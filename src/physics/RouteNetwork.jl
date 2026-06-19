"""
    RouteNetwork

Corredores de operación **tipo Norteamérica** para la simulación basada en agentes. No usa datos
geográficos externos: genera perfiles sintéticos **calibrados a estadísticas reales** (altitud,
pendiente sostenida, rugosidad del pavimento ~IRI, clima estacional, fracción de ralentí,
velocidad), y de ahí deriva los **viajes diarios** (secuencia de segmentos) que conduce cada agente.

Cada arquetipo trae además una **severidad estandarizada por mecanismo de falla** (`severity`),
que es la covariable física que acelera cada componente (frenos↔pendiente, DPF↔ralentí,
SCR↔altitud/frío, batería↔calor, fatiga↔rugosidad). Esa covariable es EMERGENTE (la fija la ruta,
no se inventa por vehículo) y es la que el ajustador AFT recupera (γ = −κ, ver DamageModels).

Arquetipos (calibrados a corredores reales de EE. UU./MX):
  :rockies_longhaul  — montaña (I-70): altitud 1.5–3.4 km, grados sostenidos 5–7%, descensos largos, frío.
  :plains_longhaul   — llanura (I-80/I-35): plano, alta velocidad sostenida, mucho km.
  :desert_southwest  — desierto (I-10): calor 30–48 °C, polvo, grados moderados.
  :urban_distribution— reparto urbano: poco km, muchas paradas, ralentí alto, pavimento irregular.
  :appalachia_regional— rolling (Apalaches): grados ondulados 3–5%, pavimento rugoso.
"""
module RouteNetwork

using Random

export RouteArchetype, ARCHETYPES, Segment, TripPhysics, sample_trip, route_severity_index

"Un segmento de viaje con sus condiciones físicas instantáneas."
struct Segment
    dist_km::Float64
    grade_pct::Float64       # + subida, − bajada
    altitude_m::Float64
    roughness_iri::Float64   # índice de rugosidad internacional (m/km); pavimento bueno ~1.5, malo ~4+
    ambient_c::Float64
    speed_kph::Float64
    idle_frac::Float64       # fracción del tiempo del segmento en ralentí (paradas/tráfico)
end

"""
    RouteArchetype

Parámetros calibrados de un corredor. `severity` da el índice de severidad ∈ ~[0,1] por mecanismo:
`:brake, :soot, :thermal_scr, :heat_batt, :fatigue` (covariable física por componente).
"""
struct RouteArchetype
    name::Symbol
    trip_km::Tuple{Float64,Float64}      # rango de km/día
    grade_abs::Tuple{Float64,Float64}    # rango de |pendiente| característica (%)
    altitude::Tuple{Float64,Float64}     # rango de altitud (m)
    roughness::Tuple{Float64,Float64}    # rango IRI
    ambient_winter::Tuple{Float64,Float64}
    ambient_summer::Tuple{Float64,Float64}
    speed_kph::Float64
    idle_frac::Float64
    descent_share::Float64               # fracción de km en descenso pronunciado (frenado)
    severity::Dict{Symbol,Float64}
end

