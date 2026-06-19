"""
    Diagnostics

Capa de **estado de salud** del vehículo y **señales precursoras de falla** — lo que hace que la
telemetría sea *útil para mantenimiento predictivo*, no solo bonita. Cada vehículo arranca con un
estado físico distinto (flota usada, heterogénea) y su salud **evoluciona** con km, horas, carga,
ralentí y clima. De ese estado salen señales OBD/CAN que **tienden hacia la falla** (la materia
prima que consumirá el modelo estadístico).

Mecanismos (con sustento):
  - **Obstrucción de filtros** (aire/aceite/combustible) ∝ km y contaminación ⇒ ΔP sube
    (un filtro tapado restringe el flujo; señal directa de servicio).
  - **Blowby / desgaste de anillos** ∝ horas-motor ⇒ **presión de cárter** (SPN 101) sube
    (indicador clásico de salud de la cámara de combustión).
  - **Ceniza DPF** ∝ combustible quemado (permanente, no se quema en regen) ⇒ ΔP DPF sube,
    acorta intervalos de regen (SAE/EPA: la ceniza limita la vida del DPF).
  - **Salud de batería (SoH)** baja con edad y **calor** (Arrhenius); ⇒ voltaje de arranque cae.
  - **Desgaste de turbo** ∝ horas ⇒ deriva de velocidad/boost respecto al comandado.
  - **Balatas / aire de frenos**: balata ∝ energía de frenado; presión de reservorio cicla.

Los rangos están calibrados a literatura/operación típica (ver Sustento_Fisico_Telemetria.md §3,5).
"""
module Diagnostics

using Random

# ── ROL ARQUITECTÓNICO (NO es un reloj de decisión) ─────────────────────────────────────────────
# `HealthState` es el motor de degradación del GENERADOR DE TELEMETRÍA STANDALONE (`TelemetrySim`:
# showcase + rutas Valhalla), un micro-simulador autónomo que NO tiene un sustrato `LifeProcess`
# detrás. Sus leyes propias (blowby∝horas, ceniza∝combustible, balata∝brake_kj…) son CORRECTAS en
# ese contexto: producen datos OBD/CAN realistas y, por diseño, NO alimentan ninguna decisión de
# mantenimiento. No es el "segundo reloj paralelo" que la auditoría señaló: esa incongruencia vivía
# en el camino de decisión y ya está cerrada.
#
# El CAMINO CANÓNICO DE DECISIÓN es otro y está unificado: `Precursors.reading(comp, f)` con
# f = Dcum/Θ del MISMO reloj que causa la falla (ver run_unified.jl y Arquitectura_Unificada_Merge.md);
# ahí telemetría, falla y CBM comparten un solo reloj. Regla: usa Precursors+LifeProcess para
# decisión/economía; usa Diagnostics/TelemetrySim para generar datasets de telemetría.
export HealthState, initial_health, evolve_health!, diagnostic_signals

"Estado de salud (lento) de un vehículo. Fracciones 0..1 salvo donde se indique."
mutable struct HealthState
    odo0_km::Float64           # odómetro inicial (flota usada → heterogeneidad)
    engh0_h::Float64           # horas-motor iniciales
    air_filter_clog::Float64   # 0 limpio … 1 tapado
    oil_filter_clog::Float64
    fuel_filter_clog::Float64
    blowby::Float64            # 0 sano … 1 desgaste severo de anillos
    dpf_ash::Float64           # 0 … 1 (ceniza permanente)
    battery_soh::Float64       # 1 nueva … 0 muerta
    turbo_wear::Float64        # 0 … 1
    brake_lining_mm::Float64   # espesor de balata restante (mm; nueva ~18, servicio ~3)
    km_since_oil::Float64
    km_since_fuelfilt::Float64
end

"""
    initial_health(rng; class, hot_climate=false) -> HealthState

Muestrea un estado inicial **heterogéneo y físicamente realista**: edad de flota (odómetro/horas),
y desgaste correlacionado con la edad + dispersión + (con prob.) un problema en desarrollo. Así la
flota arranca como una real: unas casi nuevas, otras a 600k km con blowby y batería floja.
"""
function initial_health(rng::AbstractRNG; class::Symbol=:heavy_truck, hot_climate::Bool=false)
    # edad de flota: mezcla de nuevas, maduras y viejas (km)
    u = rand(rng)
    odo = u < 0.3 ? 20_000 + 120_000 * rand(rng) :        # joven
          u < 0.75 ? 150_000 + 300_000 * rand(rng) :       # madura
          480_000 + 350_000 * rand(rng)                    # vieja
    age = odo / 850_000                                    # 0..~1 fracción de vida
    engh = odo / (class == :heavy_truck ? 55.0 : 35.0)     # ~km/h medio de servicio

    jit() = 0.5 + 0.5 * rand(rng)
    blowby = clamp(age * 0.6 * jit() + 0.02, 0, 1)
    soh = clamp(1 - age * 0.5 * jit() - (hot_climate ? 0.12 : 0.0) * rand(rng), 0.25, 1.0)
    ash = clamp(age * 0.7 * jit(), 0, 1)
    turbo = clamp(age * 0.4 * jit(), 0, 1)
    lining = class == :heavy_truck ? (18.0 - 14.0 * age * jit()) : (10.0 - 8.0 * age * jit())

    km_oil = 5_000 * rand(rng)                             # km desde último cambio
    km_ff = 20_000 * rand(rng)
    # un problema en desarrollo en ~18% de la flota (filtro tapándose, batería floja…)
    air_clog = clamp(0.15 * rand(rng) + (rand(rng) < 0.18 ? 0.4 * rand(rng) : 0.0), 0, 1)
    oil_clog = clamp(km_oil / 15_000, 0, 1)
    fuel_clog = clamp(km_ff / 35_000 + (rand(rng) < 0.10 ? 0.3 * rand(rng) : 0.0), 0, 1)
    rand(rng) < 0.10 && (soh = clamp(soh - 0.3 * rand(rng), 0.2, 1.0))   # batería floja

    return HealthState(odo, engh, air_clog, oil_clog, fuel_clog, blowby, ash, soh, turbo,
                       max(lining, 2.0), km_oil, km_ff)
