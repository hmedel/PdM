"""
    Economics

Economía de **horizonte finito con descuento** del estudio contrafactual: trayectorias de costo
acumulado (VPN), **break-even**, **estabilización** de la distribución de fallas/costo (transitorio
de renovación), veredicto por ventana de vida productiva, y EUAC del camión.

Sustento:
  - Renovación-recompensa y costo de largo plazo: Barlow & Proschan (1965); Jardine & Tsang (2013).
  - Transitorio antes del régimen estacionario: teorema de renovación / Blackwell (la tasa de costo
    converge a la asintótica con un transitorio cuantificable; arXiv 2401.12265 en vida finita).
  - Horizonte finito ⇒ política óptima no estacionaria: Jiang et al., RESS (2009).
  - Vida económica del vehículo (EUAC): caso de flota cisterna, ScienceDirect (2023).
  - Descuento 12% anual (costo de capital de flota MX); configurable.
"""
module Economics

using Statistics

export EconConfig, EconResult, run_economics, euac_curve, crn_variance_reduction

struct EconConfig
    annual_discount::Float64     # tasa de descuento anual (VPN)
    hw_per_vehicle::Float64      # costo de hardware/onboarding por unidad (programa preventivo)
    monthly_fee::Float64         # plataforma + análisis por unidad/mes
    hours_per_year::Float64      # horas-motor/año/unidad (para EUAC)
    purchase_price::Float64      # precio del camión (EUAC)
end

EconConfig(; annual_discount=0.12, hw_per_vehicle=2000.0, monthly_fee=350.0,
             hours_per_year=3000.0, purchase_price=2_500_000.0) =
    EconConfig(annual_discount, hw_per_vehicle, monthly_fee, hours_per_year, purchase_price)

_df(day, r) = 1 / (1 + r)^(day / 365)     # factor de descuento

struct EconResult
    day_points::Vector{Int}
    cum_reactive::Vector{Float64}    # costo acumulado descontado (reactivo)
    cum_preventive::Vector{Float64}  # idem con preventivo + costo de programa
    cum_savings::Vector{Float64}     # reactivo − (preventivo + programa)
    breakeven_day::Union{Int,Nothing}
    monthly_fail_reactive::Vector{Float64}   # fallas/mes/unidad (para estabilización)
    monthly_fail_preventive::Vector{Float64}
    stabilization_day::Union{Int,Nothing}
    n_vehicles::Int
end

"Costo acumulado descontado en cada punto de día."
function _cum_discounted(outcomes, r, day_points)
    flows = sort([(o.end_day, o.cost) for o in outcomes if o.kind != :censored])
    cum = zeros(length(day_points)); acc = 0.0; j = 1
    for (i, dp) in enumerate(day_points)
        while j <= length(flows) && flows[j][1] <= dp
            acc += flows[j][2] * _df(flows[j][1], r); j += 1
        end
        cum[i] = acc
    end
    return cum
end

"Fallas por mes por unidad (para detectar el régimen estacionario)."
function _monthly_failrate(outcomes, day_points, nveh)
    rate = zeros(length(day_points))
    fdays = sort([o.end_day for o in outcomes if o.kind == :failure])
    prev = 0; j = 1
    for (i, dp) in enumerate(day_points)
        c = 0
        while j <= length(fdays) && fdays[j] <= dp
            c += 1; j += 1
        end
        rate[i] = c / nveh / max((dp - prev) / 30, 1e-9)   # fallas/mes/unidad
        prev = dp
    end
    return rate
end

"Día en que la tasa de fallas alcanza (y se queda en) ±tol de su valor de régimen (último año)."
function _stabilization(rate, day_points; tol=0.15)
    n = length(rate); n < 14 && return nothing
    final = mean(rate[max(1, n - 11):n])
    final <= 0 && return nothing
    w = 3
    for i in w:n
        ma = mean(rate[i-w+1:i])
        if abs(ma / final - 1) <= tol &&
           all(j -> abs(mean(rate[max(1,j-w+1):j]) / final - 1) <= tol, i:min(n, i + 6))
            return day_points[i]
        end
    end
    return nothing
end

