# ============================================================================
# tracker_adapter.jl — Adaptador PURO entre tracker_prod y el estimador.
#
# Convierte filas de las vistas SQL (NamedTuple) ↔ contratos del estimador, y orquesta el batch
# (fit por componente + estimate por unidad) MANTENIENDO la identidad (tenant_id, vehicle_id) que
# `estimate_fleet` pierde al filtrar. SIN dependencia de BD: el runner LibPQ solo provee/escribe filas.
# Por eso es testeable con filas simuladas. Ver docs/Integracion_BD_Tracker.md.
#
# Filas esperadas (columnas de las vistas de la migración 004):
#   survival (pdm_survival_record): component_type, class, brand, route_severity,
#                                   entry_age_km, exit_age_km, status
#   live     (pdm_live_unit):       tenant_id, vehicle_id, component_type, class, brand,
#                                   route_severity, current_age_km, precursor_reading
#   catalog  (pdm_component_catalog): component_type, cp_mxn, cf_mxn
# Las funciones usan acceso por propiedad (`row.col`); el runner pasa NamedTuples (Tables.rowtable).
# ============================================================================

# Coerción tolerante a NULL (missing/nothing) de SQL.
_f(x)::Float64 = (x === missing || x === nothing) ? NaN : Float64(x)
_optf(x) = (x === missing || x === nothing) ? nothing : Float64(x)

"Fila de `pdm_survival_record` → `ServiceRecord` (contrato de historial del estimador)."
to_service_record(r)::ServiceRecord =
    ServiceRecord(String(r.component_type), Symbol(r.class), String(r.brand),
                  _f(r.route_severity), _f(r.entry_age_km), _f(r.exit_age_km), Int(r.status))

"Fila de `pdm_live_unit` → `LiveUnit` (estado actual; precursor NULL ⇒ sin CBM)."
to_live_unit(r)::LiveUnit =
    LiveUnit(String(r.component_type), Symbol(r.class), String(r.brand),
             _f(r.route_severity), _f(r.current_age_km), _optf(r.precursor_reading))

"Filas de `pdm_component_catalog` → costos `Dict(component_type => (cp, cf))` (omite costos NULL)."
function to_costs(catalog_rows)
    d = Dict{String,Tuple{Float64,Float64}}()
    for r in catalog_rows
        cp = _optf(r.cp_mxn); cf = _optf(r.cf_mxn)
        (cp === nothing || cf === nothing) && continue
        d[String(r.component_type)] = (cp, cf)
    end
    return d
end

"`MaintenanceEstimate` + contexto de unidad → fila NamedTuple para INSERT en `pdm_prediction`."
to_prediction_row(est::MaintenanceEstimate, ctx) =
    (tenant_id           = ctx.tenant_id,
     vehicle_id          = ctx.vehicle_id,
     component_type      = est.component_type,
     run_id              = ctx.run_id,
     current_age_km      = ctx.current_age_km,
     rul_km              = est.rul,
     beta                = est.beta,
     beta_lo             = est.beta_lo,
     eta                 = est.eta,
     optimal_interval_km = est.optimal_interval,     # nothing ⇒ NULL
     recommend_preventive = est.recommend_preventive,
     recommend_at_km     = est.recommend_at_age,
     cbm_alarm           = est.cbm_alarm,
     rationale           = est.rationale)

"""
    run_estimates(history_rows, live_rows, costs; run_id, nboot=200, rng) -> Vector{NamedTuple}

Orquestación batch PURA: ajusta un `ComponentModel` por tipo de componente (con historial y costo)
y evalúa cada unidad viva, devolviendo filas de predicción con su (tenant_id, vehicle_id) intactos.
Unidades sin modelo (sin historial o sin costo) se omiten; un componente cuyo ajuste falla se omite
con aviso. Esto es lo que el runner LibPQ envuelve: BD → run_estimates → BD.
"""
function run_estimates(history_rows, live_rows, costs;
                       run_id, nboot::Int=200, rng::AbstractRNG=MersenneTwister(1))
    history = ServiceRecord[to_service_record(r) for r in history_rows]
    by_comp = Dict{String,Vector{ServiceRecord}}()
    for r in history
        push!(get!(by_comp, r.component_type, ServiceRecord[]), r)
    end
    models = Dict{String,ComponentModel}()
    for (comp, recs) in by_comp
        haskey(costs, comp) || continue
        cp, cf = costs[comp]
        try
            models[comp] = fit_component(recs; cp=cp, cf=cf, nboot=nboot, rng=rng)
        catch e
            @warn "run_estimates: fit_component falló, componente omitido" component=comp exception=e
        end
    end
    preds = NamedTuple[]
    for row in live_rows
        comp = String(row.component_type)
        haskey(models, comp) || continue
        unit = to_live_unit(row)
        est  = estimate(models[comp], unit)
        ctx  = (tenant_id = row.tenant_id, vehicle_id = row.vehicle_id,
                run_id = run_id, current_age_km = unit.current_age)
        push!(preds, to_prediction_row(est, ctx))
    end
    return preds
end
