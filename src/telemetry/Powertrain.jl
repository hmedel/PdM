"""
    Powertrain

Modelo de **dinámica longitudinal e instantánea del motor** — el núcleo que hace que las señales
OBD/CAN sean *físicamente consistentes* entre sí (RPM↔velocidad↔marcha, %carga↔pendiente·masa,
consumo↔potencia, boost/EGT/NOx↔carga). De aquí salen los valores físicos que SignalRegistry
empaqueta en frames.

Física (libro de texto de dinámica vehicular; Gillespie 1992, *Fundamentals of Vehicle Dynamics*):

  Fuerzas a velocidad v y pendiente θ:
    F_rod  = C_rr · m · g · cosθ                 (rodadura)
    F_aero = ½ · ρ(alt) · Cd·A · v²              (aerodinámica; ρ baja con la altitud)
    F_grad = m · g · sinθ                         (pendiente; <0 en bajada)
    F_acc  = m · a                                (aceleración)
  Potencia en rueda:  P_rueda = (ΣF) · v ;  Potencia al motor:  P_mot = P_rueda/η + accesorios.
  En bajada P_rueda<0 ⇒ frenado (motor/retarder/servicio) — no consume combustible, calienta frenos.
  Velocidad **limitada por potencia** en subida: si P_mot>P_nominal, el camión desacelera (realista).

  %carga = 100·P_mot/P_nom.  Consumo = P_mot·BSFC/ρ_diesel.  RPM por selección de marcha
  (mantener banda de operación). Boost, EGT y NOx escalan con la carga; las térmicas
  (refrigerante/aceite) las integra TelemetrySim como retardo de 1er orden hacia un setpoint.
"""
module Powertrain

using ..SignalRegistry: J1939_PGNS  # (solo para coherencia de unidades; no se usa directamente)

export DynSpec, dynspec_for, instant_state

const G = 9.81
const RHO0 = 1.225          # densidad del aire a nivel del mar (kg/m³)
const RHO_DIESEL = 835.0    # g/L
const SCALE_H = 8500.0      # altura de escala atmosférica (m)

"Parámetros de dinámica de un vehículo (derivados del tipo de camión)."
struct DynSpec
    p_rated_kw::Float64
    idle_rpm::Float64
    redline_rpm::Float64
    cda::Float64            # Cd·A (m²)
    crr::Float64            # coef. de rodadura
    eta::Float64            # eficiencia de transmisión
    tire_r::Float64         # radio de llanta (m)
    accessory_kw::Float64
    idle_load::Float64      # % de carga en ralentí
    idle_fuel_lph::Float64
    max_boost_kpa::Float64  # boost máximo (manométrico) a plena carga
    overall_ratios::Vector{Float64}   # marcha×diferencial (rueda)
end

"Construye el DynSpec a partir de clase y potencia (TruckAgent.TruckType)."
function dynspec_for(class::Symbol, engine_kw::Float64)
    if class == :light_vehicle
        cruise_rpm, cruise_kph, tire_r = 2200.0, 100.0, 0.31
        top = cruise_rpm * 2π * tire_r / (60 * cruise_kph / 3.6)
        ratios = [top * 1.6^(i) for i in 5:-1:0]    # 6 marchas geométricas
        return DynSpec(engine_kw, 750.0, 6500.0, 0.72, 0.011, 0.90, tire_r, 1.5, 9.0, 0.8, 150.0, ratios)
    else
        cda = class == :heavy_truck && engine_kw > 300 ? 6.3 : 4.8   # Cd·A típico flota (rango 5–10 m²)
        cruise_rpm, cruise_kph, tire_r = 1300.0, 95.0, 0.50
        top = cruise_rpm * 2π * tire_r / (60 * cruise_kph / 3.6)
        ratios = [top * 1.35^(i) for i in 9:-1:0]    # 10 marchas
        return DynSpec(engine_kw, 650.0, 2100.0, cda, 0.0065, 0.88, tire_r, 7.0, 6.0, 2.6, 220.0, ratios)
    end
end

air_density(alt_m) = RHO0 * exp(-alt_m / SCALE_H)
baro_kpa(alt_m) = 101.3 * exp(-alt_m / SCALE_H)

"""
    gear_rpm(spec, v_ms, load) -> RPM

Selección de marcha: la marcha más ALTA (menor RPM, mejor consumo) que no quede por debajo del
límite de *lug*; el límite sube con la carga (bajo carga se baja marcha para tener potencia/par).
`overall_ratios` está ordenado de 1ª (ratio alto) a última (ratio bajo); se itera de la más alta
a la más baja.
"""
function gear_rpm(spec::DynSpec, v_ms::Float64, load::Float64)
    v_ms < 0.5 && return spec.idle_rpm
    lug = max(spec.idle_rpm + 250, 1000.0) + (load / 100) * 450    # downshift bajo carga
    for ratio in Iterators.reverse(spec.overall_ratios)           # de la más alta a la 1ª
        rpm = ratio * v_ms / spec.tire_r * 9.5493
        rpm >= lug && return min(rpm, spec.redline_rpm)
    end
    # ninguna marcha alcanza el lug (velocidad muy baja) → 1ª (mayor RPM disponible)
    return clamp(spec.overall_ratios[1] * v_ms / spec.tire_r * 9.5493, spec.idle_rpm, spec.redline_rpm)
