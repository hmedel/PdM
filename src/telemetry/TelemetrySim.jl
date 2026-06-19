"""
    TelemetrySim

Capa de integración: **micro-simulación física por viaje** que produce una serie de tiempo de
telemetría OBD/CAN coherente, registrada a **cadencia telemática real** (1/min por defecto), con
ruido de sensor y dropouts. Une RouteNetwork (terreno) + TruckAgent (carga) + Powertrain (motor) +
TireModel (llantas) + SignalRegistry (frames).

Estrategia de volumen (decisión del usuario: "micro-sim fina + log a cadencia real"): se simula la
física a paso fino (perfil de viaje en segmentos), se REGISTRA a `log_dt_s` (p. ej. 60 s) un
snapshot decodificado + los frames J1939/OBD round-trip, y se agregan features por viaje. Para el
dataset "showcase" se cubre cada (tipo de camión × corredor) en días representativos — datos ricos
y consistentes a volumen manejable.

Estado con memoria: térmicas (refrigerante/aceite) por **retardo de 1er orden** hacia el setpoint
de Powertrain; llantas (banda/presión) acumulan a lo largo del viaje.
"""
module TelemetrySim

using Random
using Dates

using ..RouteNetwork
using ..TruckAgent
using ..SignalRegistry
using ..Powertrain
using ..TireModel
using ..Diagnostics

export TelemetryConfig, TelemetryRow, generate_showcase, simulate_vehicle_day,
       simulate_segments, VState

struct TelemetryConfig
    log_dt_s::Int          # cadencia de registro (s)
    micro_dt_s::Int        # paso de la micro-sim (s) para integrar térmicas
    seed::Int
    days_per_combo::Int    # días representativos por (tipo × corredor)
    dropout_prob::Float64  # prob. de frame perdido (LTE)
end

TelemetryConfig(; log_dt_s=60, micro_dt_s=10, seed=20240617, days_per_combo=2, dropout_prob=0.02) =
    TelemetryConfig(log_dt_s, micro_dt_s, seed, days_per_combo, dropout_prob)

"Fila de telemetría decodificada (señales clave) a un instante de registro."
struct TelemetryRow
    vehicle_id::String
    t_s::Int
    protocol::Symbol
    speed_kph::Float64
    rpm::Float64
    load_pct::Float64
    torque_pct::Float64
    coolant_c::Float64
    oil_temp_c::Float64
    oil_press_kpa::Float64
    fuel_lph::Float64
    boost_kpa::Float64
    egt_c::Float64
    nox_out_ppm::Float64
    def_level_pct::Float64
    batt_v::Float64
    ambient_c::Float64
    altitude_m::Float64
    grade_pct::Float64
    tire_min_tread_mm::Float64
    tire_min_press_kpa::Float64
    engine_h::Float64
    odo_km::Float64
    # --- precursores PdM (capa de salud) ---
    crankcase_kpa::Float64       # blowby / desgaste de anillos
    oil_filt_dp_kpa::Float64     # obstrucción filtro de aceite
    fuel_filt_dp_kpa::Float64    # obstrucción filtro de combustible
    air_filt_dp_kpa::Float64     # obstrucción filtro de aire
    turbo_rpm::Float64
    intercooler_c::Float64
    trans_oil_c::Float64
    dpf_soot_dp_kpa::Float64
    dpf_ash_pct::Float64
    brake_air_kpa::Float64
    brake_lining_mm::Float64
    cranking_v::Float64          # voltaje de arranque (salud de batería)
    batt_soh::Float64            # state of health (0..1)
end

