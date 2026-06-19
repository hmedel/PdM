#!/usr/bin/env julia
# ============================================================================
# Generador de telemetría OBD/CAN — runner del subsistema.
#   micro-sim física por viaje → señales coherentes → frames J1939/OBD → round-trip → CSV.
#
# Uso:   julia run_telemetry.jl [days_per_combo] [log_dt_s]
# Salida: out/telemetry/{telemetry_rows,telemetry_frames,trip_features}.csv
# ============================================================================
using Printf, Statistics
using DataFrames, CSV

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
using .MaintenanceSim.TelemetrySim, .MaintenanceSim.SignalRegistry

days = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 2
logdt = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 60
cfg = TelemetrySim.TelemetryConfig(log_dt_s=logdt, micro_dt_s=10, days_per_combo=days, seed=20240617)

R = "="^84
sec(t) = (println("\n", R); println(t); println(R))

sec("GENERADOR DE TELEMETRÍA OBD/CAN — micro-simulación física con sustento real")
@printf("Cadencia de registro: %ds · paso micro-sim: %ds · %d día(s) por (tipo×corredor)\n",
        cfg.log_dt_s, cfg.micro_dt_s, cfg.days_per_combo)

rows, frames, feats = generate_showcase(cfg)
@printf("Filas decodificadas: %d · frames J1939/OBD: %d · viajes: %d\n", length(rows), length(frames), length(feats))

# --- round-trip de TODOS los frames ---
sec("VERIFICACIÓN ROUND-TRIP (encode → decode) de todos los frames")
function verify_roundtrip(frames)
    pgn_by_num = Dict(p.pgn => p for p in SignalRegistry.J1939_PGNS)
    ok = 0; bad = 0; j1939 = 0; obd = 0
    for (vid, t, id, data) in frames
        if id == 0x7E8                       # OBD-II
            obd += 1
            pid = data[2]; sig = SignalRegistry.OBD_PIDS[pid]
            v = decode_obd(sig, data[3:2+sig.n_bytes])
            isfinite(v) ? (ok += 1) : (bad += 1)
        else                                  # J1939
            j1939 += 1
            pgn = Int((id >> 8) & 0xFFFF)
            pd = get(pgn_by_num, pgn, nothing)
            if pd === nothing; bad += 1; continue; end
            dec = decode_pgn(pd, data)
            all(v -> v === missing || isfinite(v), values(dec)) ? (ok += 1) : (bad += 1)
        end
    end
    return j1939, obd, ok, bad
end
j1939, obd, ok, bad = verify_roundtrip(frames)
@printf("J1939: %d · OBD-II: %d · round-trip OK: %d · fallidos: %d\n", j1939, obd, ok, bad)
println(bad == 0 ? "✓ Todos los frames decodifican correctamente (round-trip íntegro)." :
                   "⚠ Hay frames que no decodifican — revisar.")

# --- consistencia física (chequeos de rango) ---
sec("CONSISTENCIA FÍSICA (rangos por señal, sobre las filas decodificadas)")
heavy = filter(r -> r.protocol == :j1939, rows)
function rng_ok(name, vals, lo, hi)
    mn, mx = minimum(vals), maximum(vals)
    @printf("  %-18s [%7.1f, %7.1f]   %s\n", name, mn, mx, (mn>=lo && mx<=hi) ? "✓" : "⚠ fuera de [$lo,$hi]")
end
rng_ok("RPM (pesado)", [r.rpm for r in heavy], 550, 2150)
rng_ok("velocidad kph", [r.speed_kph for r in rows], 0, 130)
rng_ok("%carga", [r.load_pct for r in rows], 0, 101)
rng_ok("refrigerante °C", [r.coolant_c for r in heavy], 60, 110)
rng_ok("EGT °C", [r.egt_c for r in heavy], 150, 750)
rng_ok("presión llanta kPa", [r.tire_min_press_kpa for r in heavy], 400, 1100)
rng_ok("voltaje batería V", [r.batt_v for r in rows], 11, 15)

# --- correlación física: %carga sube con la pendiente (consistencia esperada) ---
gl = [(r.grade_pct, r.load_pct) for r in heavy if r.speed_kph > 20]
if length(gl) > 50
    g = [x[1] for x in gl]; l = [x[2] for x in gl]
    c = cor(g, l)
    @printf("\nCorrelación pendiente↔%%carga (pesado en marcha): r=%.2f  %s\n", c,
            c > 0.3 ? "✓ (subidas cargan el motor — físicamente correcto)" : "⚠ débil")
end

# --- escribir CSV ---
sec("ESCRITURA")
outdir = joinpath(ROOT, "out", "telemetry"); mkpath(outdir)
df_rows = DataFrame(rows)
CSV.write(joinpath(outdir, "telemetry_rows.csv"), df_rows)
df_feats = DataFrame(feats)
CSV.write(joinpath(outdir, "trip_features.csv"), df_feats)
df_frames = DataFrame(
    vehicle_id = [f[1] for f in frames], t_s = [f[2] for f in frames],
    can_id_hex = [string("0x", uppercase(string(f[3], base=16))) for f in frames],
    data_hex = [join([uppercase(string(b, base=16, pad=2)) for b in f[4]], " ") for f in frames],
    bus = [f[3] == 0x7E8 ? "OBD-II" : "J1939" for f in frames],
)
CSV.write(joinpath(outdir, "telemetry_frames.csv"), df_frames)
@printf("out/telemetry/telemetry_rows.csv   (%d filas, %d señales)\n", nrow(df_rows), ncol(df_rows))
@printf("out/telemetry/telemetry_frames.csv (%d frames J1939/OBD, round-trip)\n", nrow(df_frames))
@printf("out/telemetry/trip_features.csv    (%d viajes)\n", nrow(df_feats))

# --- resumen por corredor (consumo emergente de la física + ruta) ---
sec("CONSUMO EMERGENTE POR CORREDOR (L/100km — sale de la física, no se postula)")
gdf = combine(groupby(df_feats, :route),
    [:fuel_l, :dist_km] => ((f, d) -> 100 * sum(f) / sum(d)) => :l_per_100km,
    :max_load => mean => :carga_max_media)
sort!(gdf, :l_per_100km)
for r in eachrow(gdf)
    @printf("  %-22s %5.1f L/100km   carga máx media %.0f%%\n", r.route, r.l_per_100km, r.carga_max_media)
end
println("\nVer docs/Sustento_Fisico_Telemetria.md para el origen documental de cada parámetro.")
