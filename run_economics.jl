#!/usr/bin/env julia
# ============================================================================
# Estudio contrafactual ECONÓMICO (parte estadística retomada).
#
#   (1) Vida de la flota SIN preventivo (reactivo, run-to-failure) sobre rutas — línea base,
#       con fallas/servicios/condiciones. Se estiman (β,γ,η0) de esos datos.
#   (2) La MISMA flota (CRN) con preventivo (edad T* y predictivo RUL) — gate IFR.
#   (3) ¿Cómo y EN CUÁNTO TIEMPO se estabiliza la distribución? + break-even por ventana.
#
# Uso:  julia run_economics.jl [n_vehicles] [horizon_days] [seed]
# Salida: out/economics/{trajectories,monthly_failrate}.csv
# ============================================================================
using Printf, Statistics, Random
using DataFrames, CSV

const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
using .MaintenanceSim.LifeProcess, .MaintenanceSim.Precursors, .MaintenanceSim.Survival,
      .MaintenanceSim.RUL, .MaintenanceSim.Decision, .MaintenanceSim.Policy, .MaintenanceSim.Economics

nv = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 120
hd = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 2555      # 7 años para VER la estabilización
sd = length(ARGS) >= 3 ? parse(Int, ARGS[3]) : 20240617

R = "="^86
sec(t) = (println("\n", R); println(t); println(R))
money(x) = @sprintf("%s MXN", replace(@sprintf("%.0f", x), r"(?<=\d)(?=(\d{3})+$)" => ","))

sec("ESTUDIO CONTRAFACTUAL ECONÓMICO — sin preventivo vs con preventivo (CRN)")
@printf("Flota: %d vehículos · horizonte %d días (%.1f años) · descuento 12%%/año · semilla %d\n",
        nv, hd, hd/365, sd)

# --- sustrato físico (una vez; ambos brazos comparten umbrales Θ — CRN) ---
lives, truth = generate_life_processes(LifeProcess.LifeConfig(n_vehicles=nv, horizon_days=hd, seed=sd))
comps = unique([l.component for l in lives])

# (1) ESTIMACIÓN desde el mundo REACTIVO (sin preventivo)
sec("(1) LÍNEA BASE REACTIVA — estimar (β, γ, η0) de las fallas observadas (sin preventivo)")
all_recs = reduce(vcat, [life_records(pl) for pl in lives])
Tstar = Dict{String,Float64}(); fits = Dict{String,Any}()
@printf("%-10s %8s %14s %8s %9s  %-6s %9s\n", "comp", "β̂", "IC95(β)", "γ̂", "n/fall", "prev?", "T*(h)")
for comp in comps
    recs = filter(r -> r.component_type == comp, all_recs)
    fit = fit_grouped(recs; nboot=20, rng=MersenneTwister(7)); fits[comp] = fit
    eta_ref = mean(values(fit.eta0)); cp = truth.comp[comp].cp; cf = truth.comp[comp].cf
    # gate IFR + materialidad: preventivo solo si β>1 confirmado Y el ahorro es material
    dec = Decision.decide(comp, fit.beta, fit.beta_lo, eta_ref, cp, cf)
    Tstar[comp] = dec.preventive ? dec.Tstar : Inf
    @printf("%-10s %8.2f [%4.2f,%4.2f] %+8.2f %5d/%-4d  %-6s %9s\n",
            comp, fit.beta, fit.beta_lo, fit.beta_hi, fit.gamma, fit.n, fit.nfail,
            isinf(Tstar[comp]) ? "NO" : "sí", isinf(Tstar[comp]) ? "—" : @sprintf("%.0f", Tstar[comp]))
end
println("battery: IC95(β) incluye 1 → gate IFR rechaza preventivo (correcto).")

# políticas (la estimación de la línea base define T* y el gate)
pol_react = Reactive()
pol_age   = AgeReplace(Tstar)
# CBM atado al PRECURSOR FÍSICO real (módulo Precursors = fuente única degradación→señal): la
# alarma y el ruido salen del mapa físico (balata mm, ΔP DPF, derate SCR), no de números abstractos.
# La fracción de daño que dispara cada componente ES la misma que cruza Θ y causa la falla.
cbm_comps = [c for c in comps if haskey(Precursors.PRECURSOR_INFO, c)]   # con precursor on-board → CBM
alarm = Dict(c => Precursors.alarm_fraction(c) for c in cbm_comps)
scv   = Dict(c => Precursors.sensor_cv(c) for c in cbm_comps)
pol_pred  = PredictiveRUL(alarm, scv, 14, Tstar)   # comps sin precursor → AgeReplace (default en _trigger)
println("\n[CBM] alarma física por componente (precursor → fracción de daño de alarma f*):")
for c in cbm_comps
    @printf("   %-10s %-26s f*=%.2f (cv %.1f)\n", c, Precursors.precursor_units(c),
            Precursors.alarm_fraction(c), Precursors.sensor_cv(c))
end
isempty(setdiff(comps, cbm_comps)) ||
    println("   (estadísticos sin precursor on-board → preventivo por intervalo T*: ",
            join(setdiff(comps, cbm_comps), ", "), ")")

cfg = Economics.EconConfig()

# (2)+(3) economía: reactivo vs edad-T*, y reactivo vs predictivo
econ_age  = run_economics(lives, Policy.evaluate, pol_react, pol_age,  cfg; horizon_days=hd, n_vehicles=nv)
econ_pred = run_economics(lives, Policy.evaluate, pol_react, pol_pred, cfg; horizon_days=hd, n_vehicles=nv)

