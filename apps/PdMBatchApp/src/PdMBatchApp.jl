# ============================================================================
# PdMBatchApp — Paquete-app del job BATCH server-side (BD → estimate → BD), compilable a binario
# standalone con PackageCompiler `create_app` (NO requiere Julia en destino). Ver
# docs/Empaquetado_Libreria_Compilacion.md §B y compile/build_app.jl.
#
# Único lugar que toca la BD (LibPQ). Toda la lógica de mapeo/estimación es PURA y vive en
# `MaintenanceSim.TrackerAdapter` (testeada). Este módulo solo: lee catálogo + vistas por tenant
# (RLS), llama `run_estimates`, e inserta en `pdm_prediction`.
# ============================================================================
module PdMBatchApp

using LibPQ, Tables, UUIDs, Random
using MaintenanceSim, MaintenanceSim.TrackerAdapter

export run_batch, julia_main

"Ejecuta SQL y devuelve filas como Vector{NamedTuple} (lo que consume el adaptador puro)."
fetchrows(conn, sql; params=String[]) = Tables.rowtable(LibPQ.execute(conn, sql, params))

"""
Tenants con vehículos (para el barrido). `vehicles` tiene RLS en tracker_prod, así que con
contexto vacío y sin privilegio el SELECT devolvería 0 filas. Elevamos a `super_admin` SOLO para
el descubrimiento y lo soltamos enseguida (idéntico mecanismo a Tracker; ver init-db.sql). Tras
esto el lazo corre con user_role vacío ⇒ scope estricto por tenant.
"""
function list_tenants(conn)
    LibPQ.execute(conn, "SELECT set_config('app.user_role', 'super_admin', false)")
    ts = [r.tenant_id for r in fetchrows(conn, "SELECT DISTINCT tenant_id FROM vehicles")]
    LibPQ.execute(conn, "SELECT set_config('app.user_role', '', false)")   # soltar privilegio
    return ts
end

# Filtro EXPLÍCITO por tenant_id: maintenance_records/obd_data/vehicle_mileage NO tienen RLS en
# tracker_prod, así que fijar app.current_tenant no acota el historial. El WHERE explícito acota
# ambas vistas por igual, independientemente de qué tablas tengan RLS (verificado 2026-06-23).
const SQL_HISTORY = """
    SELECT component_type, class, brand, route_severity, entry_age_km, exit_age_km, status
    FROM pdm_survival_record WHERE tenant_id = \$1"""
const SQL_LIVE = """
    SELECT tenant_id, vehicle_id, component_type, class, brand, route_severity,
           current_age_km, precursor_reading
    FROM pdm_live_unit WHERE tenant_id = \$1"""
const SQL_CATALOG = "SELECT component_type, cp_mxn, cf_mxn FROM pdm_component_catalog WHERE enabled"

"Inserta filas de predicción en pdm_prediction (nothing→NULL). Devuelve cuántas escribió."
function write_predictions(conn, preds)
    isempty(preds) && return 0
    stmt = LibPQ.prepare(conn, """
        INSERT INTO pdm_prediction
          (tenant_id, vehicle_id, component_type, run_id, current_age_km, rul_km, beta, beta_lo,
           eta, optimal_interval_km, recommend_preventive, recommend_at_km, cbm_alarm, rationale)
        VALUES (\$1,\$2,\$3,\$4,\$5,\$6,\$7,\$8,\$9,\$10,\$11,\$12,\$13,\$14)""")
    nn(x) = x === nothing ? missing : x          # LibPQ: missing → NULL
    for p in preds
        LibPQ.execute(stmt, Any[p.tenant_id, p.vehicle_id, p.component_type, p.run_id,
            p.current_age_km, p.rul_km, p.beta, p.beta_lo, p.eta, nn(p.optimal_interval_km),
            p.recommend_preventive, p.recommend_at_km, p.cbm_alarm, p.rationale])
    end
    return length(preds)
end

"""
    run_batch(; url, nboot=200, seed=1) -> (run_id, total_predicciones)

Corrida completa sobre todos los tenants. Descubre tenants elevando a `super_admin` un instante
(vehicles tiene RLS), luego acota cada tenant con `WHERE tenant_id = $1` EXPLÍCITO en las vistas
(robusto: maintenance_records/obd_data/vehicle_mileage NO tienen RLS) y fija `app.current_tenant`
para el INSERT en pdm_prediction (esa sí tiene RLS). `url` por defecto = ENV["TRACKER_DB_URL"].

Rol de BD requerido: SELECT en vehicles, maintenance_records, vehicle_mileage, obd_data y las
vistas/catálogo pdm_*; INSERT en pdm_prediction. Funciona tanto con rol BYPASSRLS/owner como con
rol normal (el escape a super_admin cubre el descubrimiento; el filtro explícito cubre el resto).
"""
function run_batch(; url::AbstractString = get(ENV, "TRACKER_DB_URL", ""),
                     nboot::Int = 200, seed::Int = 1)
    isempty(url) && error("Falta ENV[\"TRACKER_DB_URL\"]")
    conn = LibPQ.Connection(url)
    run_id = string(uuid4())
    total = 0
    try
        costs = to_costs(fetchrows(conn, SQL_CATALOG))
        isempty(costs) && @warn "Catálogo sin costos: no se ajustará ningún componente"
        for t in list_tenants(conn)
            # fija el contexto para que el INSERT en pdm_prediction (RLS) pase su WITH CHECK
            LibPQ.execute(conn, "SELECT set_config('app.current_tenant', \$1, false)", String[string(t)])
            live = fetchrows(conn, SQL_LIVE; params=String[string(t)])
            isempty(live) && continue
            hist = fetchrows(conn, SQL_HISTORY; params=String[string(t)])
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

"Entrypoint para PackageCompiler create_app. 0 = éxito, 1 = error."
function julia_main()::Cint
    try
        run_batch()
        return 0
    catch e
        @error "PdMBatchApp falló" exception=(e, catch_backtrace())
        return 1
    end
end

end # module PdMBatchApp
