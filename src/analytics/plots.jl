"""
    AnalyticsPlots

Capa de rendering PNG (OFFLINE — usa StatsPlots) que consume los datos JSON-ready de
`MaintenanceSim.Analytics` y produce figuras. Separada del paquete para no meter Plots en el core.

Uso:
    include("src/MaintenanceSim.jl");        using .MaintenanceSim
    include("src/analytics/plots.jl");       using .AnalyticsPlots
    de = MaintenanceSim.Analytics.distribution_estimate(draws, recs; vehicle_z=…, Tstar=…)
    plot_distribution(de; path="figures/dist.png")
"""
module AnalyticsPlots

using StatsPlots, Printf
export plot_distribution, plot_parameters, plot_master, plot_economics

_save(p, path) = (path !== nothing && savefig(p, path); p)

"Panel componente | vehículo | flota desde `distribution_estimate`."
function plot_distribution(de; path=nothing)
    g = de.grid
    pC = plot(g, de.component_pdf, lw=3, color=:blue, label="estimada (predictiva)",
              title="$(de.component) — COMPONENTE", xlabel="vida", ylabel="densidad")
    de.n_obs > 0 && plot!(pC, g, de.observed_density, lw=2, color=:gray, ls=:dot, label="observada (real)")
    isinf(de.Tstar) || plot!(pC, g, de.preventive_pdf, lw=2, color=:seagreen, fill=(0,0.15),
                             label=@sprintf("bajo preventivo (T*=%.0f, masa %.0f%%)", de.Tstar, 100de.preventive_mass_at_Tstar))
    vline!(pC, [de.mttf], lw=2, ls=:dash, color=:black, label=@sprintf("estable MTTF=%.0f", de.mttf))
    pV = de.vehicle_pdf === nothing ? plot(title="(sin vehículo)") :
         plot(g, de.vehicle_pdf, lw=3, color=:orange, fill=(0,0.12), label="vehículo (su ruta z)",
              title="$(de.component) — VEHÍCULO", xlabel="vida")
    pF = plot(g, de.fleet_pdf, lw=3, color=:navy, label="marginal de flota",
              title="$(de.component) — FLOTA", xlabel="vida")
    _save(plot(pC, pV, pF, layout=(1,3), size=(1550,400), legendfontsize=7), path)
end

"Posteriores/IC de β, η0, γ desde `parameter_summary`."
function plot_parameters(ps; path=nothing)
    pan(s, name) = (p = plot(s.grid, s.density, lw=2, fill=(0,0.15), legend=false,
                             title=@sprintf("%s — %s: %.3g [%.3g, %.3g]", ps.component, name, s.mean, s.lo, s.hi),
                             xlabel=name);
                    vline!(p, [s.mean], lw=2, ls=:dash, color=:red); p)
    _save(plot(pan(ps.β, "β"), pan(ps.η0, "η0"), pan(ps.γ, "γ"), layout=(1,3), size=(1350,360)), path)
end

"Ecuación maestra: tasa → estable + edades, desde `master_equation`."
function plot_master(me; path=nothing)
    pR = plot(me.months, me.rate, lw=2, marker=:circle, ms=2, label="tasa de falla (flota)",
              title="$(me.component) — ecuación maestra (tasa → estable)", xlabel="mes", ylabel="fallas/u·mes")
    me.stabilization_day !== nothing && vline!(pR, [me.stabilization_day/30], lw=2, ls=:dash, color=:red,
        label=@sprintf("estabiliza ≈ mes %.0f", me.stabilization_day/30))
    pA = plot(title="$(me.component) — distribución de edades → equilibrio", xlabel="edad (días)", ylabel="densidad")
    for day in me.age_snapshots; density!(pA, me.ages[day], lw=2, label="día $day"); end
    _save(plot(pR, pA, layout=(1,2), size=(1150,420)), path)
end

"Estabilización + ahorro (acumulado y por componente) desde `economics_summary`."
function plot_economics(es; path=nothing)
    pE = plot(es.months, es.cum_reactive ./ 1e6, lw=3, color=:red, label="REACTIVO (VPN)",
              title="ahorro — reactivo vs predictivo", xlabel="mes", ylabel="MXN (millones)")
    plot!(pE, es.months, es.cum_preventive ./ 1e6, lw=3, color=:green, label="PREDICTIVO (+programa)")
    es.breakeven_day !== nothing && vline!(pE, [es.breakeven_day/30], lw=2, ls=:dash, color=:blue,
        label=@sprintf("break-even ≈ mes %.0f", es.breakeven_day/30))
    ord = sort(collect(keys(es.savings_by_component)), by=c->es.savings_by_component[c], rev=true)
    vals = [es.savings_by_component[c]/1e3 for c in ord]
    pB = bar(ord, vals, color=:seagreen, legend=false, xrotation=40,
             title="ahorro por componente (k MXN/u·año)", ylabel="k MXN/u·año", ylims=(0, maximum(vals)*1.12))
    _save(plot(pE, pB, layout=(1,2), size=(1300,460)), path)
end

end # module AnalyticsPlots
