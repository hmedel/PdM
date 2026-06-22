# ============================================================================
# precompile_app.jl — precompile_execution_file para create_app (PdMBatchApp).
# Ejercita el camino CARO (estimación) sin BD; las funciones LibPQ/BD no se pueden precompilar
# aquí (no hay conexión) y JIT-compilan en la primera corrida real (costo despreciable).
# ============================================================================
using PdMBatchApp
using MaintenanceSim.TrackerAdapter
using Random

weibull_sample(rng, β, η) = η * (-log(rand(rng)))^(1 / β)

let rng = MersenneTwister(1)
    mk(comp, β, η) = vcat(
        [(component_type=comp, class="light", brand="generic", route_severity=0.0,
          entry_age_km=0.0, exit_age_km=weibull_sample(rng, β, η), status=1) for _ in 1:60],
        [(component_type=comp, class="light", brand="generic", route_severity=0.0,
          entry_age_km=0.0, exit_age_km=weibull_sample(rng, β, η) * 0.6, status=0) for _ in 1:12])
    hist = vcat(mk("battery", 2.0, 50_000.0), mk("brake_pad", 1.8, 80_000.0))
    live = [(tenant_id="t", vehicle_id="v$i",
             component_type=isodd(i) ? "battery" : "brake_pad", class="light", brand="generic",
             route_severity=0.0, current_age_km=20_000.0 + 1_000i,
             precursor_reading = isodd(i) ? 12.3 : missing) for i in 1:24]
    costs = Dict("battery" => (2500.0, 6000.0), "brake_pad" => (2200.0, 8000.0))
    run_estimates(hist, live, costs; run_id="precompile", nboot=100, rng=MersenneTwister(2))
end
println("precompile_app: camino de estimación ejercitado.")
