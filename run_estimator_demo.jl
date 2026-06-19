#!/usr/bin/env julia
# ============================================================================
# run_estimator_demo.jl — Demo del ESTIMADOR en su forma BATCH de servidor (lo que montará la API).
#
# Camino real del server: leer la BD → estimate_fleet(historial, unidades, costos) → escribir.
#   - historial (ServiceRecord[]) por componente  → ajusta UN modelo por tipo (caro, 1×).
#   - unidades vivas (LiveUnit[])                  → evalúa cada una (barato) reusando el modelo.
# Aquí los datos vienen del SIMULADOR (calar); en producción vienen de la BD, contrato idéntico.
#
# Uso:  julia --project=. run_estimator_demo.jl [n_unidades_por_componente]
# ============================================================================
using Printf, Random, Statistics
const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
using .MaintenanceSim.Estimator

NPER = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 200
R = "="^86
println(R); println("ESTIMADOR DE MANTENIMIENTO PREVENTIVO — API batch de servidor (estimate_fleet)"); println(R)

# --- 1) HISTORIAL (de la BD; aquí del simulador) -------------------------------------------------
lives, truth, _ = MaintenanceSim.LifeProcess.generate_life_processes(
    MaintenanceSim.LifeProcess.LifeConfig(n_vehicles=60, horizon_days=1095, seed=7))
history = reduce(vcat, [MaintenanceSim.Policy.life_records(pl) for pl in lives])
costs = Dict(c.name => (cp=truth.comp[c.name].cp, cf=truth.comp[c.name].cf)
             for c in MaintenanceSim.DamageModels.COMPONENTS)

# --- 2) FLOTA de unidades vivas (en prod: SELECT ... FROM unidades) -------------------------------
PI = MaintenanceSim.Precursors.PRECURSOR_INFO
rng = MersenneTwister(42)
units = Estimator.LiveUnit[]
for c in MaintenanceSim.DamageModels.COMPONENTS
    for _ in 1:NPER
        agefrac = rand(rng)                                  # 0..1 de la vida característica
        age = agefrac * c.eta_ref
        z = clamp(0.5 + 0.3 * randn(rng), 0.0, 1.0)
        reading = haskey(PI, c.name) ?
                  PI[c.name].new_val + agefrac * (PI[c.name].fail_val - PI[c.name].new_val) : nothing
        push!(units, Estimator.LiveUnit(c.name, :heavy_truck, "Kenworth", z, age, reading))
    end
end

# --- 3) BATCH: ajusta 1 modelo por componente (CARO, 1×), evalúa TODAS las unidades (BARATO) -------
estimate_fleet(history[1:100], units[1:5], costs; nboot=5)        # warm-up (JIT) para medir limpio
byc = Dict{String,Vector{eltype(history)}}()
for r in history; push!(get!(byc, r.component_type, eltype(history)[]), r); end
# (a) AJUSTE: una vez por tipo de componente
t_fit = @elapsed models = Dict(c => fit_component(byc[c]; cp=costs[c].cp, cf=costs[c].cf,
                                                  nboot=50, rng=MersenneTwister(1))
                               for c in keys(byc) if haskey(costs, c))
# (b) EVALUACIÓN: por unidad (reusa el modelo) — esto es lo que escala a miles
t_eval = @elapsed ests = [estimate(models[u.component_type], u) for u in units if haskey(models, u.component_type)]
ncomp = length(models)
@printf("\nFlota: %d unidades · %d tipos de componente · %d registros de historial\n",
        length(units), ncomp, length(history))
@printf("AJUSTE  (1× por componente): %2d modelos en %.2f s  (%.0f ms/modelo)\n",
        ncomp, t_fit, 1e3 * t_fit / ncomp)
@printf("EVALUAR (por unidad)       : %d unidades en %.4f s  (%.1f µs/unidad)  ← escala a toda la BD\n\n",
        length(ests), t_eval, 1e6 * t_eval / length(ests))

# --- 4) Resumen por componente (lo que la API escribiría a la BD) ---------------------------------
@printf("%-12s %5s %6s %7s %8s %9s  %s\n","componente","n","β̂","RUL h","%prevent","%CBM-alarm","modo")
for c in MaintenanceSim.DamageModels.COMPONENTS
    g = [e for e in ests if e.component_type == c.name]
    isempty(g) && continue
    pct_prev = 100 * count(e -> e.recommend_preventive, g) / length(g)
    pct_cbm  = 100 * count(e -> e.cbm_alarm, g) / length(g)
    @printf("%-12s %5d %6.2f %7.0f %7.0f%% %8.0f%%  %s\n",
            c.name, length(g), g[1].beta, median(e.rul for e in g), pct_prev, pct_cbm,
            haskey(PI, c.name) ? "CBM+T*" : "estadístico (T*)")
end

println("\n", R)
println("El server ajusta N modelos UNA vez y evalúa miles de unidades; T* se reescala por η de cada")
println("unidad (exacto en Weibull). battery/wheel_end rehúsan preventivo por IFR; tire/wheel_end sin CBM.")
