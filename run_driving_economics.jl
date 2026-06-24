#!/usr/bin/env julia
# ============================================================================
# run_driving_economics.jl — "El manejo mueve las cifras": cómo el ESTILO DE MANEJO
# del conductor (índice observable derivado de OBD/CAN) desplaza la distribución de
# vida POR UNIDAD y, con ello, el intervalo óptimo T* y el costo por unidad-año.
#
# Historia (toda recuperada del dato observable, sin verdad oculta):
#   1) El simulador agente-físico genera heterogeneidad de manejo (drive_spread>0) que
#      mueve la vida real de cada unidad: η_i = η0·exp(−κ·z_ruta − κ_drive·(idx−0.5)).
#   2) El estimador Weibull-AFT de 2 covariables RECUPERA γ_drive del índice observable.
#   3) Con la η por unidad recuperada se recomputan T* (Barlow-Proschan) y el costo/unidad-año.
#
#   julia --project=. run_driving_economics.jl        # ES (default);  FIGLANG=en para inglés
# ============================================================================
ENV["GKSwstype"] = "100"
using Printf, Statistics, Distributions, StatsPlots, Random
const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
const DM = MaintenanceSim.DamageModels; const Dec = MaintenanceSim.Decision
const FIG = joinpath(ROOT, "figures"); mkpath(FIG)
theme(:wong); default(dpi=150, legendfontsize=8, titlefontsize=10, guidefontsize=9, framestyle=:box)

const FIGLANG = get(ENV, "FIGLANG", "es")
tr(es, en) = FIGLANG == "en" ? en : es

# --- 1) flota con heterogeneidad de manejo + ajuste AFT de 2 covariables ---
const COMP = "brake_pad"                       # data-rico y muy sensible al manejo (mecanismo :brake)
println("Simulando flota con heterogeneidad de manejo (drive_spread=1.0)…")
out = simulate_fleet(MaintenanceSim.FleetSimulator.SimConfig(
        n_vehicles=300, horizon_days=900, seed=424242, drive_spread=1.0))
recs = filter(r -> r.component_type == COMP, out.survival)
fit  = fit_grouped(recs; nboot=15, rng=MersenneTwister(7))
bp   = DM.COMPONENTS[findfirst(c -> c.name == COMP, DM.COMPONENTS)]
cp, cf, β = bp.cp, bp.cf, fit.beta
z̄  = mean(r.route_severity for r in recs)
η̄0 = mean(values(fit.eta0))
# η por unidad recuperada como función del índice de manejo observable (ruta fija = media)
ηunit(idx) = η̄0 * exp(fit.gamma * z̄ + fit.gamma_drive * idx)
@printf("β=%.2f  γ_ruta=%.2f  γ_manejo=%.2f  (κ_drive verdad=%.2f)\n",
        β, fit.gamma, fit.gamma_drive, DM.drive_sensitivity(:brake))

# --- costo de largo plazo del reemplazo por edad C(T) (Barlow-Proschan), Weibull ---
function cost_rate(T, β, η, cp, cf)
    R(u) = exp(-(u / η)^β)
    n = 240; us = range(1e-6, T, length=n)
    integ = sum((R(us[i]) + R(us[i+1])) / 2 * (us[i+1] - us[i]) for i in 1:n-1)
    F = 1 - R(T)
    return (cp * R(T) + cf * F) / integ                    # costo por hora-motor
end
HPY = 2000.0                                                # horas-motor por unidad-año (aprox.)

# --- 2) Panel A: la distribución de vida por unidad se desplaza con el manejo ---
gentle_idx, aggr_idx = 0.2, 0.8
ηg, ηa = ηunit(gentle_idx), ηunit(aggr_idx)
us = range(0, quantile(Weibull(β, ηg), 0.999), length=400)
pdfW(η) = [pdf(Weibull(β, η), u) for u in us]
pA = plot(title=tr("La vida por unidad se desplaza con el manejo", "Per-unit life shifts with driving"),
          xlabel=tr("vida (horas-motor)", "life (engine-hours)"),
          ylabel=tr("densidad", "density"), legend=:topright,
          left_margin=8Plots.mm, bottom_margin=5Plots.mm)