"""
    run_economics(lives, pol_reactive, pol_preventive, cfg; horizon_days, n_vehicles) -> EconResult

Evalúa ambos brazos (CRN) sobre el sustrato `lives` y calcula las trayectorias, break-even y
estabilización. `pol_*` son políticas de `Policy`; `evaluate_fn(pl, pol)` se inyecta para no acoplar.
"""
function run_economics(lives, evaluate_fn, pol_reactive, pol_preventive, cfg::EconConfig;
                       horizon_days::Int, n_vehicles::Int)
    out_react = reduce(vcat, [evaluate_fn(pl, pol_reactive) for pl in lives])
    out_prev  = reduce(vcat, [evaluate_fn(pl, pol_preventive) for pl in lives])

    day_points = collect(30:30:horizon_days)
    r = cfg.annual_discount

    cumR = _cum_discounted(out_react, r, day_points)
    cumP = _cum_discounted(out_prev, r, day_points)
    # costo del programa preventivo: hardware al inicio + cuota mensual por unidad, descontado
    prog = zeros(length(day_points))
    acc = n_vehicles * cfg.hw_per_vehicle
    for (i, dp) in enumerate(day_points)
        acc += n_vehicles * cfg.monthly_fee * _df(dp, r)
        prog[i] = acc
    end
    cumP_total = cumP .+ prog
    savings = cumR .- cumP_total
    # break-even SOSTENIDO: primer t con ahorro>0 que se mantiene (evita capturar un cruce transitorio)
    be = findfirst(i -> all(>(0), @view savings[i:end]), 1:length(savings))
    breakeven_day = be === nothing ? nothing : day_points[be]

    mfR = _monthly_failrate(out_react, day_points, n_vehicles)
    mfP = _monthly_failrate(out_prev, day_points, n_vehicles)
    stab = _stabilization(mfR, day_points)

    return EconResult(day_points, cumR, cumP_total, savings, breakeven_day,
                      mfR, mfP, stab, n_vehicles)
end

"""
    euac_curve(annual_maint, cfg; max_years=10) -> (years, euac)

Costo Anual Uniforme Equivalente del camión vs vida de servicio L: recuperación de capital
(precio − VP del salvamento) + mantenimiento anualizado. El mínimo es la **vida económica**.
"""
function euac_curve(annual_maint::Float64, cfg::EconConfig; max_years::Int=10)
    r = cfg.annual_discount
    years = collect(1:max_years)
    euac = Float64[]
    for L in years
        salvage = cfg.purchase_price * 0.6 * (1 - L / 15)        # depreciación ~lineal a 15 años
        salvage = max(salvage, 0.05 * cfg.purchase_price)
        crf = r * (1 + r)^L / ((1 + r)^L - 1)                    # factor de recuperación de capital
        cap = (cfg.purchase_price - salvage / (1 + r)^L) * crf
        push!(euac, cap + annual_maint)                         # maint ya es ~anual
    end
    return years, euac
end

"""
    crn_variance_reduction(lives, evaluate_fn, polA, polB, r) -> (correlation, var_reduction, n)

MIDE (no afirma) el beneficio del acoplamiento por números aleatorios comunes: agrega el costo
descontado por vehículo bajo cada política y calcula la reducción de varianza de la diferencia,
`1 − Var(A−B)/(Var A + Var B) = 2·Cov(A,B)/(Var A + Var B)`. Alta correlación ⇒ el CRN reduce ruido.
"""
function crn_variance_reduction(lives, evaluate_fn, polA, polB, r)
    A = Dict{String,Float64}(); B = Dict{String,Float64}()
    for pl in lives
        for o in evaluate_fn(pl, polA)
            o.kind != :censored && (A[pl.vehicle_id] = get(A, pl.vehicle_id, 0.0) + o.cost * _df(o.end_day, r))
        end
        for o in evaluate_fn(pl, polB)
            o.kind != :censored && (B[pl.vehicle_id] = get(B, pl.vehicle_id, 0.0) + o.cost * _df(o.end_day, r))
        end
    end
    vids = collect(keys(A))
    a = [get(A, v, 0.0) for v in vids]; b = [get(B, v, 0.0) for v in vids]
    d = a .- b
    var_indep = var(a) + var(b)
    red = var_indep > 0 ? 1 - var(d) / var_indep : 0.0
    return (correlation = cor(a, b), var_reduction = red, n = length(vids))
end

end # module