# CRN: MEDIR (no afirmar) la reducción de varianza de la diferencia entre brazos
crn = crn_variance_reduction(lives, Policy.evaluate, pol_react, pol_age, cfg.annual_discount)
@printf("\n[CRN] acoplamiento reactivo↔preventivo: correlación de costo/vehículo r=%.2f → reduce la\n", crn.correlation)
@printf("      varianza de la diferencia ~%.0f%% (medido sobre %d vehículos; acopla física por-vehículo).\n",
        100*crn.var_reduction, crn.n)

# (3a) ESTABILIZACIÓN de la distribución de fallas (mundo reactivo)
sec("(3) ¿EN CUÁNTO TIEMPO SE ESTABILIZA LA DISTRIBUCIÓN? (tasa de fallas/mes/unidad, reactivo)")
dp = econ_age.day_points; mf = econ_age.monthly_fail_reactive
mk(d) = findmin(abs.(dp .- d))[2]
for mo in (6, 12, 18, 24, 36, 48, 60, 84)
    d = mo * 30; d > hd && continue
    @printf("  mes %2d  (%.1f año):  %.3f fallas/mes/unidad\n", mo, mo/12, mf[mk(d)])
end
final_rate = mean(mf[max(1,length(mf)-11):end])
@printf("\nRégimen estacionario ≈ %.3f fallas/mes/unidad (promedio último año).\n", final_rate)
if econ_age.stabilization_day !== nothing
    sd_ = econ_age.stabilization_day
    @printf("La distribución se ESTABILIZA hacia el día %d (~%.1f años / %.0f meses).\n",
            sd_, sd_/365, sd_/30)
    @printf("  → %s\n", sd_ <= 730 ? "Dentro de la ventana productiva de 2 años." :
            "FUERA de los 2 años: la flota joven aún no alcanza su régimen de fallas — clave para el análisis.")
else
    println("No se estabiliza dentro del horizonte simulado (flota aún en transitorio).")
end

# (3b) BREAK-EVEN y ahorro por ventana de vida productiva
sec("(3) BREAK-EVEN y AHORRO NETO por ventana (VPN, descuento 12%/año)")
function report_arm(name, econ)
    be = econ.breakeven_day
    @printf("\n[%s]  break-even: %s\n", name,
            be === nothing ? "no se alcanza en el horizonte" :
            @sprintf("día %d (~%.1f años / %.0f meses)", be, be/365, be/30))
    @printf("  %-8s %14s %14s %12s\n", "ventana", "ahorro neto VPN", "veredicto", "")
    for W in (2, 3, 5, 7)
        d = W * 365; d > hd && continue
        i = findmin(abs.(econ.day_points .- d))[2]
        s = econ.cum_savings[i]
        verdict = s > 0 ? (be !== nothing && be <= d ? "✓ paga dentro de $(W)a" : "✓ positivo") : "✗ no paga aún"
        @printf("  %-8s %14s   %s\n", "$(W) años", money(s), verdict)
    end
end
report_arm("Preventivo por edad T*", econ_age)
report_arm("Predictivo (RUL condicional)", econ_pred)

# (3c) EUAC / vida económica del camión
sec("(3) VIDA ECONÓMICA DEL CAMIÓN (EUAC) — ¿la ventana productiva justifica el programa?")
# mantenimiento anual = ANUALIDAD EQUIVALENTE del flujo de mantenimiento (VPN × CRF), coherente con
# la recuperación de capital del EUAC (no VPN/años, que mezclaría descontado con promedio lineal).
let hy = hd/365, r = cfg.annual_discount
    global crf_h = r * (1 + r)^hy / ((1 + r)^hy - 1)
end
tot_react = (econ_age.cum_reactive[end] / nv) * crf_h
tot_prev  = (econ_age.cum_preventive[end] / nv) * crf_h
yrs, euac_r = Economics.euac_curve(tot_react, cfg)
_,   euac_p = Economics.euac_curve(tot_prev, cfg)
life_r = yrs[argmin(euac_r)]; life_p = yrs[argmin(euac_p)]
@printf("Mantenimiento anual/unidad:  reactivo ~%s · con preventivo ~%s\n", money(tot_react), money(tot_prev))
@printf("Vida económica (mín EUAC):   reactivo %d años · con preventivo %d años\n", life_r, life_p)
@printf("  → el preventivo %s la vida económica del camión.\n",
        life_p >= life_r ? "mantiene/extiende" : "no extiende")

# --- escribir trayectorias ---
outdir = joinpath(ROOT, "out", "economics"); mkpath(outdir)
CSV.write(joinpath(outdir, "trajectories.csv"), DataFrame(
    day=dp, year=round.(dp ./ 365, digits=3),
    cum_reactive=econ_age.cum_reactive, cum_prev_age=econ_age.cum_preventive,
    savings_age=econ_age.cum_savings, cum_prev_pred=econ_pred.cum_preventive,
    savings_pred=econ_pred.cum_savings))
CSV.write(joinpath(outdir, "monthly_failrate.csv"), DataFrame(
    day=dp, year=round.(dp ./ 365, digits=3),
    failrate_reactive=econ_age.monthly_fail_reactive,
    failrate_age=econ_age.monthly_fail_preventive,
    failrate_pred=econ_pred.monthly_fail_preventive))
println("\nTrayectorias → out/economics/{trajectories,monthly_failrate}.csv")
println("Sustento matemático: docs/Estudio_Convergencia_Economica.md")