end

"""
    evolve_health!(h, d_km, dengine_h, fuel_l, brake_kj, idle_frac, ambient_c; dusty=false)

Avanza la salud tras un viaje. Tasas calibradas a vida típica de cada ítem (servicio de filtros
~15–35k km, balata ~10⁵ km, etc.). Resetea filtros si se "sirven" (clog→0 al cruzar umbral alto).
"""
function evolve_health!(h::HealthState, d_km, dengine_h, fuel_l, brake_kj, idle_frac, ambient_c;
                        dusty::Bool=false)
    h.km_since_oil += d_km; h.km_since_fuelfilt += d_km
    h.air_filter_clog = clamp(h.air_filter_clog + d_km * (dusty ? 6e-6 : 2.5e-6), 0, 1)
    h.oil_filter_clog = clamp(h.km_since_oil / 15_000, 0, 1)
    h.fuel_filter_clog = clamp(h.km_since_fuelfilt / 32_000, 0, 1)
    h.blowby = clamp(h.blowby + dengine_h * 8e-6, 0, 1)
    h.dpf_ash = clamp(h.dpf_ash + fuel_l * 4e-7, 0, 1)
    # batería: degrada con tiempo y calor (factor Arrhenius simplificado)
    heat = max(ambient_c - 25, 0)
    h.battery_soh = clamp(h.battery_soh - dengine_h * (3e-5 + 4e-6 * heat), 0.15, 1.0)
    h.turbo_wear = clamp(h.turbo_wear + dengine_h * 5e-6, 0, 1)
    h.brake_lining_mm = max(h.brake_lining_mm - brake_kj * 2e-7, 0.5)
    # servicios automáticos (taller) al cruzar umbral
    h.air_filter_clog > 0.9 && (h.air_filter_clog = 0.05)
    h.km_since_oil > 25_000 && (h.km_since_oil = 0.0)
    h.km_since_fuelfilt > 40_000 && (h.km_since_fuelfilt = 0.0)
    return h
end

"""
    diagnostic_signals(h, base; ambient_c, cranking=false) -> NamedTuple

Señales OBD/CAN derivadas del estado de salud + estado instantáneo `base` (de Powertrain).
Cada una es un **precursor** observable de su modo de falla.
"""
function diagnostic_signals(h::HealthState, base; ambient_c::Float64, cranking::Bool=false)
    # presión de cárter (SPN 101): sano ~0–2 kPa; blowby alto hasta ~10 kPa
    crankcase = 0.3 + h.blowby * 9.5 + (base.load / 100) * 0.8
    # ΔP de filtros: suben con obstrucción y con flujo (carga)
    air_dp = 1.0 + h.air_filter_clog * 6.0 + (base.load / 100) * 1.0          # kPa
    oil_dp = 45 + h.oil_filter_clog * 240 + (base.rpm / 2000) * 25             # kPa
    fuel_dp = 18 + h.fuel_filter_clog * 200 + (base.load / 100) * 15           # kPa
    # turbo: velocidad ∝ boost; el desgaste reduce eficiencia (menos rpm por boost)
    turbo_rpm = (base.boost_kpa / 220) * 130_000 * (1 - 0.25 * h.turbo_wear)
    # batería: voltaje de arranque cae con SoH y frío
    cold = max(0, 10 - ambient_c)
    cranking_v = (cranking ? 11.6 : 12.6) - (1 - h.battery_soh) * 2.6 - cold * 0.03
    # DPF: hollín (operativo) + ceniza (permanente) → ΔP total
    soot = clamp((base.load < 30 ? 0.5 : 0.2) + 0.3, 0, 1)
    dpf_dp = 2.0 + (soot * 6 + h.dpf_ash * 8) * (0.8 + 0.4 * base.load / 100)  # kPa
    trans_oil = clamp(base.coolant_set + 6 + (base.load / 100) * 20, 60, 130)  # °C

    return (crankcase_kpa=crankcase, air_filt_dp_kpa=air_dp, oil_filt_dp_kpa=oil_dp,
            fuel_filt_dp_kpa=fuel_dp, turbo_rpm=turbo_rpm, cranking_v=cranking_v,
            dpf_ash_pct=h.dpf_ash * 100, dpf_dp_kpa=dpf_dp, batt_soh=h.battery_soh,
            brake_lining_mm=h.brake_lining_mm, trans_oil_c=trans_oil)
end

end # module
