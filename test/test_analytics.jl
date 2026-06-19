# ============================================================================
# Tests de la API de Analytics (datos JSON-ready + alertas). Sin Turing/Plots.
#   julia --project=. test/test_analytics.jl
# ============================================================================
using Test, Random, Statistics

const ROOT = abspath(joinpath(@__DIR__, ".."))
isdefined(Main, :MaintenanceSim) || include(joinpath(ROOT, "src", "MaintenanceSim.jl"))
using .MaintenanceSim
using .MaintenanceSim.Analytics, .MaintenanceSim.Estimator, .MaintenanceSim.LifeProcess

@testset "Analytics — datos + alertas" begin
    lives, truth, _ = generate_life_processes(LifeConfig(n_vehicles=25, horizon_days=1095, seed=7))
    hist = reduce(vcat, [MaintenanceSim.Policy.life_records(pl) for pl in lives])
    recs = filter(r -> r.component_type == "brake_pad", hist)
    fit  = MaintenanceSim.Survival.fit_grouped(recs; nboot=20)
    d    = Analytics.from_grouped(fit; n=300)

    @testset "distribution_estimate (3 niveles + preventivo)" begin
        de = Analytics.distribution_estimate(d, recs; vehicle_z=0.8, Tstar=300.0)
        @test length(de.grid) == length(de.component_pdf) == length(de.fleet_pdf)
        @test de.vehicle_pdf !== nothing && length(de.vehicle_pdf) == length(de.grid)
        @test all(isfinite, de.component_pdf) && all(>=(0), de.component_pdf)
        @test 0.0 <= de.preventive_mass_at_Tstar <= 1.0
        @test de.mttf > 0 && de.stable_rate ≈ 1/de.mttf
        @test all(de.preventive_pdf[i] == 0 for i in eachindex(de.grid) if de.grid[i] > de.Tstar)  # censura en T*
    end

    @testset "parameter_summary (maneja draws constantes)" begin
        ps = Analytics.parameter_summary(d)        # γ y η0 son constantes en from_grouped
        @test ps.β.lo <= ps.β.mean <= ps.β.hi
        @test length(ps.γ.grid) == length(ps.γ.density)   # no revienta con draws constantes
    end

    @testset "master_equation + economics_summary" begin
        me = Analytics.master_equation(lives, "brake_pad"; horizon=1095)
        @test length(me.months) == length(me.rate) && all(>=(0), me.rate)
        es = Analytics.economics_summary(lives, truth; horizon=1095, n_vehicles=25)
        @test haskey(es.savings_by_component, "brake_pad")
        @test es.savings_by_component["brake_pad"] > es.savings_by_component["battery"]  # battery≈0 (IFR)
    end

    @testset "alertas componente/vehículo/flota" begin
        costs = Dict(c.name => (cp=truth.comp[c.name].cp, cf=truth.comp[c.name].cf)
                     for c in MaintenanceSim.DamageModels.COMPONENTS)
        m   = Estimator.fit_component(recs; cp=costs["brake_pad"].cp, cf=costs["brake_pad"].cf, nboot=15)
        # unidad con balata en alarma (3 mm < umbral 4 mm) y edad pasada de T*
        est = Estimator.estimate(m, Estimator.LiveUnit("brake_pad", :heavy_truck, "KW", 0.6, 500.0, 3.0))
        al  = Analytics.component_alerts(est; vehicle_id="V001", current_age=500.0)
        @test any(a -> a.code == "CBM_ALARM" && a.severity == :critical, al)
        va = Analytics.vehicle_alerts("V001", [est]; current_ages=Dict("brake_pad"=>500.0))
        @test any(a -> a.level == :vehicle && a.severity == :critical, va)
        # unidad sana (balata 15 mm, joven) → sin alerta crítica
        est2 = Estimator.estimate(m, Estimator.LiveUnit("brake_pad", :heavy_truck, "KW", 0.6, 50.0, 15.0))
        @test isempty(Analytics.component_alerts(est2; current_age=50.0))
    end
end
