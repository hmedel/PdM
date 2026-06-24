"""
    FleetSimulator

Simulador **basado en agentes** de una flotilla de camiones de transporte, con **física de falla**
(physics-of-failure), para producir datos sintéticos realistas y poner a prueba el algoritmo de
mantenimiento predictivo contra **verdad conocida**.

Cada camión es un agente con tipo, masa en vacío y **carga variable por viaje**, asignado a un
**corredor tipo Norteamérica** (montaña/llanura/desierto/urbano/rolling — ver RouteNetwork). Cada
día conduce un viaje: acumula horas-motor y km, y sus componentes **acumulan daño físico** (energía
de frenado, hollín, ciclado térmico, fatiga). La pieza falla cuando el daño cruza un umbral; la vida
NO se postula, **emerge** del corredor y de la carga. Telemetría J1939 derivada de la física (con
ruido de sensor) que hace round-trip por el decoder verificado `J1939.jl`.

Híbrido físico-recuperable (Brief §1.2): el umbral de falla es Weibull(β, η_ref), de modo que la
**forma β y la pendiente AFT γ = −κ** (con la covariable física `z` del corredor) siguen siendo
verdad conocida y RECUPERABLE por un ajustador independiente — mientras la heterogeneidad de vida
es genuinamente física. Ver DamageModels para la derivación.

Censura por la derecha, truncamiento por la izquierda y recurrencia por posición son ciudadanos de
primera clase. battery tiene β=1 a propósito (falla aleatoria): el algoritmo debe REHUSAR preventivo.
Escala de vida primaria: horas-motor (decisión del simulador; Brief §8.1).
"""
module FleetSimulator

using Random
using Dates

using ..J1939
using ..RouteNetwork
using ..TruckAgent
using ..DamageModels

export VehicleRec, PositionRec, InstanceRec, EventRec, SnapshotRec, FrameRec,
       GroundTruth, SimConfig, SimOutput, SurvivalRecord, simulate_fleet, FAILURE_MODES,
       encode_le, make_frame, make_id, frame_hours, frame_eec1, frame_et1, frame_vep1

# ===========================================================================
# Encoder J1939 — inverso EXACTO del decoder de J1939.jl (round-trip probado)
# ===========================================================================

encode_le(raw::Integer, n::Int) = digits(UInt8, raw; base=256, pad=n)

function make_frame(sigs::Vector{<:Tuple})
    frame = fill(0xFF, 8)
    for (sb1, n, scale, offset, phys) in sigs
        raw = round(Int, (phys - offset) / scale)
        raw = clamp(raw, 0, (1 << (8n)) - 3)
        bytes = encode_le(raw, n)
        @inbounds for i in 0:(n - 1)
            frame[sb1 + i] = bytes[i + 1]
        end
    end
    return frame
end

make_id(prio::Int, pgn::Int, sa::Int) = UInt32((prio << 26) | ((pgn & 0xFFFF) << 8) | sa)

frame_hours(h::Real)     = (make_id(6, 65253, 0), make_frame([(1, 4, 0.05,   0.0,   Float64(h))]))
frame_eec1(rpm::Real)    = (make_id(3, 61444, 0), make_frame([(4, 2, 0.125,  0.0,   Float64(rpm))]))
frame_et1(coolant::Real) = (make_id(6, 65262, 0), make_frame([(1, 1, 1.0,   -40.0,  Float64(coolant))]))
frame_vep1(volts::Real)  = (make_id(6, 65271, 0), make_frame([(5, 2, 0.05,   0.0,   Float64(volts))]))

# ===========================================================================
# Modos de falla (FMECA) — espejo de la semilla del esquema WS-A §5
# ===========================================================================
const FAILURE_MODES = Dict(
    1 => (code="BRK_PAD_WEAR", desc="desgaste de balata al mínimo de espesor",            sev=6, det=4),
    2 => (code="DPF_SAT",      desc="saturación / regeneración fallida del DPF",            sev=6, det=3),
    3 => (code="NOX_DRIFT",    desc="deriva NOx / derate SCR — unidad puede quedar varada", sev=9, det=2),
    4 => (code="BATT_DEGRADE", desc="caída de capacidad / falla de arranque (aleatoria)",   sev=5, det=6),
)

# ===========================================================================
# Registros de salida (espejo del esquema WS-A) — idénticos al motor estadístico
# ===========================================================================

