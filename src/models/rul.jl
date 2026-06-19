"""
    RUL — Remaining Useful Life condicional (forma cerrada verificada).

Para una vida ~ Weibull(β, η), la vida remanente esperada dado que la instancia tiene edad `t`
(sobrevivió hasta `t`) es:

    E[T − t | T > t] = E[T | T > t] − t,   con   E[T | T > t] = η·e^{w}·Γ(1+1/β)·Q(1+1/β, w)

donde w = (t/η)^β y Q(a,x) = Γ(a,x)/Γ(a) es la gamma incompleta superior **regularizada**
(`gamma_inc(a,x)[2]` en SpecialFunctions). Esta es la corrección que la auditoría señaló
(superior, no inferior) — ver Fundamentos IV.2.

`rul` consume el η_i condicional al vehículo (η0 del grupo · exp(γ·x)), de modo que la RUL es
específica de la unidad y su severidad de ruta.
"""
module RUL

using SpecialFunctions: gamma, gamma_inc

export rul, mean_residual_life, conditional_eta

"η condicional a la unidad: η0 del grupo escalado por el efecto AFT de la severidad de ruta."
conditional_eta(eta0_group::Float64, gamma_aft::Float64, x::Float64) = eta0_group * exp(gamma_aft * x)

"""
    mean_residual_life(t, beta, eta) -> E[T − t | T > t]

Vida remanente esperada para Weibull(beta, eta) dada la edad `t` (≥0). Forma cerrada.
"""
function mean_residual_life(t::Real, beta::Real, eta::Real)
    t <= 0 && return eta * gamma(1 + 1 / beta)        # MTTF si aún no hay uso
    w = (t / eta)^beta
    # Para piezas muy viejas (w grande) exp(w) desborda mientras Q→0 (Inf·0=NaN). Se usa la
    # asíntota de la vida media residual: MRL(t) → 1/h(t) = η^β/(β·t^(β-1)) (cola IFR/Weibull).
    w > 100 && return eta^beta / (beta * t^(beta - 1))
    Q = gamma_inc(1 + 1 / beta, w)[2]                 # gamma incompleta superior regularizada
    ET = eta * exp(w) * gamma(1 + 1 / beta) * Q       # E[T | T>t]
    return max(ET - t, 0.0)
end

"Alias semántico: RUL de una instancia con edad `t` bajo Weibull(beta, eta_i)."
rul(t::Real, beta::Real, eta_i::Real) = mean_residual_life(t, beta, eta_i)

end # module
