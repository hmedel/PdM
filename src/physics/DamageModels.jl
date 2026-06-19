"""
    DamageModels

Física de falla (physics-of-failure) y el **puente con la verdad recuperable**.

Idea (híbrido físico-recuperable):
  - Cada componente acumula **daño** en un "reloj de daño" (edad efectiva) a una tasa que depende
    de la física de operación del agente (energía de frenado, hollín, ciclado térmico, fatiga).
  - El **umbral** de falla Θ se sortea Weibull(β, η_ref): la pieza muere cuando el daño llega a Θ.
  - Por construcción, la tasa del reloj por hora-motor es  r = exp(κ·z)·ξ,  con `z` la severidad
    física del corredor (covariable EMERGENTE) y `ξ` ruido por viaje (mean ≈ 1, de carga/clima).
    ⇒ La vida en horas-motor es  T = Θ/r ~ Weibull(β, η_ref·exp(−κ·z)).

Por tanto la **verdad recuperable** es: forma `β` (del umbral) y pendiente AFT  **γ = −κ**  con la
covariable física `z`; la `η0` base es `η_ref`. La heterogeneidad de vida (montaña vs llanura) no
se postula: emerge de a qué corredor se asignó el agente y de cuánta carga llevó.

Mecanismo físico por componente (qué stress lo mata):
  brake_pad → energía de frenado (pendiente·masa)     [mecanismo :brake]
  dpf       → hollín por ralentí/baja carga           [mecanismo :soot]
  scr       → ciclado térmico/altitud → deriva NOx     [mecanismo :thermal_scr]
  battery   → calor ambiente (β=1: sigue aleatoria)    [mecanismo :heat_batt]
"""
module DamageModels

using Random

export PhysComponent, COMPONENTS, mechanism_severity, damage_increment, trip_noise,
       telemetry_state

"""
    PhysComponent

`beta`: forma del umbral Weibull (verdad recuperable).
`eta_ref`: vida característica base en horas-efectivas (a severidad z=0). `eta0` verdad por grupo.
`kappa`: sensibilidad física ⇒ **γ verdadero = −kappa** en la covariable z.
`mechanism`: clave de severidad del corredor que acelera este componente.
"""
struct PhysComponent
    name::String
    beta::Float64
    eta_ref::Float64
    kappa::Float64
    cp::Float64
    cf::Float64
    recurrent::Bool
    classes::Set{Symbol}
    mode_id::Int
    dtc_spn::Int
    dtc_fmi::Int
    dtc_lead::Float64
    mechanism::Symbol
end

const COMPONENTS = PhysComponent[
    PhysComponent("brake_pad", 2.3, 1500.0, 1.0,  2700.0,  22700.0, true,
                  Set([:heavy_truck, :light_vehicle]), 1, 0, 0, 0.0, :brake),
    PhysComponent("dpf",       2.0, 4000.0, 0.7,  9000.0,  80000.0, true,
                  Set([:heavy_truck]), 2, 3251, 16, 0.08, :soot),
    PhysComponent("scr",       2.6, 5200.0, 0.6, 14000.0, 120000.0, true,
                  Set([:heavy_truck]), 3, 5246, 4, 0.06, :thermal_scr),
    PhysComponent("battery",   1.0, 1200.0, 0.5,  1500.0,   9000.0, true,
                  Set([:heavy_truck, :light_vehicle]), 4, 0, 0, 0.0, :heat_batt),

    # ── Extensión 2026-06-18 (investigación con sustento; β/η/costos [estimación] salvo nota; ──
    #    umbrales OEM marcados [reconfirmar] contra PDF Cummins/Bendix/J1939-71). Ver tabla PdM.
    # 5. Enfriamiento/bomba de agua: top-5 varado, #3 costo (TMC/FleetNet). β desgaste, precursor SPN 110.
    PhysComponent("cooling",     2.0,  9000.0, 0.5,   800.0,  3200.0, true,
                  Set([:heavy_truck]),  5, 110,  0, 0.10, :cooling),
    # 6. Turbo (VGT): #1-2 costo. β≈2.9 (estudio diésel marino, direccional). Precursor SPN 103 vel turbo.
    PhysComponent("turbo",       2.9,  5500.0, 0.6,  3000.0,  9000.0, true,
                  Set([:heavy_truck]),  6, 103,  1, 0.08, :soot),
    # 7. EGR válvula/cooler: alto costo escape; fatiga térmica + hollín. Precursor SPN 412 temp EGR.
    PhysComponent("egr",         1.8,  3500.0, 0.6,   700.0,  2800.0, true,
                  Set([:heavy_truck]),  7, 412,  0, 0.07, :soot),
    # 8. Sistema de combustible (filtro/bomba/rail/inyector): β≈2.8 (inyector, marino). Precursor SPN 94.
    PhysComponent("fuel_system", 2.8,  6000.0, 0.4,  1500.0,  6000.0, true,
                  Set([:heavy_truck]),  8,  94,  1, 0.06, :fatigue),
    # 9. Desgaste de motor (proxy análisis de aceite, TMC RP 318C): protege cojinetes/camisas. cf/cp alto.
    #    Precursor SPN 100 presión de aceite (+ laboratorio off-board).
    PhysComponent("oil",         3.0, 12000.0, 0.4,  1500.0, 25000.0, true,
                  Set([:heavy_truck]),  9, 100,  1, 0.05, :fatigue),
    # 10. Sistema neumático (compresor + secador): frenos = #1 fuera-de-servicio CVSA. Precursor SPN 117.
    PhysComponent("air_system",  1.7,  4500.0, 0.5,   400.0,  1600.0, true,
                  Set([:heavy_truck]), 10, 117,  1, 0.05, :brake),
    # 11. Neumáticos: #1 varado roadside (~53%, TMC). ESTADÍSTICO/intervalo: TPMS no mide profundidad de
    #     banda ⇒ SIN precursor de daño on-board (no entra a Precursors ⇒ sin CBM, decide por T*/IFR).
    PhysComponent("tire",        1.85, 3500.0, 0.5,   400.0,  1600.0, true,
                  Set([:heavy_truck, :light_vehicle]), 11, 0, 0, 0.0, :fatigue),
    # 12. Wheel-end / rodamiento de cubo: top-5 varado, wheel-off catastrófico. β≈1.1-1.5 (Lundberg-
    #     Palmgren). ESTADÍSTICO: sin SPN estándar (requiere smart-hub) ⇒ sin precursor ⇒ sin CBM.
    PhysComponent("wheel_end",   1.3,  8000.0, 0.4,   600.0,  2400.0, true,
                  Set([:heavy_truck, :light_vehicle]), 12, 0, 0, 0.0, :fatigue),
]