# perfil de viaje: secuencia de tramos (dur_s, speed, grade, altitude, ambient, idle)
function trip_segments(rng, arch::RouteNetwork.RouteArchetype; summer::Bool)
    target_km = arch.trip_km[1] + (arch.trip_km[2] - arch.trip_km[1]) * rand(rng)
    amb_rng = summer ? arch.ambient_summer : arch.ambient_winter
    alt = arch.altitude[1] + (arch.altitude[2] - arch.altitude[1]) * rand(rng)
    segs = Tuple{Float64,Float64,Float64,Float64,Float64,Bool}[]
    dist = 0.0
    while dist < target_km
        if rand(rng) < arch.idle_frac * 0.5            # evento de ralentí (parada/tráfico)
            push!(segs, (60.0 + 240.0 * rand(rng), 0.0, 0.0, alt,
                         amb_rng[1] + (amb_rng[2]-amb_rng[1])*rand(rng), true))
            continue
        end
        seg_km = 2.0 + 13.0 * rand(rng)
        gmax = arch.grade_abs[2]
        # pendiente firmada con reversión a la media de altitud (sube/baja dentro del rango)
        bias = (alt - (arch.altitude[1]+arch.altitude[2])/2) / max(arch.altitude[2]-arch.altitude[1], 1)
        grade = (rand(rng) < arch.descent_share ? -1 : 1) * gmax * (0.3 + 0.7*rand(rng)) - 1.5*bias*gmax
        grade = clamp(grade, -gmax, gmax)
        speed = arch.speed_kph * (0.85 + 0.3 * rand(rng))
        dur = seg_km / max(speed, 5.0) * 3600
        alt = clamp(alt + grade/100 * seg_km * 1000, arch.altitude[1], arch.altitude[2])
        ambient = amb_rng[1] + (amb_rng[2]-amb_rng[1])*rand(rng)
        rough = arch.roughness[1] + (arch.roughness[2]-arch.roughness[1])*rand(rng)
        push!(segs, (dur, speed, grade, alt, ambient, false))
        dist += seg_km
    end
    return segs
end

_noisy(rng, v, cv) = v * (1 + cv * randn(rng))

"""
    simulate_segments(ttype, dynspec, tires, state, segs, mass, mf; cfg, rng, day_start_s)
        -> (rows, frames, features)

Núcleo de micro-simulación sobre tramos `segs` = (dur_s, speed_kph, grade_pct, altitude_m,
ambient_c, idle::Bool). Lo usan tanto los viajes sintéticos como las **rutas reales (Valhalla)**.
La severidad de frenado/fatiga para el desgaste de llanta se deriva del propio tramo (pendiente).
`state` (mutable) lleva térmicas, horas-motor, odómetro y DEF; se actualiza in situ.
"""
function simulate_segments(ttype::TruckAgent.TruckType, dynspec, tires::Vector{TireState}, state,
                           segs, mass::Float64, mf::Float64;
                           cfg::TelemetryConfig, rng, day_start_s::Int)
    rows = TelemetryRow[]
    frames = Tuple{String,Int,UInt32,Vector{UInt8}}[]   # (vid, t_s, can_id, data)
    t = 0
    next_log = 0
    # acumuladores de features
    fuel_l = 0.0; brake_kj = 0.0; max_load = 0.0; hi_load_s = 0; nox_g = 0.0; dist_km = 0.0
    coolant = state.coolant; oil_t = state.oil_t; eng0 = state.engine_h

    for (dur, speed, grade, alt, ambient, idle) in segs
        nsteps = max(1, round(Int, dur / cfg.micro_dt_s))
        for _ in 1:nsteps
            s = Powertrain.instant_state(dynspec, mass, idle ? 0.0 : speed, grade, alt, ambient;
                                         def_ok = state.def_level > 5, scr_temp_ok = true)
            # térmicas: retardo de 1er orden hacia el setpoint
            τ = 90.0  # s
            a = cfg.micro_dt_s / τ
            coolant += a * (s.coolant_set - coolant)
            oil_t += (cfg.micro_dt_s / 140.0) * (s.oil_set - oil_t)
            # acumular
            dt_h = cfg.micro_dt_s / 3600
            state.engine_h += dt_h
            d_km = s.v_kph * dt_h
            state.odo_km += d_km; dist_km += d_km
            fuel_l += s.fuel_lph * dt_h
            state.def_level = max(0.0, state.def_level - s.nox_out * 1e-6 * 3 - (s.fuel_lph*dt_h)*0.04*0.1)
            nox_g += s.nox_out * 1e-3 * dt_h
            s.braking && (brake_kj += mass * 9.81 * abs(grade)/100 * s.v_kph/3.6 * cfg.micro_dt_s / 1000)
            max_load = max(max_load, s.load); s.load > 75 && (hi_load_s += cfg.micro_dt_s)
            # desgaste de llantas: severidad de frenado del tramo (pendiente) + rugosidad
            for tire in tires
                TireModel.tread_wear_increment!(tire, d_km, mf,
                    clamp(abs(grade) / 6, 0, 1) * 0.6 + 0.2, 2.0)
            end

            # registro a cadencia
            if t >= next_log
                row, fr = _log_snapshot(ttype, dynspec, s, coolant, oil_t, tires, ambient, alt,
                                        grade, mf, state, cfg, rng, day_start_s + t)
                push!(rows, row)
                for f in fr; push!(frames, f); end
                next_log += cfg.log_dt_s
            end
            t += cfg.micro_dt_s
        end
    end
    state.coolant = coolant; state.oil_t = oil_t
    # recargar DEF si quedó bajo (servicio)
    state.def_level < 10 && (state.def_level = 100.0)
    # evolucionar la salud tras el viaje (precursores PdM)
    mean_amb = isempty(segs) ? 25.0 : sum(seg[5] for seg in segs) / length(segs)
    Diagnostics.evolve_health!(state.health, dist_km, max(state.engine_h - eng0, 0.0),
        fuel_l, brake_kj, 0.1, mean_amb; dusty = mean_amb > 35)

    feats = (dist_km=dist_km, fuel_l=fuel_l, brake_kj=brake_kj, max_load=max_load,
             hi_load_frac = t > 0 ? hi_load_s / t : 0.0, nox_g=nox_g,
             tire_min_tread = minimum(tt.tread_mm for tt in tires))
    return rows, frames, feats
