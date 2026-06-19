"""
    LifeProcess

Sustrato físico para el **estudio contrafactual gemelo**: simula la física UNA SOLA VEZ
(corredor, viajes, reloj de daño, umbrales de falla Θ) y la expone de forma que distintas
**políticas de mantenimiento** se evalúen sobre EXACTAMENTE el mismo mundo — números aleatorios
comunes (CRN; Glasserman & Yao 1992). Así la diferencia entre brazos (reactivo vs preventivo) es el
efecto de la política, no ruido de Monte Carlo (la varianza de la diferencia cae ~80%).

Para cada (vehículo, posición) se pre-sortean: la línea de tiempo de horas-motor `cum_h`, el daño
acumulado `Dcum` (compartido por componente del vehículo), la secuencia de **umbrales** Θ (uno por
instancia futura), y los flags/costos de cada falla potencial (`in_route`, `cf_real`, …). La capa
de política (Policy) es entonces un post-procesador determinista sobre este sustrato.

Reutiliza los modelos físicos (RouteNetwork, TruckAgent, DamageModels) — única fuente de verdad.
"""
module LifeProcess

using Random
using Dates

using ..RouteNetwork
using ..TruckAgent
using ..DamageModels

export PositionLife, VehicleLife, LifeConfig, generate_life_processes, GroundTruthE

struct LifeConfig
    n_vehicles::Int
    horizon_days::Int
    start_date::Date
    seed::Int
    f_trunc::Float64
    f_stagger::Float64
    max_instances::Int          # umbrales pre-sorteados por posición (cota de renovaciones)
end

LifeConfig(; n_vehicles=200, horizon_days=1825, start_date=Date(2024, 1, 1), seed=20240617,
             f_trunc=0.30, f_stagger=0.25, max_instances=80) =
    LifeConfig(n_vehicles, horizon_days, start_date, seed, f_trunc, f_stagger, max_instances)

"""
Proceso de vida de una posición (slot físico) bajo CRN. `cum_h` y `Dcum` se comparten por
referencia entre posiciones del mismo vehículo/componente (sin copia).
"""
struct PositionLife
    vehicle_id::String
    class::Symbol
    brand::String
    model::String
    component::String
    location::String
    onboard_day::Int            # offset (días) desde start_date
    ndays::Int
    z::Float64                  # covariable física (severidad del corredor para el mecanismo)
    beta::Float64
    eta_ref::Float64            # escala base del umbral (grupo)
    eta_i::Float64              # vida característica en horas-motor = eta_ref·exp(−κ z)
    kappa::Float64
    cp::Float64
    cf::Float64
    mode_id::Int
    dtc_spn::Int
    recurrent::Bool
    cum_h::Vector{Float64}
    Dcum::Vector{Float64}
    a0_D::Float64               # daño preexistente (truncamiento izq.)
    a0_h::Float64              # edad preexistente en horas-motor
    thresholds::Vector{Float64}
    in_route::Vector{Bool}
    cf_real::Vector{Float64}
    cp_real::Vector{Float64}
    downtime::Vector{Float64}
    pred_noise::Vector{Float64}   # error de predicción de la RUL por instancia (lognormal, mean≈1)
end

"Serie operativa diaria de un vehículo (Paso 1 del merge): alimenta las señales Powertrain."
struct VehicleLife
    vehicle_id::String
    class::Symbol
    engine_kw::Float64
    curb_kg::Float64
    brand::String
    route_speed::Float64
    route_grade::Float64
    onboard_day::Int
    ndays::Int
    eng_h_day::Vector{Float64}
    alt_day::Vector{Float64}
    ambient_day::Vector{Float64}
    mass_day::Vector{Float64}
end

struct GroundTruthE
    eta0::Dict{Tuple{Symbol,String,String},Float64}
    comp::Dict{String,NamedTuple{(:beta,:gamma,:cp,:cf),Tuple{Float64,Float64,Float64,Float64}}}
end

@inline weibull(rng, β, η) = η * (-log(rand(rng)))^(1 / β)

const ROUTE_KEYS = collect(keys(RouteNetwork.ARCHETYPES))

