"""
    BayesEstimator

Motor **bayesiano jerárquico** de la vida Weibull-AFT (complementa al frecuentista `Survival`).
Da **posteriores reales** de (β, η0, γ, σ_v) con **partial pooling** vehículo→flota: todos los
vehículos informan los parámetros de flota (β, η0, γ); cada vehículo tiene su escala η_v = η0·e^{γ z_v}
más un efecto aleatorio residual b_v ~ N(0, σ_v) (frailty). Si la heterogeneidad la explica la ruta
(la covariable z), el dato empuja σ_v→0: eso ES un resultado (la correlación viene de la ruta, no de
frailty; ver docs).

Es SEPARADO del paquete de producción (Turing es pesado; MCMC por componente cuesta s–min). Se usa para
análisis/calibración y para las visualizaciones de la distribución y la convergencia.

Modelo (vida en la escala de uso — horas-motor o km):
  β     ~ truncated(Normal(2,1), 0.2, 12)            # forma (componente)
  logη0 ~ Normal(log(mean t), 1.5)                   # escala base de flota
  γ     ~ Normal(0, 1)                               # pendiente AFT (verdad = −κ)
  σ_v   ~ HalfNormal(0.15)                           # dispersión residual entre vehículos
  b_v   ~ Normal(0, 1)  (no-centrado)                # efecto por vehículo
  η_i = η0 · exp(γ z_i + σ_v b_{v(i)})
  vida ~ Weibull(β, η_i)  con censura derecha + truncamiento izquierdo en a_i
"""
module BayesEstimator

using Turing, Distributions, Statistics, Random, LinearAlgebra
using MCMCChains: Chains, namesingroup
import MCMCChains

export fit_bayes, BayesFit, posterior_table, posterior_draws, predict_lifetimes

# Verosimilitud Weibull-AFT jerárquica (forma cerrada, AD-friendly).
@model function _weibull_aft_hier(t, a, d, z, vidx, nveh, mt)
    β     ~ truncated(Normal(2.0, 2.0); lower=0.2, upper=12.0)   # prior ancho/neutro
    logη0 ~ Normal(log(mt), 2.0)
    γ     ~ Normal(0.0, 2.0)
    σ_v   ~ truncated(Normal(0.0, 0.30); lower=0.0)              # half-normal neutro (el dato lo encoge)
    b     ~ filldist(Normal(0.0, 1.0), nveh)                     # efectos por vehículo (no-centrado)
    η0 = exp(logη0)
    lp = zero(eltype(b))
    @inbounds for i in eachindex(t)
        ηi  = η0 * exp(γ * z[i] + σ_v * b[vidx[i]])
        xt  = t[i] / ηi
        lSt = -xt^β                                        # log S(t) = -(t/η)^β
        lSa = a[i] > 0 ? -(a[i] / ηi)^β : zero(eltype(b))  # truncamiento: -log S(a)
        lp += (d[i] == 1 ?
               (log(β) - log(ηi) + (β - 1) * log(xt) + lSt) :  # log f(t)
               lSt) - lSa
    end
    Turing.@addlogprob! lp
end

# Variante SIN efecto aleatorio por vehículo (3 params): la heterogeneidad la captura la covariable z
# (η_v = η0·e^{γ z_v}). Rápida; es el default del reporte. La jerárquica (con b_v) se usa para mostrar
# que σ_v→0 (la correlación viene de la ruta, no de frailty).
@model function _weibull_aft(t, a, d, z, mt)
    β     ~ truncated(Normal(2.0, 2.0); lower=0.2, upper=12.0)   # prior ancho/neutro
    logη0 ~ Normal(log(mt), 2.0)
    γ     ~ Normal(0.0, 2.0)
    η0 = exp(logη0)
    lp = zero(typeof(β))
    @inbounds for i in eachindex(t)
        ηi  = η0 * exp(γ * z[i])
        xt  = t[i] / ηi
        lSt = -xt^β
        lSa = a[i] > 0 ? -(a[i] / ηi)^β : zero(typeof(β))
        lp += (d[i] == 1 ? (log(β) - log(ηi) + (β - 1) * log(xt) + lSt) : lSt) - lSa
    end
    Turing.@addlogprob! lp
end

# Init data-driven por momentos (sobre las fallas): β de la varianza de log-vida (Var log T=π²/6β²),
# γ por OLS de log(t)~z, log η0 del intercepto + corrección de Euler (E[log T]=log η − γ_E/β). Centra
# las cadenas en la verdad SIN sesgo de un valor fijo y SIN caer en el modo espurio (γ con signo errado).
function _moment_init(t, a, d, z)
    idx = d .== 1
    sum(idx) < 3 && return (2.0, log(mean(t)), 0.0)
    tf = log.(t[idx]); zf = z[idx]
    β0 = clamp(pi / (sqrt(6) * max(std(tf), 1e-3)), 0.5, 6.0)
    z̄ = mean(zf); lt̄ = mean(tf); sz = sum((zf .- z̄) .^ 2)
    γ0 = sz > 1e-6 ? clamp(sum((zf .- z̄) .* (tf .- lt̄)) / sz, -3.0, 3.0) : 0.0
    logη0 = (lt̄ - γ0 * z̄) + 0.5772156649 / β0
    return (β0, logη0, γ0)
