# ============================================================================
# Tests del estudio contrafactual económico (CRN + políticas + economía).
# Correr:  julia test/test_economics.jl
# ============================================================================
using Test, Random, Statistics

const ROOT = abspath(joinpath(@__DIR__, ".."))
isdefined(Main, :MaintenanceSim) || include(joinpath(ROOT, "src", "MaintenanceSim.jl"))
using .MaintenanceSim
using .MaintenanceSim.LifeProcess, .MaintenanceSim.Survival, .MaintenanceSim.Decision,
      .MaintenanceSim.Policy, .MaintenanceSim.Economics

@testset "Estudio económico contrafactual" begin

    lives, truth = generate_life_processes(LifeProcess.LifeConfig(
        n_vehicles=60, horizon_days=1825, seed=7))
    comps = unique([l.component for l in lives])

    @testset "sustrato CRN + vidas reactivas" begin
        @test length(lives) > 100
        recs = reduce(vcat, [life_records(pl) for pl in lives])
        @test any(r -> r.status > 0, recs)          # hay fallas
        @test any(r -> r.status == 0, recs)         # hay censura
        @test all(r -> r.exit_age >= r.entry_age, recs)
    end

    # T* desde el mundo reactivo, con gate IFR + materialidad
    Tstar = Dict{String,Float64}()
    for comp in comps
        recs = filter(r -> r.component_type == comp, reduce(vcat, [life_records(pl) for pl in lives]))
        fit = fit_grouped(recs; nboot=12, rng=MersenneTwister(3))
        dec = Decision.decide(comp, fit.beta, fit.beta_lo, mean(values(fit.eta0)),
                              truth.comp[comp].cp, truth.comp[comp].cf)
        Tstar[comp] = dec.preventive ? dec.Tstar : Inf
    end

    @testset "gate IFR — battery rechazado, brake aceptado" begin
        @test isinf(Tstar["battery"])               # β≈1 → sin preventivo
        @test !isinf(Tstar["brake_pad"])            # desgaste → preventivo
        @test Tstar["brake_pad"] > 0
    end

    @testset "políticas — preventivo reduce fallas (CRN)" begin
        brakes = filter(l -> l.component == "brake_pad", lives)
        nfail_react = sum(count(o -> o.kind == :failure, evaluate(pl, Reactive())) for pl in brakes)
        nfail_age = sum(count(o -> o.kind == :failure,
                              evaluate(pl, AgeReplace(Tstar))) for pl in brakes)
        @test nfail_age < nfail_react               # el preventivo evita fallas
        nprev_age = sum(count(o -> o.kind == :preventive,
                              evaluate(pl, AgeReplace(Tstar))) for pl in brakes)
        @test nprev_age > 0                         # hubo reemplazos preventivos

        # battery (T*=Inf): el brazo "preventivo" == reactivo (mismo mundo, sin preventivo)
        bat = first(filter(l -> l.component == "battery", lives))
        @test evaluate(bat, AgeReplace(Tstar)) == evaluate(bat, Reactive())
    end

    @testset "economía — ahorro positivo, break-even, estabilización" begin
        cfg = Economics.EconConfig()
        econ = run_economics(lives, Policy.evaluate, Reactive(), AgeReplace(Tstar), cfg;
                             horizon_days=1825, n_vehicles=60)
        @test econ.cum_savings[end] > 0             # el preventivo ahorra (neto)
        @test econ.breakeven_day !== nothing        # hay break-even en el horizonte
        @test econ.stabilization_day !== nothing    # la distribución se estabiliza
        # la tasa de fallas sube del transitorio al régimen (flota joven → estacionario)
        early = mean(econ.monthly_fail_reactive[1:3])
        late = mean(econ.monthly_fail_reactive[end-5:end])
        @test late >= early                          # ramp-up del proceso de renovación

        # predictivo captura más ahorro que el calendario (usa la condición)
        alarm = Dict("brake_pad"=>0.80, "dpf"=>0.82, "scr"=>0.90, "battery"=>0.85)
        scv = Dict("brake_pad"=>0.6, "dpf"=>1.0, "scr"=>1.4, "battery"=>1.0)
        econ_p = run_economics(lives, Policy.evaluate, Reactive(),
                               PredictiveRUL(alarm, scv, 14, Tstar), cfg;
                               horizon_days=1825, n_vehicles=60)
        @test econ_p.cum_savings[end] >= econ.cum_savings[end]
    end

    @testset "EUAC — vida económica finita" begin
        yrs, euac = Economics.euac_curve(250_000.0, Economics.EconConfig())
        @test length(yrs) == length(euac)
        @test all(>(0), euac)
        @test argmin(euac) >= 1                      # hay una vida económica óptima
    end
end