"""
    mechanism_severity(arch_severity, comp; rng) -> z ∈ [0,1]

Covariable física del componente: la severidad del mecanismo en el corredor del agente, con jitter
por unidad (variación entre ejemplares/instalación). Es la `z` que recupera el AFT (γ = −κ).
"""
function mechanism_severity(arch_severity::Dict{Symbol,Float64}, comp::PhysComponent;
                            rng::AbstractRNG)
    base = get(arch_severity, comp.mechanism, 0.3)
    return clamp(base + 0.05 * randn(rng), 0.0, 1.0)
end

"""
    trip_noise(rng, mass_factor; sigma=0.18) -> ξ (mean ≈ 1)

Ruido multiplicativo por viaje sobre la tasa de daño: carga del viaje (mass_factor) + dispersión
lognormal de condiciones (clima, conducción). Mean ≈ 1 para preservar γ = −κ.
"""
function trip_noise(rng::AbstractRNG, mass_factor::Float64; sigma::Float64=0.18)
    ln = exp(-sigma^2 / 2 + sigma * randn(rng))         # lognormal, E=1
    mf = exp(0.35 * (mass_factor - 1.0))                 # más carga ⇒ más daño (≈mean 1)
    return ln * mf
end

"""
    damage_increment(comp, z, trip, mass_factor, ξ) -> horas-efectivas de daño del viaje.

Reloj de daño: ΔD = engine_h · exp(κ·z) · ξ. (La física fina —energía de descenso, hollín— ya está
en `z` y en `ξ`; aquí se integra en horas-efectivas para que el umbral Weibull sea recuperable.)
"""
function damage_increment(comp::PhysComponent, z::Float64, trip, mass_factor::Float64, ξ::Float64)
    return trip.engine_h * exp(comp.kappa * z) * ξ
end

"""
    telemetry_state(trip, mass_factor, soot_frac, rng) -> NamedTuple

Señales físicamente derivadas para los frames J1939 (con ruido de sensor):
refrigerante sube con pendiente/carga/ambiente y baja par altitud; ΔP DPF sube con hollín;
voltaje de batería cae con calor.
"""
function telemetry_state(trip, mass_factor::Float64, soot_frac::Float64, rng::AbstractRNG)
    coolant = 82.0 + 6.0 * (mass_factor - 1.0) + 0.18 * max(trip.mean_ambient_c - 20.0, 0.0) +
              0.0015 * trip.max_altitude_m + 2.5 * randn(rng)
    coolant = clamp(coolant, 60.0, 110.0)
    rpm = 1250.0 + 220.0 * mass_factor + 60.0 * randn(rng)
    rpm = clamp(rpm, 600.0, 2100.0)
    volts = 13.7 - 0.02 * max(trip.mean_ambient_c - 25.0, 0.0) + 0.25 * randn(rng)
    volts = clamp(volts, 11.0, 14.8)
    dpf_dp = 2.0 + 12.0 * clamp(soot_frac, 0.0, 1.2) + 0.4 * randn(rng)   # kPa, sube con hollín
    return (coolant=coolant, rpm=rpm, volts=volts, dpf_dp=max(dpf_dp, 0.0))
end

end # module