"""
    generate_life_processes(cfg) -> (Vector{PositionLife}, GroundTruthE)

Genera el sustrato físico de la flota (CRN). Determinista dada `cfg.seed`.
"""
function generate_life_processes(cfg::LifeConfig=LifeConfig())
    rng = MersenneTwister(cfg.seed)
    comps = DamageModels.COMPONENTS

    eta0 = Dict{Tuple{Symbol,String,String},Float64}()
    for t in TruckAgent.TRUCK_TYPES, b in t.brands, c in comps
        t.class in c.classes || continue
        key = (t.class, b, c.name); haskey(eta0, key) && continue
        eta0[key] = c.eta_ref * (0.85 + 0.30 * rand(rng))
    end
    compmap = Dict(c.name => (beta=c.beta, gamma=-c.kappa, cp=c.cp, cf=c.cf) for c in comps)
    truth = GroundTruthE(eta0, compmap)

    lives = PositionLife[]
    vehlives = VehicleLife[]

    for k in 1:cfg.n_vehicles
        ttype = TruckAgent.TRUCK_TYPES[rand(rng, 1:length(TruckAgent.TRUCK_TYPES))]
        brand = ttype.brands[rand(rng, 1:length(ttype.brands))]
        arch  = RouteNetwork.ARCHETYPES[ROUTE_KEYS[rand(rng, 1:length(ROUTE_KEYS))]]
        model = string(ttype.name, "/", brand)
        vid   = string("VEH-", lpad(k, 4, '0'))

        onboard = (rand(rng) < cfg.f_stagger) ? rand(rng, 0:Int(round(0.3 * cfg.horizon_days))) : 0
        ndays = cfg.horizon_days - onboard

        zc = Dict(c.name => DamageModels.mechanism_severity(arch.severity, c; rng=rng)
                  for c in comps if ttype.class in c.classes)

        # conducir el horizonte: cum_h (vehículo) y Dcum (por componente)
        cum_h = Vector{Float64}(undef, ndays + 1); cum_h[1] = 0.0
        Dcum = Dict(name => (v = Vector{Float64}(undef, ndays + 1); v[1] = 0.0; v) for name in keys(zc))
        # serie operativa diaria (Paso 1 del merge: alimenta las señales Powertrain)
        eng_h_day = zeros(ndays); alt_day = zeros(ndays); amb_day = zeros(ndays); mass_day = zeros(ndays)
        loaded = true
        for d in 1:ndays
            day = cfg.start_date + Day(onboard + d - 1)
            wd = Dates.dayofweek(day)
            operates = wd <= 6 ? rand(rng) < 0.93 : rand(rng) < 0.22
            if operates
                summer = 4 <= Dates.month(day) <= 9
                trip = RouteNetwork.sample_trip(rng, arch; summer=summer)
                payload = TruckAgent.sample_payload(rng, ttype; loaded=loaded)
                mf = TruckAgent.mass_factor(ttype, payload)
                ξ = DamageModels.trip_noise(rng, mf)
                loaded = !loaded
                cum_h[d + 1] = cum_h[d] + trip.engine_h
                eng_h_day[d] = trip.engine_h; alt_day[d] = trip.mean_altitude_m
                amb_day[d] = trip.mean_ambient_c; mass_day[d] = ttype.curb_kg + payload
                for (name, z) in zc
                    c = comps[findfirst(c -> c.name == name, comps)]
                    Dcum[name][d + 1] = Dcum[name][d] + DamageModels.damage_increment(c, z, trip, mf, ξ)
                end
            else
                cum_h[d + 1] = cum_h[d]
                for name in keys(zc); Dcum[name][d + 1] = Dcum[name][d]; end
            end
        end
        push!(vehlives, VehicleLife(vid, ttype.class, ttype.engine_kw, ttype.curb_kg, brand,
              arch.speed_kph, (arch.grade_abs[1] + arch.grade_abs[2]) / 2, onboard, ndays,
              eng_h_day, alt_day, amb_day, mass_day))

        for c in comps
            ttype.class in c.classes || continue
            z = zc[c.name]
            ηref = eta0[(ttype.class, brand, c.name)]
            η_i = ηref * exp(-c.kappa * z)
            locs = c.name == "brake_pad" ? ttype.brake_positions :
                   c.name == "dpf" ? ["exhaust"] :
                   c.name == "scr" ? ["aftertreatment"] : ["chassis"]
            for loc in locs
                preexist = rand(rng) < cfg.f_trunc
                a0_h = preexist ? 0.6 * η_i * rand(rng) : 0.0
                a0_D = a0_h * exp(c.kappa * z)
                # umbrales pre-sorteados; el primero condicionado a sobrevivir el truncamiento
                Θs = Float64[]
                for j in 1:cfg.max_instances
                    Θ = weibull(rng, c.beta, ηref)
                    if j == 1
                        while a0_D > 0 && Θ <= a0_D
                            Θ = weibull(rng, c.beta, ηref)
                        end
                    end
                    push!(Θs, Θ)
                end
                inr = Bool[rand(rng) < (0.25 + 0.5 * z) for _ in 1:cfg.max_instances]
                cfr = Float64[c.cf * (0.9 + 0.2 * rand(rng)) for _ in 1:cfg.max_instances]
                cpr = Float64[c.cp * (0.9 + 0.2 * rand(rng)) for _ in 1:cfg.max_instances]
                dwn = Float64[(inr[i] ? 6.0 + 8.0 * rand(rng) : 2.0 + 2.0 * rand(rng))
                              for i in 1:cfg.max_instances]
                prn = Float64[exp(-0.16^2 / 2 + 0.16 * randn(rng)) for _ in 1:cfg.max_instances]
                push!(lives, PositionLife(vid, ttype.class, brand, model, c.name, loc,
                      onboard, ndays, z, c.beta, ηref, η_i, c.kappa, c.cp, c.cf, c.mode_id,
                      c.dtc_spn, c.recurrent, cum_h, Dcum[c.name], a0_D, a0_h,
                      Θs, inr, cfr, cpr, dwn, prn))
            end
        end
    end
    return lives, truth, vehlives
end

end # module
