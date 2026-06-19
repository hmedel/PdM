"""
    Survival

Ajuste de supervivencia **Weibull-AFT** con censura por la derecha y truncamiento por la
izquierda — el estimador con el que el pipeline RECUPERA la verdad del generador.

Es una implementación **independiente** del modelo forward del simulador (anti-circularidad,
Brief §4): aquí no se muestrea nada; se maximiza la verosimilitud de la tripleta WS-A
`(entry_age, exit_age, status)`. La log-verosimilitud por instancia, para vida ~ Weibull(β, η_i)
con η_i = η0_g · exp(γ·x) (AFT), censura por la derecha y truncamiento por la izquierda en `a`:

    ℓ_i = d_i·[ log β − β·log η_i + (β−1)·log t_i ] − (t_i/η_i)^β + (a_i/η_i)^β

donde `d_i = 1[status>0]` (falla), `t_i = exit_age`, `a_i = entry_age`. El término `+(a/η)^β`
es la corrección de truncamiento (condicionar a haber sobrevivido hasta la edad de entrada).

Modelo **bien especificado** (`fit_grouped`): un η0 por grupo (clase,marca) + β,γ compartidos.
Recupera la verdad dentro de ±5–6% (validado en synth_pipeline_demo.py). El modelo de **un solo
η0** (`fit_pooled`) está mal especificado cuando η0 varía por grupo y sesga β,γ — esa es la
motivación empírica del modelo jerárquico (F4).
"""
module Survival

using Optim
using Statistics
using Random

export fit_grouped, fit_pooled, GroupedFit, group_index

"Resultado del ajuste agrupado, con IC bootstrap de β (prueba: ¿β>1 distinguible de 1?)."
struct GroupedFit
    component::String
    beta::Float64
    beta_lo::Float64
    beta_hi::Float64
    gamma::Float64
    eta0::Dict{Tuple{Symbol,String},Float64}   # (clase, marca) -> vida característica base
    groups::Vector{Tuple{Symbol,String}}
    n::Int
    nfail::Int
    converged::Bool
end

# --- verosimilitud agrupada: theta = [logβ, γ, logη0_1, …, logη0_G] ---
function _nll_grouped(theta, gi, x, t, d, a, G)
    b = exp(theta[1]); g = theta[2]
    ll = 0.0
    @inbounds for i in eachindex(t)
        eta = exp(theta[2 + gi[i]]) * exp(g * x[i])
        zt = (t[i] / eta)^b
        za = a[i] > 0 ? (a[i] / eta)^b : 0.0
        ll += d[i] * (log(b) - b * log(eta) + (b - 1) * log(t[i])) - zt + za
    end
    return -ll
end

# --- verosimilitud de un solo η0 (mal especificada si η0 varía por grupo) ---
function _nll_pooled(theta, x, t, d, a)
    b = exp(theta[1]); e0 = exp(theta[2]); g = theta[3]
    ll = 0.0
    @inbounds for i in eachindex(t)
        eta = e0 * exp(g * x[i])
        zt = (t[i] / eta)^b
        za = a[i] > 0 ? (a[i] / eta)^b : 0.0
        ll += d[i] * (log(b) - b * log(eta) + (b - 1) * log(t[i])) - zt + za
    end
    return -ll
end

"Índice de grupo (clase,marca) 1..G y catálogo ordenado, a partir de columnas paralelas."
function group_index(classes, brands)
    groups = sort(unique(collect(zip(classes, brands))))
    gid = Dict(g => i for (i, g) in enumerate(groups))
    gi = [gid[(classes[i], brands[i])] for i in eachindex(classes)]
    return gi, groups
end

"""
    fit_grouped(records; nboot=40, rng) -> GroupedFit

Ajusta el AFT bien especificado sobre los `SurvivalRecord` de un componente (η0 por grupo).
`records` es cualquier iterable de objetos con campos `class, brand, route_severity,
entry_age, exit_age, status`. IC de β por bootstrap no-paramétrico.
"""
function fit_grouped(records; nboot::Int=40, rng::AbstractRNG=MersenneTwister(1))
    isempty(records) && error("sin registros para ajustar")
    comp = first(records).component_type
    classes = [r.class for r in records]
    brands  = [r.brand for r in records]
    x = Float64[r.route_severity for r in records]
    t = Float64[r.exit_age for r in records]
    d = Float64[r.status > 0 ? 1.0 : 0.0 for r in records]
    a = Float64[r.entry_age for r in records]
    gi, groups = group_index(classes, brands)
    G = length(groups)

    # salvaguarda numérica: exit_age estrictamente > 0
    @inbounds for i in eachindex(t)
        t[i] = max(t[i], 1e-6)
    end

    x0 = vcat([log(2.0), 0.0], fill(log(mean(t)), G))
    obj(th) = _nll_grouped(th, gi, x, t, d, a, G)
    # NelderMead (sin gradiente): la verosimilitud es suave, pero `f_tol` —no `g_tol`— es el
    # criterio activo. Para producción con muchos grupos conviene LBFGS + gradiente analítico.
    res = optimize(obj, x0, NelderMead(), Optim.Options(f_reltol=1e-10, iterations=60_000))
    th = Optim.minimizer(res)
    b = exp(th[1]); g = th[2]
    etas = Dict(groups[i] => exp(th[2 + i]) for i in 1:G)

    # IC bootstrap de β. Se arranca cada réplica desde `x0` (no desde el óptimo full-sample) para
    # NO subestimar la varianza de β — y `beta_lo` gobierna la decisión IFR. Producción: nboot≥500.
    n = length(t); bs = Float64[]
    for _ in 1:nboot
        idx = rand(rng, 1:n, n)
        objb(th) = _nll_grouped(th, gi[idx], x[idx], t[idx], d[idx], a[idx], G)
        rb = optimize(objb, x0, NelderMead(), Optim.Options(iterations=40_000))
        push!(bs, exp(Optim.minimizer(rb)[1]))
    end
    blo, bhi = quantile(bs, 0.025), quantile(bs, 0.975)

    return GroupedFit(comp, b, blo, bhi, g, etas, groups, n, Int(sum(d)),
                      Optim.converged(res))
end

"""
    fit_pooled(records) -> (beta, eta0, gamma)

Ajuste de un solo η0 (mal especificado si η0 varía por grupo). Se usa SOLO para demostrar el
sesgo en β,γ frente a `fit_grouped` — motivación empírica del jerárquico (F4).
"""
function fit_pooled(records)
    x = Float64[r.route_severity for r in records]
    t = Float64[max(r.exit_age, 1e-6) for r in records]
    d = Float64[r.status > 0 ? 1.0 : 0.0 for r in records]
    a = Float64[r.entry_age for r in records]
    obj(th) = _nll_pooled(th, x, t, d, a)
    res = optimize(obj, [log(2.0), log(mean(t)), 0.0], NelderMead(),
                   Optim.Options(f_reltol=1e-10, iterations=60_000))
    th = Optim.minimizer(res)
    return (beta=exp(th[1]), eta0=exp(th[2]), gamma=th[3])
end

end # module