end

"""
    simulate_vehicle_day(ttype, arch, dynspec, tires, state; cfg, rng, summer, day_start_s)

Un día sintético: muestrea carga y un viaje del arquetipo, y micro-simula sobre sus tramos.
"""
function simulate_vehicle_day(ttype::TruckAgent.TruckType, arch, dynspec,
                              tires::Vector{TireState}, state;
                              cfg::TelemetryConfig, rng, summer::Bool, day_start_s::Int)
    payload = TruckAgent.sample_payload(rng, ttype; loaded = rand(rng) < 0.7)
    mass = ttype.curb_kg + payload
    mf = TruckAgent.mass_factor(ttype, payload)
    segs = trip_segments(rng, arch; summer=summer)
    rows, frames, feats = simulate_segments(ttype, dynspec, tires, state, segs, mass, mf;
                                            cfg=cfg, rng=rng, day_start_s=day_start_s)
    return rows, frames, feats, state
end

# snapshot de registro: fila decodificada + frames J1939/OBD (con ruido y dropout)
function _log_snapshot(ttype, dynspec, s, coolant, oil_t, tires, ambient, alt, grade, mf,
                       state, cfg, rng, t_s)
    cv = 0.01
    tmin = minimum(tt.tread_mm for tt in tires)
    tire_temp = TireModel.tire_temp_c(ambient, s.v_kph, mf)
    pmin = minimum(TireModel.tire_pressure_kpa(tt, tire_temp) for tt in tires)
    dg = Diagnostics.diagnostic_signals(state.health, s; ambient_c=ambient)
    row = TelemetryRow(state.vid, t_s, ttype.protocol,
        _noisy(rng, s.v_kph, cv), _noisy(rng, s.rpm, cv), _noisy(rng, s.load, cv),
        s.torque_pct, _noisy(rng, coolant, 0.008), _noisy(rng, oil_t, 0.008),
        _noisy(rng, s.oil_press_kpa, cv), _noisy(rng, s.fuel_lph, 0.02),
        _noisy(rng, s.boost_kpa, cv), _noisy(rng, s.egt_c, cv), _noisy(rng, s.nox_out, 0.05),
        state.def_level, _noisy(rng, dg.cranking_v + 1.3 - 0.02*max(ambient-25,0), 0.01),
        ambient, alt, grade, tmin, pmin, state.engine_h, state.odo_km,
        _noisy(rng, dg.crankcase_kpa, 0.03), _noisy(rng, dg.oil_filt_dp_kpa, cv),
        _noisy(rng, dg.fuel_filt_dp_kpa, cv), _noisy(rng, dg.air_filt_dp_kpa, cv),
        _noisy(rng, dg.turbo_rpm, cv), _noisy(rng, s.intake_temp_c - 3, cv),
        _noisy(rng, dg.trans_oil_c, 0.008), _noisy(rng, dg.dpf_dp_kpa, cv), dg.dpf_ash_pct,
        _noisy(rng, dg.brake_lining_mm < 4 ? 700.0 : 770.0, cv), dg.brake_lining_mm,
        _noisy(rng, dg.cranking_v, 0.01), dg.batt_soh)

    frames = Tuple{String,Int,UInt32,Vector{UInt8}}[]
    if ttype.protocol == :j1939
        pgnvals = Dict(
            "EEC1" => Dict(190=>row.rpm, 513=>s.torque_pct, 512=>s.driver_demand),
            "EEC2" => Dict(91=>clamp(s.load,0,100), 92=>clamp(s.load,0,100)),
            "CCVS" => Dict(84=>row.speed_kph),
            "ET1"  => Dict(110=>row.coolant_c, 175=>row.oil_temp_c, 174=>ambient+8),
            "EFL/P1" => Dict(100=>row.oil_press_kpa, 111=>clamp(coolant>104 ? 70.0 : 95.0,0,100)),
            "LFE"  => Dict(183=>max(row.fuel_lph,0), 51=>clamp(s.load,0,100)),
            "IC1"  => Dict(102=>row.boost_kpa, 105=>s.intake_temp_c, 173=>row.egt_c),
            "VEP1" => Dict(168=>row.batt_v, 167=>row.batt_v+0.3),
            "AMB"  => Dict(108=>s.baro_kpa, 171=>ambient),
            "AT1 NOx" => Dict(3216=>s.nox_in, 3226=>max(row.nox_out_ppm,0)),
            "AT1 DEF" => Dict(1761=>state.def_level, 5246=>state.def_level<5 ? 1.0 : 0.0),
            # --- precursores PdM ---
            "CCP"  => Dict(101=>clamp(row.crankcase_kpa,0,12)),
            "FLTR" => Dict(99=>clamp(row.oil_filt_dp_kpa,0,255), 95=>clamp(row.fuel_filt_dp_kpa,0,255),
                           107=>clamp(row.air_filt_dp_kpa,0,12)),
            "TC1"  => Dict(103=>max(row.turbo_rpm,0), 52=>row.intercooler_c),
            "AIR1" => Dict(117=>clamp(row.brake_air_kpa,0,1000), 118=>clamp(row.brake_air_kpa-15,0,1000)),
            "TF1"  => Dict(177=>row.trans_oil_c),
            "DPF2" => Dict(3720=>clamp(row.dpf_ash_pct,0,100)),
            "DPFC1"=> Dict(3251=>max(row.dpf_soot_dp_kpa,0), 3719=>clamp(40+row.dpf_ash_pct,0,100)),
        )
        for pd in SignalRegistry.J1939_PGNS
            haskey(pgnvals, pd.name) || continue
            rand(rng) < cfg.dropout_prob && continue        # frame perdido (LTE)
            id, data = encode_pgn(pd, Dict{Int,Float64}(pgnvals[pd.name]))
            push!(frames, (state.vid, t_s, id, data))
        end
        # TPMS: un frame por llanta
        for (i, tt) in enumerate(tires)
            tp = TireModel.tire_pressure_kpa(tt, TireModel.tire_temp_c(ambient, s.v_kph, mf))
            tpmsdef = first(filter(p->p.name=="TIRE", SignalRegistry.J1939_PGNS))
            id, data = encode_pgn(tpmsdef, Dict{Int,Float64}(929=>Float64(i), 241=>tp,
                                  242=>TireModel.tire_temp_c(ambient, s.v_kph, mf)))
            push!(frames, (state.vid, t_s, id, data))
        end
    else  # OBD-II: subconjunto (menos señales — brecha real)
        obdvals = Dict(0x0C=>row.rpm, 0x0D=>row.speed_kph, 0x04=>clamp(s.load,0,100),
                       0x05=>row.coolant_c, 0x0F=>s.intake_temp_c, 0x11=>clamp(s.load,0,100),
                       0x2F=>clamp(state.def_level,0,100), 0x5E=>max(row.fuel_lph,0),
                       0x46=>ambient, 0x42=>row.batt_v, 0x5C=>row.oil_temp_c, 0x33=>s.baro_kpa,
                       0x0B=>s.boost_kpa, 0x43=>clamp(s.load,0,100), 0x2C=>clamp(20+s.load*0.3,0,100),
                       0x06=>clamp(2*randn(rng),-15,15), 0x3C=>clamp(row.egt_c*0.7,0,900),
                       0x31=>clamp(state.health.km_since_fuelfilt,0,65535))
        for (pid, val) in obdvals
            rand(rng) < cfg.dropout_prob && continue
            sig = SignalRegistry.OBD_PIDS[pid]
            data = encode_obd(sig, val)
            frame = vcat(UInt8[0x41, pid], data)        # respuesta Modo 01 auto-describible (round-trip)
            frame = vcat(frame, fill(0xAA, 8 - length(frame)))  # relleno a 8 bytes (ISO-TP single frame)
            push!(frames, (state.vid, t_s, UInt32(0x7E8), frame))   # respuesta OBD (ECU)
        end
    end
    return row, frames
