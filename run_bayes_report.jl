#!/usr/bin/env julia
# ============================================================================
# run_bayes_report.jl — Genera las figuras del reporte bayesiano (→ figures/).
#
# Muestra, sobre datos SINTÉTICOS con verdad conocida:
#   (1) Posterior de los parámetros (β, η0, γ) vs verdad — por componente.
#   (2) Estimación de la distribución a 3 NIVELES: componente, vehículo, flota.
#   (3) Convergencia: el posterior se estrecha al acumular datos (∝ 1/√N).
#   (4) Solo-fallas (run-to-failure) → fallas+preventivo: cómo cambia la estimación.
#   (5) Ecuación maestra: tasa de falla y distribución de edades de la flota → estado estacionario.
#
# El ajuste bayesiano (Turing) es OFFLINE; los segundos no importan. Para los barridos se usa el
# modelo AFT de 3 params (rápido); para la demostración de frailty, el jerárquico (σ_v).
#
# Uso:  julia --project=. -t auto run_bayes_report.jl
# ============================================================================
ENV["GKSwstype"] = "100"            # GR headless → PNG sin display
using Printf, Statistics, Random
using StatsPlots, Distributions
const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
include(joinpath(ROOT, "src", "models", "bayes.jl")); using .BayesEstimator
const DM = MaintenanceSim.DamageModels
const FIG = joinpath(ROOT, "figures"); mkpath(FIG)
default(size=(820, 480), legendfontsize=8, dpi=130)

# ---------- datos sintéticos (mundo run-to-failure) -----------------------------------------------
NV, H = 60, 1460
lives, truth, vehlives = MaintenanceSim.LifeProcess.generate_life_processes(
    MaintenanceSim.LifeProcess.LifeConfig(n_vehicles=NV, horizon_days=H, seed=7))
allrecs = reduce(vcat, [MaintenanceSim.Policy.life_records(pl) for pl in lives])
rtf(comp) = filter(r -> r.component_type == comp, allrecs)
tru(comp) = truth.comp[comp]
println("Datos: $NV vehículos · $H días · $(length(allrecs)) registros")

# censura preventiva: una falla con vida > T* se habría reemplazado preventivamente (censura en T*)
function censor_at(records, Tstar)
    isinf(Tstar) && return records
    [r.status > 0 && r.exit_age > Tstar ?
     merge(r, (exit_age=Tstar, status=0)) : r for r in records]
end
# submuestra hasta acumular `nf` fallas (para la convergencia)
function take_until_failures(records, nf)
    out = empty(records); f = 0
    for r in records
        push!(out, r); (r.status > 0 && (f += 1)); f >= nf && break
    end
    return out
end

# =================================================================================================
# (1) POSTERIOR DE PARÁMETROS vs VERDAD — por componente
# =================================================================================================
println("\n[1/5] Posterior de parámetros…")
comps_main = ["brake_pad", "dpf", "scr", "battery", "egr", "air_system"]
fits = Dict{String,Any}()
for comp in comps_main
    nfail = count(r -> r.status > 0, rtf(comp))
    nfail < 30 && (println("  (omito $comp: solo $nfail fallas en el horizonte)"); continue)
    bf = fit_bayes(rtf(comp); n_samples=400, n_chains=3, rng=MersenneTwister(7))  # jerárquico (default)
    fits[comp] = bf
    d = posterior_draws(bf); tc = tru(comp)
    pβ = density(d.β, lw=2, fill=(0,0.15), label="posterior β",
                 title="$comp — posterior de β", xlabel="β (forma Weibull)")
    vline!(pβ, [tc.beta], lw=2, ls=:dash, color=:red, label="verdad β=$(tc.beta)")
    pγ = density(d.γ, lw=2, fill=(0,0.15), color=:purple, label="posterior γ",
                 title="$comp — posterior de γ (=−κ)", xlabel="γ (pendiente AFT)")
    vline!(pγ, [tc.gamma], lw=2, ls=:dash, color=:red, label="verdad γ=$(round(tc.gamma,digits=2))")
    pσ = density(d.σ_v, lw=2, fill=(0,0.15), color=:darkgreen, label="posterior σ_v",
                 title="$comp — σ_v (frailty residual por vehículo)", xlabel="σ_v")
    vline!(pσ, [0.0], lw=2, ls=:dash, color=:red, label="σ_v=0 (sin frailty)")
    savefig(plot(pβ, pγ, pσ, layout=(1,3), size=(1350,380)), joinpath(FIG, "1_post_params_$comp.png"))
end
println("  → figures/1_post_params_*.png (jerárquico: β, γ, σ_v) para: ", join(sort(collect(keys(fits))), ", "))

