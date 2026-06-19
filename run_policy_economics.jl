#!/usr/bin/env julia
# ============================================================================
# run_policy_economics.jl — Comparación de 4 POLÍTICAS × 2 escenarios de FLOTA, en PDF.
#
# Políticas:
#   1) Reactivo            (run-to-failure)
#   2) Intervalo fijo      (preventivo por tiempo/km, programado a 0.7·MTTF — lo que hacen hoy)
#   3) Óptimo T*           (preventivo por edad, intervalo matemáticamente óptimo)
#   4) Predictivo (CBM)    (toda la maquinaria: precursor + RUL + regla IFR)
# Escenarios: flota NUEVA de agencia (sin edad previa) vs flota USADA (edad preexistente).
# Usa la simulación agente-física ya construida. Exporta PDF presentable.
#
#   julia --project=. run_policy_economics.jl
# ============================================================================
ENV["GKSwstype"] = "100"
using Printf, Statistics, Distributions, StatsPlots
const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
const DM = MaintenanceSim.DamageModels; const FIG = joinpath(ROOT, "figures"); mkpath(FIG)
const Ec = MaintenanceSim.Economics; const Pol = MaintenanceSim.Policy; const Pr = MaintenanceSim.Precursors
theme(:wong); default(dpi=150, legendfontsize=8, titlefontsize=10, guidefontsize=9, framestyle=:box)

NV, H = 60, 1460
comps = [c.name for c in DM.COMPONENTS if :heavy_truck in c.classes]

# Construye los T* (fijo y óptimo) y la política predictiva a partir de la verdad de un escenario.
function policies(lives, truth)
    recs_z(c) = [pl.z for pl in lives if pl.component == c]
    Tfix = Dict{String,Float64}(); Topt = Dict{String,Float64}()
    for c in comps
        tc = truth.comp[c]; zb = mean(recs_z(c))
        ηf = mean(v for (k,v) in truth.eta0 if last(k)==c) * exp(tc.gamma*zb)
        mttf = mean(Weibull(tc.beta, ηf))
        Tfix[c] = 0.7 * mttf                                   # intervalo programado (no óptimo)
        Topt[c] = MaintenanceSim.Decision.optimal_age(tc.beta, ηf, tc.cp, tc.cf)[1]
    end
    cbm = [c for c in comps if haskey(Pr.PRECURSOR_INFO, c)]
    alarm = Dict(c=>Pr.alarm_fraction(c) for c in cbm); scv = Dict(c=>Pr.sensor_cv(c) for c in cbm)
    return Tfix, Topt, Pol.PredictiveRUL(alarm, scv, 14, Topt)
end

# Curvas de costo acumulado (VPN) de las 4 políticas para una flota dada.
function cost_curves(lives, truth)
    Tfix, Topt, pol_pred = policies(lives, truth)
    cfg  = Ec.EconConfig()                                            # con costo de programa (telemática)
    cfg0 = Ec.EconConfig(hw_per_vehicle=0.0, monthly_fee=0.0)         # calendario: sin programa
    e_fix  = Ec.run_economics(lives, Pol.evaluate, Pol.Reactive(), Pol.AgeReplace(Tfix), cfg0; horizon_days=H, n_vehicles=NV)
    e_opt  = Ec.run_economics(lives, Pol.evaluate, Pol.Reactive(), Pol.AgeReplace(Topt), cfg0; horizon_days=H, n_vehicles=NV)
    e_pred = Ec.run_economics(lives, Pol.evaluate, Pol.Reactive(), pol_pred,             cfg;  horizon_days=H, n_vehicles=NV)
    months = e_pred.day_points ./ 30
    return (months=months, reactivo=e_pred.cum_reactive, fijo=e_fix.cum_preventive,
            optimo=e_opt.cum_preventive, predictivo=e_pred.cum_preventive)
end

function panel(cc, title_)
    p = plot(title=title_, xlabel="mes", ylabel="costo acumulado (millones MXN)", legend=:topleft)
    plot!(p, cc.months, cc.reactivo ./1e6,   lw=3, color=:firebrick,  label="Reactivo (run-to-failure)")
    plot!(p, cc.months, cc.fijo ./1e6,        lw=3, color=:orange,     label="Intervalo fijo (0.7·MTTF)")
    plot!(p, cc.months, cc.optimo ./1e6,      lw=3, color=:steelblue,  label="Óptimo T* (por edad)")
    plot!(p, cc.months, cc.predictivo ./1e6,  lw=3, color=:seagreen,   label="Predictivo CBM (+programa)")
    p
end

println("Escenario NUEVA (de agencia)…")
lN, tN, _ = MaintenanceSim.LifeProcess.generate_life_processes(
    MaintenanceSim.LifeProcess.LifeConfig(n_vehicles=NV, horizon_days=H, seed=7, f_trunc=0.0))
ccN = cost_curves(lN, tN)
println("Escenario USADA (edad preexistente)…")
lU, tU, _ = MaintenanceSim.LifeProcess.generate_life_processes(
    MaintenanceSim.LifeProcess.LifeConfig(n_vehicles=NV, horizon_days=H, seed=7, f_trunc=1.0))
ccU = cost_curves(lU, tU)

fin(cc) = (react=cc.reactivo[end]/1e6, fijo=cc.fijo[end]/1e6, opt=cc.optimo[end]/1e6, pred=cc.predictivo[end]/1e6)
for (lab, cc) in [("NUEVA", ccN), ("USADA", ccU)]
    f = fin(cc)
    @printf("%-6s (M MXN a %.0f años): reactivo %.1f · fijo %.1f · óptimo %.1f · predictivo %.1f\n",
            lab, H/365, f.react, f.fijo, f.opt, f.pred)
end

P = plot(panel(ccN, "Flota NUEVA (de agencia, sin edad previa)"),
         panel(ccU, "Flota USADA (con edad preexistente, ~años de uso)"),
         layout=(1,2), size=(1500,560),
         plot_title="Costo por política de mantenimiento — 4 políticas × 2 flotas")
savefig(P, joinpath(FIG, "politicas_economia.pdf"))
savefig(P, joinpath(FIG, "politicas_economia.png"))
println("→ figures/politicas_economia.{pdf,png}")