end

"Estado mutable del vehículo entre días."
mutable struct VState
    vid::String
    coolant::Float64
    oil_t::Float64
    engine_h::Float64
    odo_km::Float64
    def_level::Float64
    health::Diagnostics.HealthState
end

"""
    generate_showcase(cfg) -> (rows, frames, features)

Genera el dataset showcase: cada (tipo de camión × corredor) por `cfg.days_per_combo` días, a paso
fino y registro a `cfg.log_dt_s`. Datos ricos, consistentes y round-trip.
"""
function generate_showcase(cfg::TelemetryConfig=TelemetryConfig())
    rng = MersenneTwister(cfg.seed)
    all_rows = TelemetryRow[]
    all_frames = Tuple{String,Int,UInt32,Vector{UInt8}}[]
    all_feats = NamedTuple[]
    routes = collect(keys(RouteNetwork.ARCHETYPES))
    k = 0
    for ttype in TruckAgent.TRUCK_TYPES, rk in routes
        k += 1
        arch = RouteNetwork.ARCHETYPES[rk]
        brand = ttype.brands[1]
        dynspec = Powertrain.dynspec_for(ttype.class, ttype.engine_kw)
        vid = string(ttype.name, "_", rk)
        tires = [TireModel.new_tire(loc, ttype.class; rng=rng) for loc in ttype.brake_positions]
        hot = rk in (:desert_southwest,)
        health = Diagnostics.initial_health(rng; class=ttype.class, hot_climate=hot)
        st = VState(vid, 80.0, 90.0, health.engh0_h, health.odo0_km, 100.0, health)
        for d in 1:cfg.days_per_combo
            summer = isodd(d)
            rows, frames, feats, st = simulate_vehicle_day(ttype, arch, dynspec, tires, st;
                                          cfg=cfg, rng=rng, summer=summer, day_start_s=(d-1)*86400)
            append!(all_rows, rows); append!(all_frames, frames)
            push!(all_feats, merge((vehicle_id=vid, route=String(rk), day=d,
                  class=String(ttype.class)), feats))
        end
    end
    return all_rows, all_frames, all_feats
end

end # module
