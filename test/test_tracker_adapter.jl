# ============================================================================
# Tests del ADAPTADOR tracker_prod ↔ estimador (mapeo puro + orquestación batch).
# No toca la BD: usa filas NamedTuple como las que entregarían las vistas SQL (migración 004).
# Correr:  julia --project=. test/test_tracker_adapter.jl
# ============================================================================
using Test, Random, Distributions

const ROOT = abspath(joinpath(@__DIR__, ".."))
isdefined(Main, :MaintenanceSim) || include(joinpath(ROOT, "src", "MaintenanceSim.jl"))
using .MaintenanceSim
using .MaintenanceSim.TrackerAdapter, .MaintenanceSim.Estimator

@testset "TrackerAdapter — mapeo puro y orquestación batch" begin

    @testset "to_service_record / to_live_unit (incl. NULL→nothing)" begin
        sr = to_service_record((component_type="battery", class="light", brand="generic",
                                route_severity=0.0, entry_age_km=0.0, exit_age_km=42000.0, status=1))
        @test sr isa ServiceRecord
        @test sr.component_type == "battery" && sr.class == :light && sr.status == 1
        @test sr.exit_age == 42000.0

        u_cbm = to_live_unit((component_type="battery", class="light", brand="generic",
                              route_severity=0.0, current_age_km=23000.0, precursor_reading=12.4))
        @test u_cbm.precursor_reading == 12.4
        # precursor NULL (missing) ⇒ nothing (sin CBM)
        u_nocbm = to_live_unit((component_type="oil", class="light", brand="generic",
                                route_severity=0.0, current_age_km=15000.0, precursor_reading=missing))
        @test u_nocbm.precursor_reading === nothing
    end

    @testset "to_costs omite costos NULL" begin
        cat = [(component_type="battery", cp_mxn=2500.0, cf_mxn=6000.0),
               (component_type="oil",     cp_mxn=1200.0, cf_mxn=15000.0),
               (component_type="belt",    cp_mxn=missing, cf_mxn=9000.0)]   # sin cp ⇒ omitido
        costs = to_costs(cat)
        @test costs["battery"] == (2500.0, 6000.0)
        @test haskey(costs, "oil") && !haskey(costs, "belt")
    end

    @testset "to_prediction_row mapea todas las columnas de pdm_prediction" begin
        est = MaintenanceEstimate("battery", 100.0, 2.0, 1.5, 50000.0, 40000.0, true, 40000.0, false, "ok")
        row = to_prediction_row(est, (tenant_id="t1", vehicle_id="v1", run_id="r1", current_age_km=10000.0))
        for col in (:tenant_id, :vehicle_id, :component_type, :run_id, :current_age_km, :rul_km,
                    :beta, :beta_lo, :eta, :optimal_interval_km, :recommend_preventive,
                    :recommend_at_km, :cbm_alarm, :rationale)
            @test haskey(row, col)
        end
        @test row.vehicle_id == "v1" && row.rul_km == 100.0 && row.optimal_interval_km == 40000.0
        # T* nothing (IFR rehúsa) ⇒ NULL en la fila
        est0 = MaintenanceEstimate("oil", 50.0, 0.9, 0.7, 30000.0, nothing, false, 30050.0, false, "rtf")
        @test to_prediction_row(est0, (tenant_id="t", vehicle_id="v", run_id="r", current_age_km=0.0)).optimal_interval_km === nothing
    end

    @testset "run_estimates: recupera β, mantiene identidad, omite sin modelo" begin
        rng = MersenneTwister(7)
        W = Weibull(2.0, 50000.0)
        hist = vcat(
            [(component_type="battery", class="light", brand="generic", route_severity=0.0,
              entry_age_km=0.0, exit_age_km=rand(rng, W), status=1) for _ in 1:50],
            [(component_type="battery", class="light", brand="generic", route_severity=0.0,
              entry_age_km=0.0, exit_age_km=rand(rng, W)*0.6, status=0) for _ in 1:10])   # censuras
        live = [(tenant_id="t1", vehicle_id="v$i", component_type="battery", class="light",
                 brand="generic", route_severity=0.0, current_age_km=20000.0+3000i,
                 precursor_reading=missing) for i in 1:5]
        costs = Dict("battery"=>(2500.0, 6000.0))

        preds = run_estimates(hist, live, costs; run_id="run-1", nboot=60, rng=MersenneTwister(11))
        @test length(preds) == 5                                   # una por unidad viva
        @test Set(p.vehicle_id for p in preds) == Set("v$i" for i in 1:5)   # identidad intacta
        @test all(p.run_id == "run-1" for p in preds)
        @test all(p.component_type == "battery" for p in preds)
        @test abs(first(preds).beta - 2.0) / 2.0 < 0.20            # recupera β (con ruido bootstrap)
        @test all(p.rul_km > 0 for p in preds)

        # unidad de componente sin historial/costo ⇒ omitida
        live_oil = [(tenant_id="t1", vehicle_id="x", component_type="oil", class="light",
                     brand="generic", route_severity=0.0, current_age_km=15000.0, precursor_reading=missing)]
        @test isempty(run_estimates(hist, live_oil, costs; run_id="r", nboot=20, rng=MersenneTwister(1)))
    end
end