const ARCHETYPES = Dict{Symbol,RouteArchetype}(
    :rockies_longhaul => RouteArchetype(:rockies_longhaul,
        (600.0, 1000.0), (5.0, 7.0), (1500.0, 3400.0), (1.5, 3.0), (-12.0, 8.0), (12.0, 30.0),
        92.0, 0.07, 0.35,
        Dict(:brake=>0.95, :soot=>0.35, :thermal_scr=>0.95, :heat_batt=>0.25, :fatigue=>0.45,
             :cooling=>0.85)),   # [estimación] subidas sostenidas estresan enfriamiento
    :plains_longhaul => RouteArchetype(:plains_longhaul,
        (700.0, 1150.0), (0.3, 1.2), (250.0, 800.0), (1.2, 2.2), (-8.0, 14.0), (18.0, 34.0),
        102.0, 0.05, 0.05,
        Dict(:brake=>0.15, :soot=>0.20, :thermal_scr=>0.25, :heat_batt=>0.45, :fatigue=>0.20,
             :cooling=>0.20)),   # [estimación] llano/templado: bajo estrés térmico
    :desert_southwest => RouteArchetype(:desert_southwest,
        (600.0, 1000.0), (1.0, 3.0), (200.0, 1300.0), (1.5, 2.8), (5.0, 22.0), (32.0, 48.0),
        96.0, 0.06, 0.12,
        Dict(:brake=>0.40, :soot=>0.25, :thermal_scr=>0.50, :heat_batt=>0.95, :fatigue=>0.40,
             :cooling=>0.80)),   # [estimación] calor ambiente alto estresa enfriamiento
    :urban_distribution => RouteArchetype(:urban_distribution,
        (120.0, 320.0), (1.0, 3.0), (50.0, 700.0), (2.5, 4.5), (-6.0, 16.0), (16.0, 36.0),
        34.0, 0.28, 0.30,
        Dict(:brake=>0.70, :soot=>0.95, :thermal_scr=>0.45, :heat_batt=>0.55, :fatigue=>0.75,
             :cooling=>0.50)),   # [estimación] pare-y-siga: ralentí/poco flujo de aire
    :appalachia_regional => RouteArchetype(:appalachia_regional,
        (400.0, 720.0), (3.0, 5.0), (300.0, 1200.0), (3.0, 4.5), (-10.0, 12.0), (16.0, 32.0),
        76.0, 0.10, 0.25,
        Dict(:brake=>0.75, :soot=>0.45, :thermal_scr=>0.55, :heat_batt=>0.45, :fatigue=>0.95,
             :cooling=>0.80)),   # [estimación] grados regionales empinados
)

"Resumen físico de un viaje (lo que consumen los modelos de daño y la telemetría)."
struct TripPhysics
    dist_km::Float64
    engine_h::Float64
    idle_h::Float64
    descent_energy_kjpt::Float64   # energía potencial en descensos por tonelada (∝ frenado)
    mean_altitude_m::Float64
    max_altitude_m::Float64
    mean_ambient_c::Float64
    mean_roughness_iri::Float64
    n_stops::Int
end

"Severidad compuesta del vehículo (para mostrar en la tabla vehicle), ∈ ~[0,1]."
route_severity_index(a::RouteArchetype) =
    clamp(0.30 * a.severity[:brake] + 0.20 * a.severity[:fatigue] +
          0.20 * a.severity[:thermal_scr] + 0.15 * a.severity[:soot] +
          0.15 * a.severity[:heat_batt], 0.0, 1.0)

_u(rng, lo, hi) = lo + (hi - lo) * rand(rng)

"""
    sample_trip(rng, arch; summer) -> TripPhysics

Genera un viaje diario sobre el arquetipo, integrando segmentos. La energía de descenso (frenado)
escala con la fracción de descenso y la pendiente; el ralentí y las paradas con el arquetipo.
"""
function sample_trip(rng::AbstractRNG, a::RouteArchetype; summer::Bool=true)
    dist = _u(rng, a.trip_km[1], a.trip_km[2])
    speed = a.speed_kph * (0.9 + 0.2 * rand(rng))
    drive_h = dist / speed
    idle_h = drive_h * a.idle_frac * (0.7 + 0.6 * rand(rng))
    engine_h = drive_h + idle_h

    grade = _u(rng, a.grade_abs[1], a.grade_abs[2])
    alt_lo, alt_hi = a.altitude
    mean_alt = _u(rng, alt_lo, alt_hi)
    max_alt = min(alt_hi, mean_alt + _u(rng, 100.0, 700.0))
    # energía potencial disipada en descensos por tonelada: g·Δh por km de descenso, Δh = grade%·dist
    descent_km = dist * a.descent_share * (0.8 + 0.4 * rand(rng))
    dh = (grade / 100.0) * descent_km * 1000.0                # metros de descenso acumulados
    descent_energy = 9.81 * dh / 1000.0                        # kJ por tonelada (g·Δh)
    amb_rng = summer ? a.ambient_summer : a.ambient_winter
    ambient = _u(rng, amb_rng[1], amb_rng[2])
    rough = _u(rng, a.roughness[1], a.roughness[2])
    n_stops = round(Int, (a.idle_frac * dist / max(speed, 1.0)) * 30 + 2 * rand(rng))

    return TripPhysics(dist, engine_h, idle_h, descent_energy, mean_alt, max_alt,
                       ambient, rough, n_stops)
end

end # module
