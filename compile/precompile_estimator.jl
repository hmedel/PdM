# ============================================================================
# precompile_estimator.jl — Ejercita el camino CARO del estimador para que el sysimage/app
# lo precompile (Weibull-AFT + bootstrap + decisión IFR + reescalado T*). Sin BD: usa filas
# sintéticas idénticas a las de las vistas SQL (mismo contrato que tracker_adapter).
# Lo consumen create_sysimage / create_app como `precompile_execution_file`.
# ============================================================================
using MaintenanceSim
using MaintenanceSim.TrackerAdapter
using Random

# Muestreo Weibull por inversa (evita depender de Distributions en el script de precompila).
weibull_sample(rng, β, η) = η * (-log(rand(rng)))^(1 / β)

function exercise()
    rng = MersenneTwister(1)
    # Historial de dos componentes (uno CBM con precursor, uno estadístico) con fallas + censuras.
    mkhist(comp, β, η) = vcat(
        [(component_type=comp, class="light", brand="generic", route_severity=0.0,
          entry_age_km=0.0, exit_age_km=weibull_sample(rng, β, η), status=1) for _ in 1:60],
        [(component_type=comp, class="light", brand="generic", route_severity=0.0,
          entry_age_km=0.0, exit_age_km=weibull_sample(rng, β, η) * 0.6, status=0) for _ in 1:12])
    hist = vcat(mkhist("battery", 2.0, 50_000.0), mkhist("brake_pad", 1.8, 80_000.0))
    live = [(tenant_id="t", vehicle_id="v$i",
             component_type=isodd(i) ? "battery" : "brake_pad", class="light", brand="generic",
             route_severity=0.0, current_age_km=20_000.0 + 1_000i,
             precursor_reading = isodd(i) ? 12.3 : missing) for i in 1:24]
    costs = Dict("battery" => (2500.0, 6000.0), "brake_pad" => (2200.0, 8000.0))

    # Camino completo del runner (menos la BD): fit por componente + estimate por unidad.
    preds = TrackerAdapter.run_estimates(hist, live, costs; run_id="precompile", nboot=100,
                                         rng=MersenneTwister(2))
    # También ejercita los mapeos puros individuales y la fila de salida.
    sr = to_service_record(first(hist)); to_live_unit(first(live)); to_costs(
        [(component_type="battery", cp_mxn=2500.0, cf_mxn=6000.0)])
    return length(preds), sr.exit_age
end

exercise()
println("precompile_estimator: camino del estimador ejercitado.")
