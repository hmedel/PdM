#!/usr/bin/env julia
# ============================================================================
# run_analytics_demo.jl — Demo de la API de Analytics (datos) + AnalyticsPlots (PNG opcional) + alertas.
# Muestra el flujo que el servicio de Tracker usaría: estimar → datos para gráficas → alertas.
#   julia --project=. run_analytics_demo.jl
# ============================================================================
ENV["GKSwstype"] = "100"
using Printf, Random, Statistics
const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl"));      using .MaintenanceSim
include(joinpath(ROOT, "src", "analytics", "plots.jl"));  using .AnalyticsPlots
using .MaintenanceSim.Analytics, .MaintenanceSim.Estimator
const FIG = joinpath(ROOT, "figures"); mkpath(FIG)

# datos del simulador (en producción: de la BD)
lives, truth, _ = MaintenanceSim.LifeProcess.generate_life_processes(
    MaintenanceSim.LifeProcess.LifeConfig(n_vehicles=40, horizon_days=1095, seed=7))
hist = reduce(vcat, [MaintenanceSim.Policy.life_records(pl) for pl in lives])
comp = "brake_pad"; recs = filter(r -> r.component_type == comp, hist)
costs = Dict(c.name => (cp=truth.comp[c.name].cp, cf=truth.comp[c.name].cf) for c in MaintenanceSim.DamageModels.COMPONENTS)

# 1) DATOS para gráficas (la API los devolvería en JSON)
fit = MaintenanceSim.Survival.fit_grouped(recs; nboot=30)
d   = Analytics.from_grouped(fit; n=400)
Tstar = MaintenanceSim.Decision.optimal_age(fit.beta, mean(values(fit.eta0)), costs[comp].cp, costs[comp].cf)[1]
de  = Analytics.distribution_estimate(d, recs; vehicle_z=0.85, Tstar=Tstar)
ps  = Analytics.parameter_summary(d)
me  = Analytics.master_equation(lives, comp; horizon=1095)
es  = Analytics.economics_summary(lives, truth; horizon=1095, n_vehicles=40)
@printf("DATOS: MTTF=%.0f h, estable mes≈%.0f, break-even mes≈%s, ahorro %.0f k/u·año\n",
        de.mttf, me.stabilization_day/30, string(round(Int, es.breakeven_day/30)), es.savings_per_unit_year/1e3)

# 2) PNG opcional (offline)
plot_distribution(de; path=joinpath(FIG, "demo_distribucion.png"))
plot_parameters(ps;  path=joinpath(FIG, "demo_parametros.png"))
plot_master(me;      path=joinpath(FIG, "demo_maestra.png"))
plot_economics(es;   path=joinpath(FIG, "demo_economia.png"))
println("PNG: figures/demo_{distribucion,parametros,maestra,economia}.png")

# 3) ALERTAS (la API las emitiría por componente/vehículo/flota)
m = Estimator.fit_component(recs; cp=costs[comp].cp, cf=costs[comp].cf, nboot=20)
ests_by_vehicle = Dict{String,Vector}()
ages_by_vehicle = Dict{String,Dict{String,Float64}}()
# 3 unidades de ejemplo: sana, desgaste avanzado (RUL bajo), y en alarma física (balata < 4 mm)
for (vid, age, balata) in [("V-SANO", 60.0, 15.0), ("V-DESGASTE", de.mttf*1.05, 5.0), ("V-ALARMA", de.mttf*0.9, 3.0)]
    unit = Estimator.LiveUnit(comp, :heavy_truck, "Kenworth", 0.6, age, balata)
    ests_by_vehicle[vid] = [Estimator.estimate(m, unit)]
    ages_by_vehicle[vid] = Dict(comp => age)
end
println("\nALERTAS por vehículo:")
for (vid, ests) in ests_by_vehicle
    va = Analytics.vehicle_alerts(vid, ests; current_ages=ages_by_vehicle[vid])
    isempty(va) || for a in va; @printf("  [%s] %-10s %-16s %s\n", uppercase(string(a.severity)), a.target, a.code, a.message); end
end
fa = Analytics.fleet_alerts(ests_by_vehicle, es)
println("\nALERTAS de flota:")
isempty(fa) ? println("  (ninguna)") : for a in fa; @printf("  [%s] %s — %s\n", uppercase(string(a.severity)), a.code, a.message); end
println("\n✓ Demo Analytics: datos + PNG + alertas (componente/vehículo/flota)")