struct VehicleRec
    vehicle_id::String
    class::Symbol
    brand::String
    model::String              # tipo + marca (ej. "Class8_Sleeper/Freightliner")
    model_year::Int
    gvwr_kg::Float64
    protocol::Symbol
    onboarded_at::Date
    route_severity::Float64     # severidad compuesta del corredor (emergente)
    hours_per_day::Float64      # horas-motor/día medias (emergente)
    driving_index::Float64      # índice de estilo de manejo del conductor (OBD/CAN-derivado, 0..1)
end

struct PositionRec
    position_id::Int
    vehicle_id::String
    component_type::String
    location::String
end

struct InstanceRec
    instance_id::Int
    position_id::Int
    part_number::String
    supplier::String
    install_time::Date
    install_known::Bool
    install_engine_h::Float64
    removal_time::Union{Date,Nothing}
end

struct EventRec
    event_id::Int
    instance_id::Int
    type::Symbol
    event_time::Date
    onset_lower::Union{Date,Nothing}
    onset_upper::Union{Date,Nothing}
    engine_h::Float64
    odo_km::Float64
    mode_id::Int
    restoration_q::Float64
    cost_parts::Float64
    cost_labor::Float64
    cost_towing::Float64
    downtime_h::Float64
    in_route::Bool
    cost_fine::Float64
    source::Symbol
    dtc_spn::Int
    dtc_fmi::Int
end

struct SnapshotRec
    vehicle_id::String
    ts::Date
    engine_h::Float64
    odo_km::Float64
    brake_energy_cum::Float64    # PROXY ordinal sin calibrar (energía de descenso real integrada)
    rainflow_miner_cum::Float64  # PROXY ordinal sin calibrar (dosis de rugosidad·masa)
    route_severity::Float64
end

struct FrameRec
    vehicle_id::String
    ts::Date
    can_id::UInt32
    data::Vector{UInt8}
end

"La tripleta derivada que consume el ajustador. `route_severity` = covariable física `z` del componente."
struct SurvivalRecord
    instance_id::Int
    component_type::String
    class::Symbol
    brand::String
    model::String
    route_severity::Float64     # z (covariable física específica del mecanismo del componente)
    driving_index::Float64      # covariable de ESTILO DE MANEJO (OBD/CAN-derivada, 0=suave..1=agresivo)
    entry_age::Float64          # horas-motor (truncamiento por la izquierda)
    exit_age::Float64           # horas-motor (evento o censura) — EMERGENTE de la física
    status::Int
    entry_imputed::Bool
end

struct GroundTruth
    eta0::Dict{Tuple{Symbol,String,String},Float64}   # η_ref por (clase, marca, componente)
    comp::Dict{String,NamedTuple{(:beta,:gamma,:cp,:cf),Tuple{Float64,Float64,Float64,Float64}}}
end

struct SimConfig
    n_vehicles::Int
    horizon_days::Int
    start_date::Date
    seed::Int
    f_trunc::Float64
    f_stagger::Float64
    snapshot_every_days::Int
    inspect_every_days::Int
    drive_spread::Float64       # ancho de heterogeneidad de manejo (0 = sin efecto; 1 = índice en [0,1])
end

SimConfig(; n_vehicles=200, horizon_days=730, start_date=Date(2024, 6, 17), seed=20240617,
            f_trunc=0.30, f_stagger=0.25, snapshot_every_days=14, inspect_every_days=90,
            drive_spread=0.0) =
    SimConfig(n_vehicles, horizon_days, start_date, seed, f_trunc, f_stagger,
              snapshot_every_days, inspect_every_days, drive_spread)

struct SimOutput
    config::SimConfig
    vehicles::Vector{VehicleRec}
    positions::Vector{PositionRec}
    instances::Vector{InstanceRec}
    events::Vector{EventRec}
    snapshots::Vector{SnapshotRec}
    frames::Vector{FrameRec}
    survival::Vector{SurvivalRecord}
    truth::GroundTruth
end

# muestreo Weibull por inversa: L = η·(−ln U)^(1/β)
@inline weibull(rng, β, η) = η * (-log(rand(rng)))^(1 / β)

# ===========================================================================
# Simulación basada en agentes
# ===========================================================================

const ROUTE_KEYS = collect(keys(RouteNetwork.ARCHETYPES))