end

"""
    instant_state(spec, mass_kg, v_kph, grade_pct, altitude_m, ambient_c; accel, def_ok, scr_temp_ok)
        -> NamedTuple

Estado físico instantáneo. Devuelve señales directas + setpoints térmicos (para el retardo en
TelemetrySim). `def_ok`/`scr_temp_ok` modulan la eficiencia del SCR (NOx de salida).
"""
function instant_state(spec::DynSpec, mass_kg::Float64, v_kph::Float64, grade_pct::Float64,
                       altitude_m::Float64, ambient_c::Float64;
                       accel::Float64=0.0, def_ok::Bool=true, scr_temp_ok::Bool=true)
    ρ = air_density(altitude_m)
    θ = atan(grade_pct / 100)
    v = v_kph / 3.6
    # Derate por altitud (diésel TURBO): el turbo MANTIENE potencia nominal hasta ~1500 m
    # (Cummins: sin derate hasta ~5000 ft ≈ 1524 m); arriba, ~8.5%/1000 m (≈2.5%/1000 ft, Garrett).
    P_alt = spec.p_rated_kw * (1 - 0.085 * max(altitude_m - 1500.0, 0.0) / 1000)

    Freq(vv) = spec.crr * mass_kg * G * cos(θ) + 0.5 * ρ * spec.cda * vv^2 +
               mass_kg * G * sin(θ) + mass_kg * accel
    Peng(vv) = Freq(vv) * vv / 1000 / spec.eta + spec.accessory_kw

    # velocidad limitada por potencia en subida
    vcap = v
    for _ in 1:25
        (Peng(vcap) <= 0.98 * P_alt || vcap < 1.0) && break
        vcap *= 0.95
    end
    v = vcap
    F = Freq(v)
    P_eng = Peng(v)
    braking = F < 0                                  # bajada: frenado, no fuel
    P_fuel = max(braking ? spec.accessory_kw : P_eng, spec.idle_load / 100 * spec.p_rated_kw)

    moving = v >= 0.5
    load = moving ? clamp(100 * P_eng / P_alt, spec.idle_load, 100.0) : spec.idle_load
    braking && (load = spec.idle_load + 4)            # motor "frena" a baja carga
    rpm = moving ? gear_rpm(spec, v, load) : spec.idle_rpm
    torque_pct = clamp(load * 0.95, -30.0, 125.0)
    driver_demand = clamp(torque_pct + 4 * (load > 60), -30.0, 125.0)

    # consumo: BSFC peor a baja carga; ralentí fijo
    bsfc = 195 + 60 * exp(-load / 25)                # g/kWh
    fuel_lph = moving && !braking ? P_fuel * bsfc / RHO_DIESEL : spec.idle_fuel_lph
    fuel_econ = (moving && fuel_lph > 0.1) ? v_kph / fuel_lph : 0.0   # km/L

    boost = baro_kpa(altitude_m) + (load / 100) * spec.max_boost_kpa
    egt = 250 + (load / 100) * 420 + max(ambient_c - 25, 0) * 1.5     # °C
    oil_press = moving ? 140 + (rpm / spec.redline_rpm) * 320 : 150.0  # kPa
    nox_in = 90 + (load / 100) * 950                                  # ppm engine-out
    scr_eff = (def_ok && scr_temp_ok && egt > 220) ? 0.92 : 0.35
    nox_out = max(nox_in * (1 - scr_eff), 5.0)

    # setpoints térmicos (TelemetrySim integra el retardo)
    coolant_set = clamp(82 + (load / 100) * 14 + max(ambient_c - 25, 0) * 0.25 +
                        altitude_m * 0.001 + (braking ? -2 : 0), 75.0, 106.0)
    oil_set = clamp(coolant_set + 8 + (load / 100) * 16, 80.0, 130.0)
    intake_t = ambient_c + (load / 100) * 18                          # post-intercooler

    return (v_kph=v * 3.6, rpm=rpm, load=load, torque_pct=torque_pct, driver_demand=driver_demand,
            fuel_lph=fuel_lph, fuel_econ=fuel_econ, boost_kpa=boost, egt_c=egt,
            oil_press_kpa=oil_press, intake_temp_c=intake_t, nox_in=nox_in, nox_out=nox_out,
            baro_kpa=baro_kpa(altitude_m), p_eng_kw=P_eng, braking=braking,
            coolant_set=coolant_set, oil_set=oil_set)
end

end # module