end

"Resultado del ajuste bayesiano: cadena MCMC + metadatos para extraer posteriores."
struct BayesFit
    component::String
    chain                       # MCMCChains.Chains
    vehicle_ids::Vector
    z_by_vehicle::Vector{Float64}
    n::Int
    nfail::Int
end

"""
    fit_bayes(records; n_samples=1000, n_chains=4, rng, accept=0.8) -> BayesFit

Ajusta el modelo jerárquico a los registros de UN componente (campos: component_type, vehicle_id,
route_severity, entry_age, exit_age, status). Usa NUTS (HMC). `vehicle_id` agrupa el efecto aleatorio.
"""
function fit_bayes(records; n_samples::Int=1000, n_chains::Int=4,
                   rng::AbstractRNG=MersenneTwister(1), accept::Float64=0.8,
                   adtype=AutoForwardDiff(), vehicle_effect::Bool=true)
    isempty(records) && error("fit_bayes: sin registros")
    comp = first(records).component_type
    t = Float64[max(r.exit_age, 1e-6) for r in records]
    a = Float64[r.entry_age for r in records]
    d = Float64[r.status > 0 ? 1.0 : 0.0 for r in records]
    z = Float64[r.route_severity for r in records]
    vids = unique(r.vehicle_id for r in records)
    vmap = Dict(v => i for (i, v) in enumerate(vids))
    zbyv = zeros(Float64, length(vids))
    for r in records; zbyv[vmap[r.vehicle_id]] = r.route_severity; end

    model = if vehicle_effect
        _weibull_aft_hier(t, a, d, z, Int[vmap[r.vehicle_id] for r in records], length(vids), mean(t))
    else
        _weibull_aft(t, a, d, z, mean(t))
    end
    # Init data-driven (por momentos): centra las cadenas en la verdad sin sesgo de un valor fijo.
    β0, logη0_0, γ0 = _moment_init(t, a, d, z)
    init = vehicle_effect ?
        (β=β0, logη0=logη0_0, γ=γ0, σ_v=0.05, b=zeros(length(vids))) :
        (β=β0, logη0=logη0_0, γ=γ0)
    chain = sample(rng, model, NUTS(accept; adtype=adtype), MCMCThreads(), n_samples, n_chains;
                   progress=false, chain_type=Chains, initial_params=fill(init, n_chains))
    return BayesFit(comp, chain, collect(vids), zbyv, length(t), Int(sum(d)))
end

# --- extracción de posteriores ---------------------------------------------------------------------

"Vector de muestras del posterior para un parámetro escalar (concatena cadenas)."
_draws(bf::BayesFit, sym::Symbol) = vec(Array(bf.chain[sym]))

"""
    posterior_table(bf) -> NamedTuple

Resumen del posterior de los parámetros de flota: media, IC 95% y R̂ de β, η0 (=exp logη0), γ, σ_v.
"""
_has(bf::BayesFit, sym::Symbol) = sym in names(bf.chain)

function posterior_table(bf::BayesFit)
    β  = _draws(bf, :β);  γ = _draws(bf, :γ)
    η0 = exp.(_draws(bf, :logη0))
    q(x) = (mean=mean(x), lo=quantile(x, 0.025), hi=quantile(x, 0.975))
    σ = _has(bf, :σ_v) ? q(_draws(bf, :σ_v)) : nothing
    return (component=bf.component, n=bf.n, nfail=bf.nfail,
            β=q(β), η0=q(η0), γ=q(γ), σ_v=σ)
end

"Muestras crudas del posterior (β, η0, γ, [σ_v]) como columnas (para graficar densidades)."
function posterior_draws(bf::BayesFit)
    return (β=_draws(bf, :β), η0=exp.(_draws(bf, :logη0)), γ=_draws(bf, :γ),
            σ_v=_has(bf, :σ_v) ? _draws(bf, :σ_v) : Float64[])
end

"""
    predict_lifetimes(bf, z; n=4000, rng) -> Vector

Distribución PREDICTIVA posterior de la vida a severidad de ruta `z`: por cada muestra del posterior
(β, η0, γ) sortea una vida Weibull(β, η0·e^{γz}). Mezcla la incertidumbre de parámetros + la aleatoria.
"""
function predict_lifetimes(bf::BayesFit, z::Real; n::Int=4000, rng::AbstractRNG=MersenneTwister(2))
    β = _draws(bf, :β); η0 = exp.(_draws(bf, :logη0)); γ = _draws(bf, :γ)
    m = length(β); out = Vector{Float64}(undef, n)
    @inbounds for k in 1:n
        j = rand(rng, 1:m)
        out[k] = rand(rng, Weibull(β[j], η0[j] * exp(γ[j] * z)))
    end
    return out
end

end # module BayesEstimator