# =================================================================================================
# (2) ESTIMACIÓN DE LA DISTRIBUCIÓN A 3 NIVELES (componente | vehículo | flota) — por componente
# =================================================================================================
println("\n[2/5] Distribución a 3 niveles por componente…")
for comp in comps_main
    haskey(fits, comp) || continue
    bf = fits[comp]; tc = tru(comp)
    obs = [r.exit_age for r in rtf(comp) if r.status > 0]
    zf  = [r.route_severity for r in rtf(comp)]
    zmean = mean(zf); η0m = posterior_table(bf).η0.mean
    grid = range(0, stop=quantile(obs, 0.99) * 1.1, length=300)
    # NIVEL COMPONENTE: predictiva a z̄ vs observado vs verdad
    pC = histogram(obs, normalize=:pdf, alpha=0.35, color=:gray, label="vidas obs (fallas)",
                   title="$comp — COMPONENTE", xlabel="vida (h-motor)")
    density!(pC, predict_lifetimes(bf, zmean; n=6000), lw=3, color=:blue, label="predictiva (Bayes)")
    plot!(pC, grid, t->pdf(Weibull(tc.beta, η0m * exp(tc.gamma * zmean)), t),
          lw=2, ls=:dash, color=:red, label="Weibull verdad")
    # NIVEL VEHÍCULO: corrimiento AFT por severidad de ruta (η_v = η0·e^{γz})
    zlo, zhi = quantile(zf, [0.1, 0.9])
    pV = density(predict_lifetimes(bf, zlo; n=6000), lw=3, color=:green, fill=(0,0.12),
                 label=@sprintf("z=%.2f (ruta suave)", zlo), title="$comp — VEHÍCULO", xlabel="vida (h-motor)")
    density!(pV, predict_lifetimes(bf, zhi; n=6000), lw=3, color=:orange, fill=(0,0.12),
             label=@sprintf("z=%.2f (ruta severa)", zhi))
    # NIVEL FLOTA: mezcla marginal sobre la población de rutas vs histograma de flota
    mix = reduce(vcat, [predict_lifetimes(bf, z; n=120) for z in zf[1:min(end,400)]])
    pF = histogram(obs, normalize=:pdf, alpha=0.35, color=:gray, label="vidas flota (obs)",
                   title="$comp — FLOTA (marginal)", xlabel="vida (h-motor)")
    density!(pF, mix, lw=3, color=:navy, label="predictiva marginal (Bayes)")
    savefig(plot(pC, pV, pF, layout=(1,3), size=(1550,400)), joinpath(FIG, "2_dist_$comp.png"))
end
println("  → figures/2_dist_*.png (componente | vehículo | flota) para: ", join(sort(collect(keys(fits))), ", "))

# =================================================================================================
# (3) CONVERGENCIA: el posterior se estrecha al acumular datos
# =================================================================================================
println("\n[3/5] Convergencia…")
comp = "brake_pad"; bf = fits[comp]; tc = tru(comp)   # secciones 3-5 usan brake_pad como ejemplar
Ns = [20, 40, 80, 160, 320]
pConv = plot(title="CONVERGENCIA — $comp: posterior de β al acumular fallas",
             xlabel="β", ylabel="densidad")
widths = Float64[]
for (k, nf) in enumerate(Ns)
    sub = take_until_failures(rtf(comp), nf)
    # convergencia: el modelo AFT rápido (3 params) basta — el escalado del IC ∝1/√N es model-agnóstico
    bfk = fit_bayes(sub; n_samples=400, n_chains=2, rng=MersenneTwister(11), vehicle_effect=false)
    dk = posterior_draws(bfk); pt = posterior_table(bfk)
    push!(widths, pt.β.hi - pt.β.lo)
    density!(pConv, dk.β, lw=2, alpha=0.8, label="N=$nf fallas")
end
vline!(pConv, [tc.beta], lw=2, ls=:dash, color=:red, label="verdad")
pW = plot(Ns, widths, marker=:circle, lw=2, label="ancho IC95% de β", xscale=:log10,
          title="$comp — el IC se estrecha ∝ 1/√N", xlabel="N fallas (log)", ylabel="ancho IC95%")
plot!(pW, Ns, widths[1] .* sqrt.(Ns[1] ./ Ns), ls=:dash, color=:gray, label="referencia 1/√N")
savefig(plot(pConv, pW, layout=(1,2), size=(1150,440)), joinpath(FIG, "3_convergencia.png"))
println("  → figures/3_convergencia.png")