"""
    simulate_fleet(cfg::SimConfig=SimConfig()) -> SimOutput

Corre la simulación agente-físico. Determinista dada `cfg.seed`.
"""
function simulate_fleet(cfg::SimConfig=SimConfig())
    rng = MersenneTwister(cfg.seed)
    sim_end = cfg.start_date + Day(cfg.horizon_days)
    comps = DamageModels.COMPONENTS

    # --- Ground truth: η_ref por (clase, marca, componente) con dispersión entre marcas ---
    eta0 = Dict{Tuple{Symbol,String,String},Float64}()
    for t in TruckAgent.TRUCK_TYPES, b in t.brands, c in comps
        t.class in c.classes || continue
        key = (t.class, b, c.name)
        haskey(eta0, key) && continue
        eta0[key] = c.eta_ref * (0.85 + 0.30 * rand(rng))
    end
    # γ verdadero = −κ por componente
    compmap = Dict(c.name => (beta=c.beta, gamma=-c.kappa, cp=c.cp, cf=c.cf) for c in comps)
    truth = GroundTruth(eta0, compmap)

    vehicles  = VehicleRec[]
    positions = PositionRec[]
    instances = InstanceRec[]
    events    = EventRec[]
    snapshots = SnapshotRec[]
    frames    = FrameRec[]
    survival  = SurvivalRecord[]

    pos_counter = 0; inst_counter = 0; evt_counter = 0
    nextpos()  = (pos_counter += 1)
    nextinst() = (inst_counter += 1)
    nextevt()  = (evt_counter += 1)

    for k in 1:cfg.n_vehicles
        ttype = TruckAgent.TRUCK_TYPES[rand(rng, 1:length(TruckAgent.TRUCK_TYPES))]
        brand = ttype.brands[rand(rng, 1:length(ttype.brands))]
        arch  = RouteNetwork.ARCHETYPES[ROUTE_KEYS[rand(rng, 1:length(ROUTE_KEYS))]]
        myear = 2018 + rand(rng, 0:6)
        gvwr  = ttype.curb_kg + ttype.payload_max_kg
        vid   = string("VEH-", lpad(k, 4, '0'))
        xveh  = RouteNetwork.route_severity_index(arch)

        # Estilo de manejo del conductor (trait por unidad) + índice OBSERVABLE (OBD/CAN-derivado, con
        # ruido de agregación). Guarda de RNG: con drive_spread=0 NO se consume aleatorio ⇒ stream y
        # resultados idénticos al modelo sin manejo (retrocompat exacta). `dterm` = κ_drive·(index−0.5).
        if cfg.drive_spread > 0
            drive_style   = clamp(0.5 + cfg.drive_spread * (rand(rng) - 0.5), 0.0, 1.0)
            driving_index = clamp(drive_style + 0.03 * randn(rng), 0.0, 1.0)
        else
            drive_style = 0.5; driving_index = 0.5
        end
        dterm(c) = DamageModels.drive_sensitivity(c.mechanism) * (driving_index - 0.5)

        onboard = (rand(rng) < cfg.f_stagger) ?
                  cfg.start_date + Day(rand(rng, 0:Int(round(0.3 * cfg.horizon_days)))) :
                  cfg.start_date
        ndays = Dates.value(sim_end - onboard)

        # covariable física z por componente (emergente del corredor) + jitter por unidad
        zc = Dict(c.name => DamageModels.mechanism_severity(arch.severity, c; rng=rng)
                  for c in comps if ttype.class in c.classes)

        # --- conducir el horizonte: series acumuladas de horas-motor, km y DAÑO por componente ---
        cum_h  = Vector{Float64}(undef, ndays + 1); cum_h[1]  = 0.0
        cum_km = Vector{Float64}(undef, ndays + 1); cum_km[1] = 0.0
        Dcum = Dict(name => (v = Vector{Float64}(undef, ndays + 1); v[1] = 0.0; v)
                    for name in keys(zc))
        be_cum = Vector{Float64}(undef, ndays + 1); be_cum[1] = 0.0   # proxy energía de frenado
        rf_cum = Vector{Float64}(undef, ndays + 1); rf_cum[1] = 0.0   # proxy fatiga (rugosidad·masa)
        last_trip = nothing
        loaded = true
        for d in 1:ndays
            day = onboard + Day(d - 1)
            wd = Dates.dayofweek(day)
            operates = wd <= 6 ? rand(rng) < 0.93 : rand(rng) < 0.22
            if operates
                summer = 4 <= Dates.month(day) <= 9
                trip = RouteNetwork.sample_trip(rng, arch; summer=summer)
                payload = TruckAgent.sample_payload(rng, ttype; loaded=loaded)
                mf = TruckAgent.mass_factor(ttype, payload)
                ξ = DamageModels.trip_noise(rng, mf)
                loaded = !loaded                         # ida cargado / vuelta vacío
                cum_h[d + 1]  = cum_h[d] + trip.engine_h
                cum_km[d + 1] = cum_km[d] + trip.dist_km
                for (name, z) in zc
                    c = comps[findfirst(c -> c.name == name, comps)]
                    Dcum[name][d + 1] = Dcum[name][d] +
                        DamageModels.damage_increment(c, z, trip, mf, ξ; drive_term=dterm(c))
                end
                be_cum[d + 1] = be_cum[d] + trip.descent_energy_kjpt * mf
                rf_cum[d + 1] = rf_cum[d] + trip.mean_roughness_iri * mf * trip.dist_km * 1e-3
                last_trip = (trip=trip, mf=mf)
            else
                cum_h[d + 1] = cum_h[d]; cum_km[d + 1] = cum_km[d]
                for name in keys(zc); Dcum[name][d + 1] = Dcum[name][d]; end
                be_cum[d + 1] = be_cum[d]; rf_cum[d + 1] = rf_cum[d]
            end
        end
        total_h = cum_h[end]
        mean_hpd = total_h / max(ndays, 1)
        model = string(ttype.name, "/", brand)
        push!(vehicles, VehicleRec(vid, ttype.class, brand, model, myear, gvwr, ttype.protocol,
              onboard, round(xveh, digits=4), round(mean_hpd, digits=3), round(driving_index, digits=4)))

        # --- snapshots periódicos (usage_snapshot) con proxies físicos reales (ordinales) ---
        for d in 0:cfg.snapshot_every_days:ndays
            push!(snapshots, SnapshotRec(vid, onboard + Day(d), cum_h[d + 1], cum_km[d + 1],
                  be_cum[d + 1], rf_cum[d + 1], xveh))
        end

        # --- telemetría J1939 cruda (estado al cierre), derivada de la física + ruido ---
        soot_alive = 0.0
        if last_trip !== nothing
            ts = DamageModels.telemetry_state(last_trip.trip, last_trip.mf, soot_alive, rng)
            push!(frames, FrameRec(vid, sim_end, frame_hours(total_h)...))
            push!(frames, FrameRec(vid, sim_end, frame_eec1(ts.rpm)...))
            push!(frames, FrameRec(vid, sim_end, frame_vep1(ts.volts)...))
            if ttype.protocol == :j1939
                push!(frames, FrameRec(vid, sim_end, frame_et1(ts.coolant)...))
            end
        end

        # primer día (índice) en que el daño efectivo de un componente cruza `target`
        function cross_day(name, D0, a0_D, target)
            Dc = Dcum[name]
            for d in 0:ndays
                if Dc[d + 1] - D0 + a0_D >= target
                    return d
                end
            end
            return nothing
        end

        # --- cada componente que porta el tipo, en cada posición ---
        for c in comps
            ttype.class in c.classes || continue
            z = zc[c.name]
            ηref_g = eta0[(ttype.class, brand, c.name)]
            η_i = ηref_g * exp(-c.kappa * z - dterm(c))  # vida característica (ruta + manejo) en horas-motor
            locs = c.name == "brake_pad" ? ttype.brake_positions :
                   c.name == "dpf" ? ["exhaust"] :
                   c.name == "scr" ? ["aftertreatment"] : ["chassis"]

            for loc in locs
                pid = nextpos()
                push!(positions, PositionRec(pid, vid, c.name, loc))

                preexist = rand(rng) < cfg.f_trunc
                a0_h = preexist ? 0.6 * η_i * rand(rng) : 0.0       # edad preexistente (horas-motor)
                a0_D = a0_h * exp(c.kappa * z + dterm(c))            # ≈ daño preexistente (efectivo)
                install_day = 0
                D0 = Dcum[c.name][1]
                cumh0 = cum_h[1]
                install_known = !preexist
                install_date = onboard
                entry_age = a0_h

                while true
                    Θ = weibull(rng, c.beta, ηref_g)                 # umbral de falla (efectivo)
                    while a0_D > 0 && Θ <= a0_D
                        Θ = weibull(rng, c.beta, ηref_g)
                    end

                    iid = nextinst()
                    inst_h = max(0.0, cumh0)
                    inst_km = cum_km[install_day + 1]
                    push!(instances, InstanceRec(iid, pid, part_number(c, brand), supplier(rng, c),
                          install_date, install_known, inst_h, nothing))
                    push!(events, EventRec(nextevt(), iid, :install, install_date, nothing, nothing,
                          inst_h, inst_km, 0, 0.0, 0.0, 0.0, 0.0, 0.0, false, 0.0,
                          install_known ? :shop_order : :manual, 0, 0))

                    fday = cross_day(c.name, D0, a0_D, Θ)
                    last_good = nothing

                    if fday === nothing
                        obs_h = a0_h + (cum_h[end] - cumh0)
                        push!(survival, SurvivalRecord(iid, c.name, ttype.class, brand, model, z,
                              driving_index, entry_age, obs_h, 0, !install_known))
                        if c.mode_id == 1
                            last_good = emit_inspections!(events, nextevt, iid, onboard, ndays,
                                            cum_h, cum_km, cfg.inspect_every_days, sim_end)
                        end
                        break
                    end

                    fdate = onboard + Day(fday)
                    exit_h = a0_h + (cum_h[fday + 1] - cumh0)

                    # DTC con lead time (cobertura diagnóstica): cruza Θ·(1−lead)
                    if c.dtc_spn != 0 && c.dtc_lead > 0
                        dday = cross_day(c.name, D0, a0_D, Θ * (1 - c.dtc_lead))
                        if dday !== nothing && onboard + Day(dday) <= sim_end
                            push!(events, EventRec(nextevt(), iid, :auto_dtc, onboard + Day(dday),
                                  nothing, onboard + Day(dday), cum_h[dday + 1], cum_km[dday + 1],
                                  0, 0.0, 0.0, 0.0, 0.0, 0.0, false, 0.0, :auto_dtc, c.dtc_spn, c.dtc_fmi))
                        end
                    end
                    if c.mode_id == 1
                        last_good = emit_inspections!(events, nextevt, iid, onboard, fday,
                                        cum_h, cum_km, cfg.inspect_every_days, sim_end)
                    end

                    in_route = rand(rng) < (0.25 + 0.5 * z)
                    parts = max(0.0, c.cp * (0.55 + 0.1 * randn(rng)))
                    labor = max(0.0, c.cp * (0.45 + 0.1 * randn(rng)))
                    towing = in_route ? c.cf * 0.15 * (0.8 + 0.4 * rand(rng)) : 0.0
                    fine = (in_route && c.mode_id == 3) ? 8000.0 : 0.0
                    downtime = in_route ? 6.0 + 8.0 * rand(rng) : 2.0 + 2.0 * rand(rng)

                    push!(events, EventRec(nextevt(), iid, :failure, fdate, last_good, fdate,
                          cum_h[fday + 1], cum_km[fday + 1], c.mode_id, 0.0,
                          parts, labor, towing, downtime, in_route, fine,
                          c.dtc_spn != 0 ? :auto_dtc : :dvir, c.dtc_spn, c.dtc_fmi))

                    push!(survival, SurvivalRecord(iid, c.name, ttype.class, brand, model, z,
                          driving_index, entry_age, exit_h, c.mode_id, !install_known))

                    instances[iid] = InstanceRec(iid, pid, instances[iid].part_number,
                          instances[iid].supplier, instances[iid].install_time,
                          instances[iid].install_known, instances[iid].install_engine_h, fdate)

                    c.recurrent || break
                    push!(events, EventRec(nextevt(), iid, :corrective_replace, fdate, nothing, fdate,
                          cum_h[fday + 1], cum_km[fday + 1], c.mode_id, 0.0, parts, labor, 0.0, 0.0,
                          in_route, 0.0, :shop_order, 0, 0))

                    fday >= ndays && break
                    # siguiente instancia desde edad 0 (renovación q=0)
                    install_day = fday
                    D0 = Dcum[c.name][fday + 1]
                    cumh0 = cum_h[fday + 1]
                    a0_h = 0.0; a0_D = 0.0; entry_age = 0.0
                    install_known = true; install_date = fdate
                end
            end
        end
    end

    return SimOutput(cfg, vehicles, positions, instances, events, snapshots, frames, survival, truth)
end

# --- helpers ---

part_number(c, brand::String) = string(uppercase(first(c.name, 3)), "-", brand[1:min(3, end)], "-STD")
function supplier(rng, c)
    sup = c.name == "brake_pad" ? ["Bosch", "Brembo", "Meritor"] :
          c.name == "battery"   ? ["LTH", "Bosch"] : ["OEM"]
    sup[rand(rng, 1:length(sup))]
end

"Inspecciones DVIR periódicas (estado bueno → cota inferior del onset). Devuelve la última fecha buena."
function emit_inspections!(events, nextevt, iid, onboard, until_day, cum_h, cum_km, every, sim_end)
    last_good = nothing
    d = every
    while d <= until_day
        idate = onboard + Day(d)
        idate > sim_end && break
        push!(events, EventRec(nextevt(), iid, :inspection, idate, nothing, nothing,
              cum_h[d + 1], cum_km[d + 1], 0, 0.0, 0.0, 0.0, 0.0, 0.0, false, 0.0, :dvir, 0, 0))
        last_good = idate
        d += every
    end
    return last_good
end

end # module
