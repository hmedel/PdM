#!/usr/bin/env julia
# ============================================================================
# Demo: telemetría OBD/CAN sobre una RUTA REAL de México (perfil de Valhalla).
#
#   1) python3 tools/valhalla_route.py --name cdmx_puebla --loc ... --loc ...   (genera el perfil)
#   2) julia run_valhalla_demo.jl cdmx_puebla                                   (simula y reporta)
#
# Muestra cómo el terreno real (subida a ~3200 m, descensos) se refleja en las señales:
# carga/EGT/refrigerante suben en la subida; el motor frena en bajada; derate por altitud.
# ============================================================================
using Printf, Statistics, JSON3
using DataFrames, CSV

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
using .MaintenanceSim.TelemetrySim, .MaintenanceSim.TruckAgent,
      .MaintenanceSim.Powertrain, .MaintenanceSim.TireModel, .MaintenanceSim.Diagnostics

name = length(ARGS) >= 1 ? ARGS[1] : "cdmx_puebla"
profile_path = joinpath(ROOT, "out", "routes", name * ".json")
isfile(profile_path) || error("No existe $profile_path. Corre primero: python3 tools/valhalla_route.py --name $name ...")
prof = JSON3.read(read(profile_path, String))

R = "="^84
@printf("%s\nTELEMETRÍA SOBRE RUTA REAL (Valhalla) — %s\n%s\n", R, name, R)
@printf("Fuente: %s · %.1f km · %d segmentos · altitud %.0f–%.0f m · peaje=%s\n",
        prof.base, prof.total_km, prof.n_segments, prof.min_alt, prof.max_alt, prof.has_toll)

# clima México por altitud (lapse rate ~6.5 °C/1000 m) y estación
season_sl = 30.0            # temp a nivel del mar, verano centro de México (°C)
mex_ambient(alt) = season_sl - 6.5 * alt / 1000

# tramos del perfil → tuplas (dur_s, speed, grade, alt, ambient, idle)
segs = Tuple{Float64,Float64,Float64,Float64,Float64,Bool}[]
for s in prof.segments
    spd = max(8.0, Float64(s.speed_kph))
    dur = Float64(s.dist_km) / spd * 3600
    push!(segs, (dur, spd, Float64(s.grade_pct), Float64(s.altitude_m),
                 mex_ambient(Float64(s.altitude_m)), false))
end

# agente: Clase 8 sleeper con el peso REAL del corredor (casado al request de Valhalla)
ttype = first(filter(t -> t.name == "Class8_Sleeper", TruckAgent.TRUCK_TYPES))
dynspec = Powertrain.dynspec_for(ttype.class, ttype.engine_kw)
weight_t = haskey(prof, :weight_t) ? Float64(prof.weight_t) : 25.0
mass = weight_t * 1000
@printf("Camión: Clase 8, peso bruto %.1f t (casado al corredor)\n", weight_t)
mf = TruckAgent.mass_factor(ttype, mass - ttype.curb_kg)
rng = TelemetrySim.Random.MersenneTwister(20240617)
tires = [TireModel.new_tire(loc, ttype.class; rng=rng) for loc in ttype.brake_positions]
health = Diagnostics.initial_health(rng; class=ttype.class)
st = TelemetrySim.VState("TRK-MX-001", 75.0, 85.0, health.engh0_h, health.odo0_km, 100.0, health)
cfg = TelemetrySim.TelemetryConfig(log_dt_s=60, micro_dt_s=10)

rows, frames, feats = simulate_segments(ttype, dynspec, tires, st, segs, mass, mf;
                                        cfg=cfg, rng=rng, day_start_s=0)

@printf("\nViaje simulado: %d filas (1/min) · %d frames J1939 · %.1f km · %.0f L · %.1f L/100km\n",
        length(rows), length(frames), feats.dist_km, feats.fuel_l,
        100 * feats.fuel_l / max(feats.dist_km, 1))

# efecto del terreno: comparar tramos de subida fuerte vs bajada vs plano
climb = filter(r -> r.grade_pct > 3, rows)
desc  = filter(r -> r.grade_pct < -3, rows)
flat  = filter(r -> abs(r.grade_pct) <= 1, rows)
showrow(lbl, rs) = isempty(rs) ? @printf("  %-16s (sin tramos)\n", lbl) :
    @printf("  %-16s carga %4.0f%%  RPM %4.0f  EGT %3.0f°C  cool %3.0f°C  L/h %4.1f  v %4.0f km/h\n",
            lbl, mean(r.load_pct for r in rs), mean(r.rpm for r in rs), mean(r.egt_c for r in rs),
            mean(r.coolant_c for r in rs), mean(r.fuel_lph for r in rs), mean(r.speed_kph for r in rs))
println("\nEfecto del terreno real en la telemetría (promedios por tipo de tramo):")
showrow("Subida (>3%)", climb)
showrow("Plano (±1%)", flat)
showrow("Bajada (<-3%)", desc)

# altitud máxima alcanzada y derate
hi = maximum(r.altitude_m for r in rows)
@printf("\nAltitud máxima: %.0f m → derate de potencia turbo ~%.0f%% (a esa altura)\n",
        hi, 100 * 0.085 * max(hi - 1000, 0) / 1000)
c = cor([r.altitude_m for r in rows], [r.load_pct for r in rows])
@printf("Correlación altitud↔%%carga: r=%.2f\n", c)

outdir = joinpath(ROOT, "out", "telemetry"); mkpath(outdir)
CSV.write(joinpath(outdir, "valhalla_$(name).csv"), DataFrame(rows))
@printf("\nTelemetría → out/telemetry/valhalla_%s.csv (%d filas, %d señales)\n",
        name, length(rows), length(fieldnames(TelemetrySim.TelemetryRow)))
