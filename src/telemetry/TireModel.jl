"""
    TireModel

Estado y telemetría de **llantas por posición** (el "nivel de las llantas"): profundidad de banda
(desgaste), presión y temperatura (TPMS), y modos de falla. Fundamentado en:

  - **FMCSA 49 CFR §393.75** — profundidad mínima legal de banda: **4/32″ (3.2 mm) en dirección**,
    **2/32″ (1.6 mm) en tracción/remolque**. (1/32″ = 0.794 mm.)
  - **Ley de Gay-Lussac** (gas ideal a volumen ~constante): la presión absoluta de la llanta
    escala con la temperatura absoluta. ⇒ TPMS sube con temperatura de operación/ambiente.
  - **Inflado en frío típico**: ~110 psi (758 kPa) en camión pesado; ~32 psi (220 kPa) en ligero.
  - **Desgaste** ∝ km · carga · severidad (frenado/curvas) · rugosidad; vida típica de banda a
    mínimo legal del orden de 10⁵ km (asunción de industria, etiquetada — calibrable con datos).

Modos de falla: desgaste al mínimo legal (gradual), desgaste irregular (alineación → acelerado y
asimétrico), y **blowout** (presión baja + calor + carga → súbito, en ruta = costo c_f alto).
"""
module TireModel

export TireSpec, TireState, new_tire, tread_wear_increment!, tire_pressure_kpa,
       tire_temp_c, tread_fraction, MM_PER_32

const MM_PER_32 = 0.79375    # 1/32 de pulgada en mm

"Parámetros de una llanta según su posición y clase de vehículo."
struct TireSpec
    position::String         # steer_left, drive_axle_right, front_left (ligero), ...
    new_tread_mm::Float64
    legal_min_mm::Float64
    cold_kpa::Float64        # presión de inflado en frío (referencia 20 °C)
    base_wear_mm_per_kkm::Float64   # desgaste base (mm por 1000 km) a condición nominal
    leak_kpa_per_30d::Float64       # fuga lenta
    misalign::Float64        # 0 = alineada; >0 acelera y vuelve irregular el desgaste
end

"Estado dinámico de una llanta."
mutable struct TireState
    spec::TireSpec
    tread_mm::Float64
    cum_km::Float64
end

"""
    new_tire(position, class; rng) -> TireState

Crea una llanta nueva para la posición/clase. Inflado, banda y desgaste por defecto (con jitter de
ejemplar) según FMCSA + valores de industria.
"""
function new_tire(position::String, class::Symbol; rng)
    steer = occursin("steer", position) || occursin("front", position)
    if class == :light_vehicle
        spec = TireSpec(position, 8.0, 1.6, 220.0, 0.045 * (0.9 + 0.2 * rand(rng)),
                        5.0, rand(rng) < 0.12 ? 0.4 * rand(rng) : 0.0)
    else
        new_t = steer ? 14.3 : 20.6          # 18/32″ dirección, 26/32″ tracción
        mint  = steer ? 3.2 : 1.6            # FMCSA 4/32″ vs 2/32″
        wear  = (steer ? 0.11 : 0.085) * (0.9 + 0.2 * rand(rng))   # mm/1000 km (dir. desgasta más)
        spec = TireSpec(position, new_t, mint, 758.0, wear, 4.0,
                        rand(rng) < 0.10 ? 0.5 * rand(rng) : 0.0)
    end
    return TireState(spec, spec.new_tread_mm, 0.0)
end

"""
    tread_wear_increment!(tire, km, load_factor, severity, roughness_iri) -> mm desgastados

Avanza el desgaste de banda del viaje. `load_factor` ~ masa/ref (>1 cargado), `severity` ∈ [0,1]
(frenado/curvas del corredor), `roughness_iri` (pavimento). La desalineación lo acelera.
"""
function tread_wear_increment!(t::TireState, km::Float64, load_factor::Float64,
                               severity::Float64, roughness_iri::Float64)
    f = load_factor * (0.7 + 0.9 * severity) * (0.85 + 0.10 * roughness_iri) * (1 + 1.5 * t.spec.misalign)
    dmm = t.spec.base_wear_mm_per_kkm * (km / 1000) * f
    t.tread_mm = max(0.0, t.tread_mm - dmm)
    t.cum_km += km
    return dmm
end

"Fracción de banda restante sobre el rango útil (1 = nueva, 0 = en el mínimo legal)."
tread_fraction(t::TireState) =
    clamp((t.tread_mm - t.spec.legal_min_mm) / (t.spec.new_tread_mm - t.spec.legal_min_mm), 0.0, 1.0)

"""
    tire_temp_c(ambient_c, speed_kph, load_factor) -> °C

Temperatura de operación de la llanta: ambiente + calentamiento por flexión (∝ velocidad·carga).
"""
tire_temp_c(ambient_c::Float64, speed_kph::Float64, load_factor::Float64) =
    ambient_c + (speed_kph / 100) * 22 * load_factor

"""
    tire_pressure_kpa(tire, temp_c; days_since_service) -> kPa (manométrica)

Presión TPMS: inflado en frío corregido por temperatura (Gay-Lussac, en presión ABSOLUTA) menos
fuga lenta acumulada. `temp_c` es la temperatura de la llanta.
"""
function tire_pressure_kpa(t::TireState, temp_c::Float64; days_since_service::Float64=15.0)
    p_abs_cold = t.spec.cold_kpa + 101.3            # absoluta a 20 °C
    p_abs = p_abs_cold * (273.15 + temp_c) / (273.15 + 20.0)   # Gay-Lussac
    leak = t.spec.leak_kpa_per_30d * (days_since_service / 30)
    return max(p_abs - 101.3 - leak, 0.0)           # de vuelta a manométrica
end

end # module
