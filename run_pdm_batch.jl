#!/usr/bin/env julia
# ============================================================================
# run_pdm_batch.jl — Job BATCH server-side del estimador PdM: BD → estimate → BD.
#
# Único punto que toca la BD (LibPQ). Toda la lógica de mapeo/estimación es pura y vive en
# `MaintenanceSim.TrackerAdapter` (testeada en test/test_tracker_adapter.jl). Este runner solo:
#   1) lee el catálogo (costos) y, POR TENANT (RLS), las vistas pdm_survival_record / pdm_live_unit,
#   2) llama `run_estimates` (fit por componente + estimate por unidad, identidad intacta),
#   3) inserta en pdm_prediction.
#
# Corre por tenant fijando `app.current_tenant`, de modo que la Row-Level Security de Tracker
# devuelve exactamente las filas de ese tenant (sin necesidad de un rol que la bypassee).
#
# Requiere en el ENTORNO DE DEPLOY (no en el paquete core, que se mantiene libre de BD):
#   LibPQ, Tables, UUIDs  →  ]activate <env-deploy>; add LibPQ Tables UUIDs
# Conexión:  ENV["TRACKER_DB_URL"]  (p. ej. "postgresql://user:pass@host:5432/tracker_prod")
#
#   julia --project=<env-deploy> run_pdm_batch.jl
# Compilable con PackageCompiler (create_app) usando `julia_main` como entrypoint (ver
# docs/Empaquetado_Libreria_Compilacion.md y deployment-server-batch).
# ============================================================================
using LibPQ, Tables, UUIDs, Random
include(joinpath(@__DIR__, "src", "MaintenanceSim.jl")); using .MaintenanceSim
using .MaintenanceSim.TrackerAdapter

"Ejecuta SQL y devuelve las filas como Vector{NamedTuple} (lo que consume el adaptador)."
fetchrows(conn, sql; params=String[]) = Tables.rowtable(LibPQ.execute(conn, sql, params))

"Lista de tenants con vehículos (para el barrido por RLS)."
list_tenants(conn) = [r.tenant_id for r in fetchrows(conn,
    "SELECT DISTINCT tenant_id FROM vehicles")]

const SQL_HISTORY = """
    SELECT component_type, class, brand, route_severity, entry_age_km, exit_age_km, status
    FROM pdm_survival_record"""
const SQL_LIVE = """
    SELECT tenant_id, vehicle_id, component_type, class, brand, route_severity,
           current_age_km, precursor_reading
    FROM pdm_live_unit"""
const SQL_CATALOG = "SELECT component_type, cp_mxn, cf_mxn FROM pdm_component_catalog WHERE enabled"

"Inserta las filas de predicción en pdm_prediction (nothing→NULL). Devuelve cuántas escribió."
function write_predictions(conn, preds)
    isempty(preds) && return 0
    stmt = LibPQ.prepare(conn, """
        INSERT INTO pdm_prediction
          (tenant_id, vehicle_id, component_type, run_id, current_age_km, rul_km, beta, beta_lo,
           eta, optimal_interval_km, recommend_preventive, recommend_at_km, cbm_alarm, rationale)
        VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10,\$11,\$12,\$13,\$14)""")
    nn(x) = x === nothing ? missing : x      # LibPQ: missing → NULL
    for p in preds
        LibPQ.execute(stmt, Any[p.tenant_id, p.vehicle_id, p.component_type, p.run_id,
            p.current_age_km, p.rul_km, p.beta, p.beta_lo, p.eta, nn(p.optimal_interval_km),
            p.recommend_preventive, p.recommend_at_km, p.cbm_alarm, p.rationale])
    end
    return length(preds)
end

"Orquesta una corrida completa sobre todos los tenants. Devuelve (run_id, total_predicciones)."
function run_batch(; url::AbstractString = get(ENV, "TRACKER_DB_URL", ""),
                     nboot::Int = 200, seed::Int = 1)
    isempty(url) && error("Falta ENV[\"TRACKER_DB_URL\"]")
    conn = LibPQ.Connection(url)
    run_id = string(uuid4())
    total = 0
    try
        costs = to_costs(fetchrows(conn, SQL_CATALOG))
        isempty(costs) && @warn "Catálogo sin costos: no se podrá ajustar ningún componente"
        for t in list_tenants(conn)
            LibPQ.execute(conn, "SELECT set_config('app.current_tenant', \$1, false)", String[string(t)])
            live = fetchrows(conn, SQL_LIVE)
            isempty(live) && continue
            hist = fetchrows(conn, SQL_HISTORY)
            preds = run_estimates(hist, live, costs; run_id=run_id, nboot=nboot, rng=MersenneTwister(seed))
            n = write_predictions(conn, preds)
            total += n
            @info "tenant procesado" tenant=string(t) unidades=length(live) predicciones=n
        end
    finally
        close(conn)
    end
    @info "corrida PdM completa" run_id total
    return run_id, total
end

"Entrypoint para PackageCompiler (create_app). Devuelve 0 en éxito, 1 en error."
function julia_main()::Cint
    try
        run_batch()
        return 0
    catch e
        @error "run_pdm_batch falló" exception=(e, catch_backtrace())
        return 1
    end
end

# Ejecución directa (no cuando se incluye/compila): `julia run_pdm_batch.jl`
if abspath(PROGRAM_FILE) == @__FILE__
    run_batch()
end
