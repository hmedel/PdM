# run_accident_policies.jl — Comportamiento de la TASA DE ACCIDENTES según la política de
# mantenimiento, para tres regímenes: (1) reactivo, (2) preventivo, (3) reactivo que incorpora
# preventivo poco a poco.
#
# Anclas documentadas (whitepaper §2.3 — FMCSA SMS):
#   - carrier con mal Vehicle Maintenance BASIC = 5.65 choques / 100 unidades-año
#   - promedio nacional (bien mantenido)        = 3.43 choques / 100 unidades-año   (+65% el reactivo)
# La transición del régimen (3) usa una fracción de adopción del preventivo φ(t) que sube de 0→~1.
using Plots, Printf

ROOT = @__DIR__
const FIG = joinpath(ROOT, "figures"); mkpath(FIG)
theme(:wong); default(dpi=150, legendfontsize=9, titlefontsize=12, guidefontsize=10, framestyle=:box)

# Idioma de las figuras: FIGLANG=en para inglés (default español). Preserva los nombres ES.
const FIGLANG = get(ENV, "FIGLANG", "es")
tr(es, en) = FIGLANG == "en" ? en : es
L_react = tr("Reactivo", "Reactive")
L_grad  = tr("Reactivo incorporando preventivo", "Reactive adopting preventive")
L_prev  = tr("Preventivo", "Preventive")
L_month = tr("mes", "month")

react = 5.65            # choques/100 unidades-año — reactivo (mal mantenimiento)
prev  = 3.43            # choques/100 unidades-año — preventivo establecido
H     = 48              # meses (4 años, mismo horizonte que la figura de costo)
t     = collect(0:H)

# (1) Reactivo: tasa alta y estable (cota; el envejecimiento IFR la empujaría más arriba).
rate_react = fill(react, length(t))
# (2) Preventivo: programa establecido, tasa baja y estable.
rate_prev  = fill(prev,  length(t))
# (3) Reactivo → preventivo: adopción gradual φ(t)=1-e^{-t/τ}; mezcla lineal de ambas tasas.
τ   = 15.0
phi = 1 .- exp.(-t ./ τ)
rate_grad = (1 .- phi) .* react .+ phi .* prev

# ---- Figura 1: TASA de accidentes (comportamiento) ----
p = plot(t, rate_react, lw=3, color=:firebrick, label=L_react,
         title=tr("Tasa de accidentes por política de mantenimiento", "Accident rate by maintenance policy"),
         xlabel=L_month, ylabel=tr("choques por 100 unidades-año", "crashes per 100 power units-year"),
         legend=:right, left_margin=8Plots.mm, bottom_margin=5Plots.mm,
         size=(950,540), ylims=(0, 6.4))
plot!(p, t, rate_grad, lw=3, color=:orange,   label=L_grad)
plot!(p, t, rate_prev, lw=3, color=:seagreen, label=L_prev)
hline!(p, [prev], color=:seagreen, ls=:dash, alpha=0.35, label=false)
annotate!(p, 2.2, (react+prev)/2, text("+65 %", 9, :firebrick, :left))
fn1 = tr("accidentes_politicas", "accident_rate_by_policy")
savefig(p, joinpath(FIG, fn1*".pdf")); savefig(p, joinpath(FIG, fn1*".png"))

# ---- Figura 2: accidentes ACUMULADOS (impacto) para una flota de 100 unidades ----
# Para 100 unidades, accidentes/mes = tasa/12; el acumulado integra la tasa en el tiempo.
fleet = 100
cumacc(r) = [isempty(2:i) ? 0.0 : sum(@view r[2:i]) for i in 1:length(r)] .* (fleet/100) ./ 12
cum_react = cumacc(rate_react); cum_grad = cumacc(rate_grad); cum_prev = cumacc(rate_prev)

q = plot(t, cum_react, lw=3, color=:firebrick, label=L_react,
         title=tr("Accidentes acumulados por política (flota de 100 unidades)", "Cumulative accidents by policy (100-unit fleet)"),
         xlabel=L_month, ylabel=tr("accidentes acumulados (4 años)", "cumulative accidents (4 years)"),
         legend=:topleft, left_margin=8Plots.mm, bottom_margin=5Plots.mm, size=(950,540))
plot!(q, t, cum_grad, lw=3, color=:orange,   label=L_grad)
plot!(q, t, cum_prev, lw=3, color=:seagreen, label=L_prev)
# Sombrea el área evitada entre reactivo y preventivo establecido (el premio de seguridad).
plot!(q, t, cum_react, fillrange=cum_prev, fillalpha=0.10, color=:seagreen, label=false, lw=0)
annotate!(q, t[end]*0.5, (cum_react[end]+cum_prev[end])/2,
          text(tr("accidentes evitados", "accidents avoided"), 9, :seagreen, :center))
fn2 = tr("accidentes_acumulados", "cumulative_accidents_by_policy")
savefig(q, joinpath(FIG, fn2*".pdf")); savefig(q, joinpath(FIG, fn2*".png"))

@printf("Tasa final (choques/100u-año): reactivo %.2f · gradual %.2f · preventivo %.2f\n",
        rate_react[end], rate_grad[end], rate_prev[end])
@printf("Acumulado a 4 años (100 u): reactivo %.1f · gradual %.1f · preventivo %.1f → evitados (R-P) %.1f\n",
        cum_react[end], cum_grad[end], cum_prev[end], cum_react[end]-cum_prev[end])
println("→ figures/$fn1.{pdf,png} + $fn2.{pdf,png}")
