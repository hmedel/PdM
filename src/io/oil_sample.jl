"""
    OilSample

Contrato de datos de **análisis de aceite usado** (UOA) — modalidad de condición OFF-BOARD para
motor/diferencial/transmisión. Mapeo PURO de una muestra de laboratorio a una **fracción de degradación**
`f ∈ [0,1]` (0 = nuevo, 1 = en el límite condenatorio), el análogo off-board del precursor on-board
`f = Dcum/Θ` (ver `Precursors`). Sin BD ni I/O: solo el contrato y su matemática, testeable.

Diseño completo: `docs/Modalidad_Analisis_Aceite_INTERNO.md`. Límites [reconfirmar] vs TMC RP 318C/OEM.
"""
module OilSample

export OilSampleRecord, WearLimit, wear_fraction, normalize_ppm, system_fraction, DEFAULT_LIMITS

"Una muestra de análisis de aceite (una fila del contrato `pdm_oil_sample`)."
struct OilSampleRecord
    vehicle_id::String
    system::Symbol                       # :engine | :differential | :transmission
    engine_hours::Float64                # reloj de uso del vehículo a la muestra
    odometer_km::Float64
    oil_hours::Float64                   # horas sobre ESTA carga de aceite (normaliza el desgaste)
    metals_ppm::Dict{Symbol,Float64}     # :iron_fe, :copper_cu, :lead_pb, :chromium_cr, :aluminum_al…
    viscosity_cst_100c::Float64
    soot_pct::Float64
    tbn::Float64
end

"Especificación condenatoria de un indicador: línea base `b`, límite `L` y peso `w` (importancia)."
struct WearLimit
    baseline::Float64
    limit::Float64
    weight::Float64
end

"Normaliza ppm por edad de aceite a una referencia `h_ref` (ppm equivalentes a `h_ref` horas de aceite)."
normalize_ppm(ppm::Real, oil_hours::Real; h_ref::Real=250.0) =
    oil_hours > 0 ? ppm * h_ref / oil_hours : float(ppm)

"""
    wear_fraction(value_norm, lim) -> f ∈ [0,1]

Fracción de desgaste de UN indicador: 0 en la línea base, 1 en el límite condenatorio (clamp).
Análogo off-board de `f = Dcum/Θ`: `Θ ↔ lim.limit`, `Dcum ↔ value_norm − lim.baseline`.
"""
function wear_fraction(value_norm::Real, lim::WearLimit)
    den = lim.limit - lim.baseline
    den <= 0 && return 0.0
    return clamp((value_norm - lim.baseline) / den, 0.0, 1.0)
end

"""
    system_fraction(sample, limits; h_ref=250.0) -> (frac, driver)

Fracción de degradación del sistema = máximo ponderado de las fracciones por metal (cada metal apunta a
una superficie; la peor gobierna). Devuelve `(f ∈ [0,1], metal_dominante)`. `limits`: Dict metal→WearLimit.
"""
function system_fraction(sample::OilSampleRecord, limits::Dict{Symbol,WearLimit}; h_ref::Real=250.0)
    best = 0.0; driver = :none
    for (metal, lim) in limits
        haskey(sample.metals_ppm, metal) || continue
        vn = normalize_ppm(sample.metals_ppm[metal], sample.oil_hours; h_ref=h_ref)
        f = lim.weight * wear_fraction(vn, lim)
        if f > best
            best = f; driver = metal
        end
    end
    return (clamp(best, 0.0, 1.0), driver)
end

"Límites condenatorios de referencia por sistema [reconfirmar vs TMC RP 318C / OEM]."
const DEFAULT_LIMITS = Dict(
    :engine => Dict(
        :iron_fe     => WearLimit(10.0, 100.0, 1.0),
        :copper_cu   => WearLimit(5.0,   40.0, 0.8),
        :lead_pb     => WearLimit(5.0,   30.0, 0.8),
        :chromium_cr => WearLimit(2.0,   20.0, 0.7),
        :aluminum_al => WearLimit(3.0,   25.0, 0.7)),
    :differential => Dict(
        :iron_fe     => WearLimit(50.0, 300.0, 1.0),
        :copper_cu   => WearLimit(20.0, 120.0, 0.7)),
    :transmission => Dict(
        :iron_fe     => WearLimit(20.0, 150.0, 1.0),
        :copper_cu   => WearLimit(15.0,  90.0, 0.7)),
)

end # module
