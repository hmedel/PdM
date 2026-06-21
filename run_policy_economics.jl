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

# Idioma de las figuras: FIGLANG=en para inglés (default español). Preserva los nombres ES de archivo.
const FIGLANG = get(ENV, "FIGLANG", "es")
tr(es, en) = FIGLANG == "en" ? en : es
P_react = tr("Reactivo", "Reactive");   P_fix  = tr("Intervalo fijo", "Fixed interval")
P_opt   = tr("Óptimo T*", "Optimal T*"); P_pred = tr("Predictivo CBM", "Predictive CBM")
L_month = tr("mes", "month")

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

function panel(cc, title_; ylab::Bool=true)
    p = plot(title=title_, xlabel=L_month, legend=:topleft, left_margin=8Plots.mm, bottom_margin=5Plots.mm,
             ylabel = ylab ? tr("costo acumulado (millones MXN)", "cumulative cost (million MXN)") : "")
    plot!(p, cc.months, cc.reactivo ./1e6,   lw=3, color=:firebrick,  label=P_react)
    plot!(p, cc.months, cc.fijo ./1e6,        lw=3, color=:orange,     label=P_fix)
    plot!(p, cc.months, cc.optimo ./1e6,      lw=3, color=:steelblue,  label=P_opt)
    plot!(p, cc.months, cc.predictivo ./1e6,  lw=3, color=:seagreen,   label=P_pred)
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

# Distribución de EVENTOS por política: fallas (en ruta, caras/peligrosas) vs reemplazos preventivos.
function event_counts(lives, truth)
    Tfix, Topt, pol_pred = policies(lives, truth)
    pols = [P_react=>Pol.Reactive(), P_fix=>Pol.AgeReplace(Tfix),
            P_opt=>Pol.AgeReplace(Topt), P_pred=>pol_pred]
    labs = String[]; fails = Int[]; prevs = Int[]
    for (lab, pol) in pols
        o = reduce(vcat, [Pol.evaluate(pl, pol) for pl in lives])
        push!(labs, lab); push!(fails, count(x->x.kind==:failure, o)); push!(prevs, count(x->x.kind==:preventive, o))
    end
    labs, fails, prevs
end
labs, fails, prevs = event_counts(lN, tN)
@printf("Eventos (flota nueva): %s\n", join(["$(labs[i]): $(fails[i]) fallas / $(prevs[i]) prev" for i in eachindex(labs)], " · "))
pEv = groupedbar(labs, hcat(fails, prevs), bar_position=:stack, xrotation=15,
    label=[tr("Fallas (en ruta — caras/peligrosas)", "Failures (on-road — costly/dangerous)") tr("Reemplazos preventivos (taller)", "Preventive replacements (shop)")],
    color=[:firebrick :seagreen], title=tr("Eventos por política (flota nueva) — el predictivo convierte fallas en preventivos", "Events by policy (new fleet) — predictive turns failures into preventives"),
    ylabel=tr("nº de eventos en 4 años", "events over 4 years"))
fnE = tr("politicas_eventos", "events_by_policy")
savefig(pEv, joinpath(FIG, fnE*".pdf")); savefig(pEv, joinpath(FIG, fnE*".png"))
println("→ figures/$fnE.{pdf,png}")

# Descomposturas que INMOVILIZAN el vehículo (falla en ruta) acumuladas en el tiempo, por política.
function breakdown_curves(lives, truth)
    Tfix, Topt, pol_pred = policies(lives, truth)
    pols = [P_react=>Pol.Reactive(), P_fix=>Pol.AgeReplace(Tfix),
            P_opt=>Pol.AgeReplace(Topt), P_pred=>pol_pred]
    months = collect(0:Int(round(H/30)))
    series = Pair{String,Vector{Int}}[]
    for (lab, pol) in pols
        o = reduce(vcat, [Pol.evaluate(pl, pol) for pl in lives])
        days = sort([x.end_day for x in o if x.kind == :failure && x.in_route])
        push!(series, lab => [count(d -> d <= m*30, days) for m in months])
    end
    return months, series
end
mB, sB = breakdown_curves(lN, tN)
cols = Dict(P_react=>:firebrick, P_fix=>:orange, P_opt=>:steelblue, P_pred=>:seagreen)
pBk = plot(title=tr("Descomposturas que inmovilizan el vehículo, por política", "Breakdowns that immobilize the vehicle, by policy"),
           xlabel=L_month, ylabel=tr("descomposturas acumuladas (vehículo parado en ruta)", "cumulative breakdowns (vehicle stranded on-road)"),
           legend=:topleft, left_margin=8Plots.mm, bottom_margin=5Plots.mm, size=(1000,560))
for (lab, ys) in sB
    plot!(pBk, mB, ys, lw=3, color=cols[lab], label=lab)
end
fnB = tr("descomposturas_politicas", "immobilizing_breakdowns_by_policy")
savefig(pBk, joinpath(FIG, fnB*".pdf")); savefig(pBk, joinpath(FIG, fnB*".png"))
@printf("Descomposturas en ruta (4 años): %s\n", join(["$(lab): $(ys[end])" for (lab,ys) in sB], " · "))
println("→ figures/$fnB.{pdf,png}")

# Intervenciones TOTALES por política: fallas correctivas + reemplazos preventivos.
# Hace visible el sobre-mantenimiento: T* logra seguridad similar al CBM pero con muchos más preventivos.
tot = fails .+ prevs
pI = groupedbar(labs, hcat(fails, prevs), bar_position=:stack, xrotation=0,
    label=[tr("Fallas correctivas", "Corrective failures") tr("Reemplazos preventivos", "Preventive replacements")], color=[:firebrick :steelblue],
    title=tr("Intervenciones totales por política — flota nueva", "Total interventions by policy — new fleet"),
    ylabel=tr("nº de intervenciones en 4 años", "interventions over 4 years"), legend=:topleft,
    left_margin=8Plots.mm, bottom_margin=6Plots.mm, size=(1000,580), ylims=(0, 1.14*maximum(tot)))
for (i, tt) in enumerate(tot)
    annotate!(pI, i, tt + 0.035*maximum(tot), text(string(tt), 9, :black, :center))
end
fnI = tr("intervenciones_politicas", "total_interventions_by_policy")
savefig(pI, joinpath(FIG, fnI*".pdf")); savefig(pI, joinpath(FIG, fnI*".png"))
@printf("Intervenciones totales (4 años): %s\n", join(["$(labs[i]): $(tot[i]) ($(fails[i])f+$(prevs[i])p)" for i in eachindex(labs)], " · "))
println("→ figures/$fnI.{pdf,png}")

P = plot(panel(ccN, tr("Flota NUEVA", "NEW fleet"); ylab=true),
         panel(ccU, tr("Flota USADA", "USED fleet"); ylab=false),
         layout=(1,2), size=(1500,560),
         plot_title=tr("Costo por política de mantenimiento", "Cost by maintenance policy"))
fnC = tr("politicas_economia", "cost_by_policy")
savefig(P, joinpath(FIG, fnC*".pdf")); savefig(P, joinpath(FIG, fnC*".png"))
println("→ figures/$fnC.{pdf,png}")
