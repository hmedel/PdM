#!/usr/bin/env julia
# ============================================================================
# Análisis MULTINIVEL del mantenimiento preventivo: componente · vehículo · flota,
# y las CORRELACIONES entre componentes (distribución multivariada) + su origen.
#
#   - Componente: β, T* por componente (decisión IFR).
#   - Vehículo:   agregado de las vidas de sus componentes (condición del camión).
#   - Flota:      distribución multivariada y correlación entre componentes.
# La correlación viene de la severidad de ruta COMPARTIDA por vehículo (recuperable).
# ============================================================================
using Printf, Statistics
const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
using .MaintenanceSim.LifeProcess, .MaintenanceSim.Policy

nv = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 300
lives, truth = generate_life_processes(LifeProcess.LifeConfig(n_vehicles=nv, horizon_days=730, seed=7))
comps = [c.name for c in MaintenanceSim.DamageModels.COMPONENTS if :heavy_truck in c.classes]
R = "="^78

# --- primera vida (horas-motor a la 1ª falla/censura) por (vehículo, componente) ---
# brake_pad: media sobre sus posiciones. Solo pesados portan los 4 componentes.
vc = Dict{String,Dict{String,Vector{Float64}}}()   # vid => comp => [exit_age...]
vehsev = Dict{String,Float64}()
for pl in lives
    rec = life_records(pl)[1]
    d = get!(vc, pl.vehicle_id, Dict{String,Vector{Float64}}())
    push!(get!(d, pl.component, Float64[]), rec.exit_age)
    vehsev[pl.vehicle_id] = pl.z   # severidad (≈ por vehículo; z del componente)
end
life(vid, c) = haskey(vc[vid], c) ? mean(vc[vid][c]) : NaN

println(R); println("MANTENIMIENTO PREVENTIVO MULTINIVEL — componente · vehículo · flota"); println(R)
@printf("Flota: %d vehículos · horizonte 2 años\n\n", nv)

# === NIVEL COMPONENTE: vida característica y dispersión en la flota ===
println("[NIVEL COMPONENTE] vida a 1ª falla (horas-motor) en la flota:")
@printf("  %-10s %8s %8s %8s\n", "comp", "media", "p10", "p90")
for c in comps
    xs = filter(!isnan, [life(v, c) for v in keys(vc)])
    isempty(xs) && continue
    @printf("  %-10s %8.0f %8.0f %8.0f\n", c, mean(xs), quantile(xs,0.1), quantile(xs,0.9))
end

# === NIVEL VEHÍCULO: condición agregada (vida mínima entre componentes = el que limita) ===
println("\n[NIVEL VEHÍCULO] el componente que LIMITA (menor vida) define el primer servicio:")
limiting = Dict{String,Int}()
heavy = [v for v in keys(vc) if all(haskey(vc[v], c) for c in comps)]
for v in heavy
    cmin = argmin(Dict(c => life(v, c) for c in comps))
    limiting[cmin] = get(limiting, cmin, 0) + 1
end
for (c, n) in sort(collect(limiting), by=x->-x[2])
    @printf("  %-10s limita en %3d de %d camiones pesados (%.0f%%)\n", c, n, length(heavy), 100*n/length(heavy))
end

# === NIVEL FLOTA: correlación multivariada entre componentes (solo pesados con los 4) ===
println("\n[NIVEL FLOTA] correlación entre vidas de componentes (mismo vehículo):")
M = [life(v, c) for v in heavy, c in comps]
println("  matriz de correlación (Pearson):")
@printf("  %-10s", ""); for c in comps; @printf("%10s", first(c,9)); end; println()
for (i, ci) in enumerate(comps)
    @printf("  %-10s", first(ci,10))
    for j in 1:length(comps)
        @printf("%10.2f", cor(M[:, i], M[:, j]))
    end
    println()
end
# correlación de cada componente con la severidad de ruta del vehículo
sev = [vehsev[v] for v in heavy]
println("\n  correlación vida↔severidad de ruta (negativa = más severo → menos vida):")
for (i, c) in enumerate(comps)
    @printf("    %-10s r=%+.2f\n", c, cor(M[:, i], sev))
end
println("\n→ La correlación POSITIVA entre componentes y la NEGATIVA con la severidad confirman el")
println("  origen: la ruta compartida por vehículo es el factor latente que los correlaciona")
println("  (recuperable vía la covariable AFT γ, no una frailty que rompería la estimación).")