plot!(pA, us, pdfW(ηg), lw=3, color=:seagreen,  fill=(0, 0.15, :seagreen),
      label=tr("manejo suave (idx=0.2)", "gentle driving (idx=0.2)"))
plot!(pA, us, pdfW(ηa), lw=3, color=:firebrick, fill=(0, 0.15, :firebrick),
      label=tr("manejo agresivo (idx=0.8)", "aggressive driving (idx=0.8)"))
vline!(pA, [mean(Weibull(β, ηg))], color=:seagreen,  ls=:dash, label="")
vline!(pA, [mean(Weibull(β, ηa))], color=:firebrick, ls=:dash, label="")

# --- 3) Panel B: T* óptimo vs índice de manejo ---
idxs = collect(0.0:0.02:1.0)
Tstars = [Dec.optimal_age(β, ηunit(i), cp, cf)[1] for i in idxs]
pB = plot(idxs, Tstars, lw=3, color=:steelblue, legend=false,
          title=tr("El intervalo óptimo T* baja con el manejo", "Optimal interval T* drops with driving"),
          xlabel=tr("índice de manejo (OBD/CAN)", "driving index (OBD/CAN)"),
          ylabel=tr("T* (horas-motor)", "T* (engine-hours)"),
          left_margin=8Plots.mm, bottom_margin=5Plots.mm)

# --- 4) Panel C: costo por unidad-año vs manejo (T* por unidad vs reactivo vs T* ciego) ---
T_blind = Dec.optimal_age(β, ηunit(0.5), cp, cf)[1]        # política que IGNORA el manejo (idx medio)
cost_unit_aware = [cost_rate(Dec.optimal_age(β, ηunit(i), cp, cf)[1], β, ηunit(i), cp, cf) * HPY for i in idxs]
cost_blind      = [cost_rate(T_blind, β, ηunit(i), cp, cf) * HPY for i in idxs]
cost_reactive   = [cf / mean(Weibull(β, ηunit(i))) * HPY for i in idxs]
pC = plot(title=tr("Costo por unidad-año (el manejo lo mueve)", "Cost per unit-year (driving moves it)"),
          xlabel=tr("índice de manejo (OBD/CAN)", "driving index (OBD/CAN)"),
          ylabel=tr("costo (MXN/unidad-año)", "cost (MXN/unit-year)"), legend=:topleft,
          left_margin=8Plots.mm, bottom_margin=5Plots.mm)
plot!(pC, idxs, cost_reactive,    lw=3, color=:firebrick, label=tr("Reactivo", "Reactive"))
plot!(pC, idxs, cost_blind,       lw=3, color=:orange,    label=tr("T* ciego al manejo", "driving-blind T*"))
plot!(pC, idxs, cost_unit_aware,  lw=3, color=:seagreen,  label=tr("T* por unidad (consciente)", "per-unit T* (aware)"))

P = plot(pA, pB, pC, layout=(1, 3), size=(1650, 520),
         plot_title=tr("El manejo mueve la vida y el costo por unidad",
                       "Driving moves per-unit life and cost"))
fn = tr("manejo_economia", "driving_economics")
savefig(P, joinpath(FIG, fn * ".pdf")); savefig(P, joinpath(FIG, fn * ".png"))

@printf("T*: suave(idx=0.2)=%.0f h · medio=%.0f h · agresivo(idx=0.8)=%.0f h  (horas-motor)\n",
        Dec.optimal_age(β, ηunit(0.2), cp, cf)[1], T_blind, Dec.optimal_age(β, ηunit(0.8), cp, cf)[1])
@printf("Ahorro del T* consciente vs ciego en unidad agresiva: %.0f MXN/unidad-año\n",
        (cost_rate(T_blind, β, ηunit(0.8), cp, cf) -
         cost_rate(Dec.optimal_age(β, ηunit(0.8), cp, cf)[1], β, ηunit(0.8), cp, cf)) * HPY)
println("→ figures/$fn.{pdf,png}")