# =================================================================================================
# (4) SOLO-FALLAS (run-to-failure) → FALLAS + PREVENTIVO
# =================================================================================================
println("\n[4/5] Fallas-solo vs fallas+preventivo…")
# T* óptimo (de la verdad) para censurar el mundo preventivo
ηrep = posterior_table(bf).η0.mean
Tstar, _ = MaintenanceSim.Decision.optimal_age(tc.beta, ηrep, tc.cp, tc.cf)
prev_recs = censor_at(rtf(comp), Tstar)
bf_prev = fit_bayes(prev_recs; n_samples=500, n_chains=3, rng=MersenneTwister(7))
nf_rtf = count(r->r.status>0, rtf(comp)); nf_prev = count(r->r.status>0, prev_recs)
dβ_rtf = posterior_draws(bf).β; dβ_prev = posterior_draws(bf_prev).β
pP = density(dβ_rtf, lw=3, color=:gray, fill=(0,0.12),
             label="solo-fallas (RTF, $(nf_rtf) fallas)",
             title="$comp — recuperación de β: RTF vs régimen PREVENTIVO\n(preventivo censura las vidas largas en T*=$(round(Int,Tstar)) h)",
             xlabel="β")
density!(pP, dβ_prev, lw=3, color=:teal, fill=(0,0.12),
         label="fallas+preventivo ($(nf_prev) fallas, resto censurado)")
vline!(pP, [tc.beta], lw=2, ls=:dash, color=:red, label="verdad β=$(tc.beta)")
savefig(pP, joinpath(FIG, "4_fallas_vs_preventivo.png"))
println("  → figures/4_fallas_vs_preventivo.png  (RTF $nf_rtf fallas → preventivo $nf_prev fallas)")

# =================================================================================================
# (5) ECUACIÓN MAESTRA: tasa de falla y distribución de edades de la flota → estado estacionario
# =================================================================================================
println("\n[5/5] Ecuación maestra (renovación de la flota)…")
# días de falla por posición (renovaciones a lo largo del horizonte)
function failure_days(pl)
    di=0; D0=pl.Dcum[1]; a0=pl.a0_D; ti=1; fds=Int[]
    while ti <= length(pl.thresholds)
        Θ=pl.thresholds[ti]; fday=nothing
        for d in di:pl.ndays
            (pl.Dcum[d+1]-D0+a0 >= Θ) && (fday=d; break)
        end
        fday===nothing && break
        push!(fds, fday); (!pl.recurrent) && break
        di=fday; D0=pl.Dcum[fday+1]; a0=0.0; ti+=1
    end
    fds
end
comp_pls = [pl for pl in lives if pl.component == comp]
binw = 30
nb = H ÷ binw
rate = zeros(nb)
for pl in comp_pls, fd in failure_days(pl)
    b = min(fd ÷ binw + 1, nb); rate[b] += 1
end
rate ./= (length(comp_pls) * binw / 30)        # fallas por unidad por mes
zbar  = mean(r.route_severity for r in rtf(comp))                       # severidad media de la flota
ηref  = mean(v for (k, v) in truth.eta0 if last(k) == comp)             # η_ref verdad del componente
μ = mean(Weibull(tc.beta, ηref * exp(tc.gamma * zbar)))   # MTTF a la severidad media de la flota
months = (1:nb) .* (binw/30)
pM = plot(months, rate, lw=2, marker=:circle, ms=2, label="tasa de falla de la flota",
          title="ECUACIÓN MAESTRA — $comp: renovación de la flota → estado estacionario",
          xlabel="mes", ylabel="fallas / unidad·mes")
# estado estacionario de renovación: tasa → 1/MTTF (en las mismas unidades de tiempo)
hpm = sum(sum(@view vl.eng_h_day[1:vl.ndays]) for vl in vehlives) /
      sum(vl.ndays for vl in vehlives) * 30          # horas-motor/mes reales (incl. días sin operar)
ss = hpm / μ
hline!(pM, [ss], lw=2, ls=:dash, color=:red, label=@sprintf("estado estacionario 1/MTTF≈%.2f", ss))
savefig(pM, joinpath(FIG, "5_ecuacion_maestra_tasa.png"))

# distribución de edades de la flota en distintos tiempos → equilibrio S(a)/MTTF
function ages_at(pls, day)
    ages = Float64[]
    for pl in pls
        fds = failure_days(pl); last0 = 0
        for fd in fds; fd < day ? (last0 = fd) : break; end
        push!(ages, (day - last0))               # días desde la última renovación
    end
    ages
end
pA = plot(title="$comp — distribución de EDADES de la flota → equilibrio",
          xlabel="edad desde última renovación (días)", ylabel="densidad")
for (day,lab,col) in [(90,"mes 3",:lightblue),(360,"año 1",:dodgerblue),(H-30,"estacionario",:navy)]
    density!(pA, ages_at(comp_pls, day), lw=2, color=col, label=lab)
end
savefig(pA, joinpath(FIG, "5_ecuacion_maestra_edades.png"))
println("  → figures/5_ecuacion_maestra_{tasa,edades}.png")

println("\n✓ Reporte de figuras generado en figures/  ($(length(readdir(FIG))) PNG)")
