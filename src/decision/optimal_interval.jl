"""
    Decision — intervalo óptimo de reemplazo por edad + calculadora de ahorro.

Teoría de renovación-recompensa (Barlow-Proschan; Jardine-Tsang). Para una política de
**reemplazo preventivo por edad** T sobre una vida ~ Weibull(β, η) con costo preventivo
programado `cp` y costo correctivo en falla `cf` (cf ≫ cp; la diferencia es el premium de la
falla **en ruta**: grúa + downtime + multa por derate), la tasa de costo de largo plazo es:

    C(T) = [ cp·R(T) + cf·(1−R(T)) ] / ∫₀^T R(t) dt,    R(t) = exp(−(t/η)^β)

- Reactivo (run-to-failure):  C_rtf = cf / MTTF.
- Preventivo óptimo:          C* = min_T C(T)  en  T* .
- Techo predictivo (predicción perfecta): cp / MTTF  ⇒  ahorro máximo = 1 − 1/ρ,  ρ = cf/cp.

REGLA IFR (no negociable, Brief §1.6 / teorema): el reemplazo preventivo por edad solo reduce
costo si la tasa de falla es **creciente** (β > 1). Si el IC bootstrap de β **incluye 1**, la
falla es estadísticamente indistinguible de aleatoria → el motor **rehúsa** preventivo (T*→∞,
ahorro ≈ 0). Es lo que ocurre con `battery` (β≈1) y es lo que separa esto de la charlatanería.
"""
module Decision

using SpecialFunctions: gamma

export DecisionResult, decide, cost_rate_age, mttf, optimal_age, fleet_savings

mttf(beta, eta) = eta * gamma(1 + 1 / beta)

"Confiabilidad Weibull R(t)."
_R(t, beta, eta) = exp(-(t / eta)^beta)

"∫₀^T R(t) dt por regla de Simpson (n par), sin dependencias externas."
function _integral_R(T, beta, eta; n::Int=400)
    T <= 0 && return 0.0
    n = iseven(n) ? n : n + 1          # Simpson compuesto requiere n par
    h = T / n
    s = _R(0.0, beta, eta) + _R(T, beta, eta)
    @inbounds for i in 1:(n - 1)
        s += (isodd(i) ? 4.0 : 2.0) * _R(i * h, beta, eta)
    end
    return s * h / 3
end

"""
    cost_rate_age(T, beta, eta, cp, cf) -> tasa de costo de la política de edad T.
"""
function cost_rate_age(T, beta, eta, cp, cf)
    T <= 1e-9 && return Inf
    R = _R(T, beta, eta)
    den = _integral_R(T, beta, eta)
    return den > 0 ? (cp * R + cf * (1 - R)) / den : Inf
end

"""
    optimal_age(beta, eta, cp, cf) -> (Tstar, Cstar)

Minimiza C(T) por barrido log + refinamiento local. Si β≤1 el óptimo se va al infinito
(política degenerada: nunca reemplazar preventivamente).
"""
function optimal_age(beta, eta, cp, cf)
    lo, hi = log(1e-3 * eta), log(50 * eta)
    npts = 241                                  # impar ⇒ npts-1 par (Simpson aguas abajo)
    grid = range(lo, hi; length=npts)
    bi, best_c = 1, cost_rate_age(exp(grid[1]), beta, eta, cp, cf)
    for (i, l) in enumerate(grid)
        c = cost_rate_age(exp(l), beta, eta, cp, cf)
        if c < best_c
            best_c, bi = c, i
        end
    end
    # óptimo en la frontera superior ⇒ no hay mínimo finito (β≤1, IFR): T*→∞,
    # con tasa límite cf/MTTF (= C_rtf). Evita devolver un T* finito espurio.
    bi >= npts && return Inf, cf / mttf(beta, eta)   # mínimo en la frontera superior ⇒ T*→∞
    best_l = grid[bi]
    # refinamiento local (sección dorada), acotado al dominio [lo, hi]
    step = (hi - lo) / (npts - 1)
    a, b = max(best_l - step, lo), min(best_l + step, hi)
    φ = (sqrt(5) - 1) / 2
    c1, c2 = b - φ * (b - a), a + φ * (b - a)
    f1, f2 = cost_rate_age(exp(c1), beta, eta, cp, cf), cost_rate_age(exp(c2), beta, eta, cp, cf)
    for _ in 1:60
        if f1 < f2
            b, c2, f2 = c2, c1, f1
            c1 = b - φ * (b - a); f1 = cost_rate_age(exp(c1), beta, eta, cp, cf)
        else
            a, c1, f1 = c1, c2, f2
            c2 = a + φ * (b - a); f2 = cost_rate_age(exp(c2), beta, eta, cp, cf)
        end
    end
    Tstar = exp((a + b) / 2)
    return Tstar, cost_rate_age(Tstar, beta, eta, cp, cf)
end

"Resultado de la decisión para un componente."
struct DecisionResult
    component::String
    preventive::Bool          # ¿se recomienda preventivo? (requiere β>1 confirmado)
    reason::String
    Tstar::Union{Float64,Nothing}
    s_prev::Float64           # ahorro preventivo-óptimo vs reactivo (fracción)
    s_ceiling::Float64        # techo predictivo = 1 − 1/ρ
    c_rtf::Float64            # tasa de costo reactivo (run-to-failure)
    c_star::Float64           # tasa de costo preventivo óptimo
    c_floor::Float64          # tasa de costo techo predictivo (cp/MTTF)
end

"""
    decide(component, beta, beta_lo, eta, cp, cf; s_min=0.03) -> DecisionResult

Decisión con la regla IFR: preventivo solo si `beta_lo > 1` (IC excluye 1) y el ahorro es
material (≥ `s_min`). En otro caso, rehúsa y reporta por qué.
"""
function decide(component, beta, beta_lo, eta, cp, cf; s_min::Float64=0.03)
    c_rtf = cf / mttf(beta, eta)
    c_floor = cp / mttf(beta, eta)
    Tstar, Cstar = optimal_age(beta, eta, cp, cf)
    s_prev = 1 - Cstar / c_rtf
    s_ceiling = 1 - cp / cf

    if beta_lo <= 1.0
        return DecisionResult(component, false,
            "IC de β incluye 1 (β_lo=$(round(beta_lo,digits=2))): falla indistinguible de aleatoria — IFR rehúsa preventivo",
            nothing, 0.0, s_ceiling, c_rtf, c_rtf, c_floor)
    elseif s_prev < s_min
        return DecisionResult(component, false,
            "β>1 pero ahorro ($(round(100*s_prev))%) < umbral — no material",
            nothing, s_prev, s_ceiling, c_rtf, Cstar, c_floor)
    else
        return DecisionResult(component, true,
            "β>1 confirmado (β_lo=$(round(beta_lo,digits=2))>1): desgaste — preventivo óptimo en T*",
            Tstar, s_prev, s_ceiling, c_rtf, Cstar, c_floor)
    end
end

"""
    fleet_savings(decision, n_units; hours_per_year=3000.0) -> MXN/año

Proyección de ahorro de flota para un componente con decisión preventiva: la tasa de costo
reactivo por hora × fracción de ahorro × horas/año × unidades con ese componente.
"""
function fleet_savings(d::DecisionResult, n_units::Int; hours_per_year::Float64=3000.0)
    d.preventive || return 0.0
    return d.c_rtf * d.s_prev * hours_per_year * n_units
end

end # module
