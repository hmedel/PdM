# ============================================================================
# Tests de la API del ESTIMADOR (forma batch de servidor): fit_component / estimate / estimate_fleet.
# Correr:  julia --project=. test/test_estimator.jl
# ============================================================================
using Test, Random, Statistics

const ROOT = abspath(joinpath(@__DIR__, ".."))
isdefined(Main, :MaintenanceSim) || include(joinpath(ROOT, "src", "MaintenanceSim.jl"))
using .MaintenanceSim
using .MaintenanceSim.Estimator, .MaintenanceSim.LifeProcess, .MaintenanceSim.Policy

@testset "Estimador — API batch (fit_component / estimate / estimate_fleet)" begin
    lives, truth, _ = generate_life_processes(LifeConfig(n_vehicles=60, horizon_days=1095, seed=7))
    history = reduce(vcat, [life_records(pl) for pl in lives])
    recs(c) = filter(r -> r.component_type == c, history)
    cpcf(c) = (truth.comp[c].cp, truth.comp[c].cf)

    @testset "fit_component ajusta el modelo del componente" begin
        cp, cf = cpcf("brake_pad")
        m = fit_component(recs("brake_pad"); cp=cp, cf=cf, nboot=20, rng=MersenneTwister(3))
        @test m isa ComponentModel
        @test m.component_type == "brake_pad"
        @test abs(m.fit.beta - truth.comp["brake_pad"].beta) / truth.comp["brake_pad"].beta < 0.10
        @test m.has_precursor                                   # brake_pad tiene precursor (balata)
        @test m.decision.preventive                             # desgaste β>1 ⇒ preventivo
    end

    @testset "estimate(model,unit) ≡ estimate_maintenance(history,unit)" begin
        cp, cf = cpcf("brake_pad")
        unit = LiveUnit("brake_pad", :heavy_truck, "Kenworth", 0.6, 800.0, 6.0)
        m  = fit_component(recs("brake_pad"); cp=cp, cf=cf, nboot=20, rng=MersenneTwister(3))
        e1 = estimate(m, unit)
        e2 = estimate_maintenance(recs("brake_pad"), unit; cp=cp, cf=cf, nboot=20, rng=MersenneTwister(3))
        @test e1.beta == e2.beta
        @test e1.rul == e2.rul
        @test e1.recommend_at_age == e2.recommend_at_age       # wrapper = fit_component + estimate
    end

    @testset "T* escala lineal con η de la unidad (exacto en Weibull)" begin
        cp, cf = cpcf("brake_pad")
        m = fit_component(recs("brake_pad"); cp=cp, cf=cf, nboot=20, rng=MersenneTwister(3))
        a = estimate(m, LiveUnit("brake_pad", :heavy_truck, "Kenworth", 0.2, 500.0, nothing))
        b = estimate(m, LiveUnit("brake_pad", :heavy_truck, "Kenworth", 0.8, 500.0, nothing))
        @test a.optimal_interval !== nothing && b.optimal_interval !== nothing
        @test b.optimal_interval / a.optimal_interval ≈ b.eta / a.eta rtol=1e-6
    end

    @testset "componente estadístico (tire): sin precursor ⇒ sin CBM" begin
        cp, cf = cpcf("tire")
        m = fit_component(recs("tire"); cp=cp, cf=cf, nboot=10, rng=MersenneTwister(3))
        @test m.has_precursor == false
        e = estimate(m, LiveUnit("tire", :heavy_truck, "Kenworth", 0.5, 1000.0, 999.0))  # lectura ignorada
        @test e.cbm_alarm == false
    end

    @testset "battery (β≈1): IFR rehúsa preventivo en el modelo" begin
        cp, cf = cpcf("battery")
        m = fit_component(recs("battery"); cp=cp, cf=cf, nboot=25, rng=MersenneTwister(5))
        @test m.decision.preventive == false
    end

    @testset "estimate_fleet: ajusta por tipo, evalúa la flota, omite lo no ajustable" begin
        costs = Dict("brake_pad" => cpcf("brake_pad"), "battery" => cpcf("battery"))
        units = [
            LiveUnit("brake_pad", :heavy_truck, "Kenworth", 0.6, 400.0, 6.0),
            LiveUnit("brake_pad", :heavy_truck, "Kenworth", 0.3, 900.0, 2.0),
            LiveUnit("battery",   :heavy_truck, "Kenworth", 0.5, 600.0, nothing),
            LiveUnit("desconocido", :heavy_truck, "Kenworth", 0.5, 100.0, nothing),  # sin historial/costo
        ]
        res = estimate_fleet(history, units, costs; nboot=10, rng=MersenneTwister(1))
        @test length(res) == 3                                  # se omite "desconocido"
        @test Set(e.component_type for e in res) == Set(["brake_pad", "battery"])
        @test all(e -> e.rul >= 0, res)
    end
end
