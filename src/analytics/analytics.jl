"""
    Analytics

API de **analítica + alertas** (datos JSON-ready) que el servicio de Tracker puede consumir para
graficar y alertar, a tres niveles (componente / vehículo / flota). Es LIGERO: solo usa
Distributions/Statistics + los módulos del paquete (Survival/RUL/Decision/Precursors/Economics/
Policy/DamageModels/LifeProcess). NO depende de Turing ni de Plots.

Recibe los **draws de parámetros** (β, η0, γ) en `ParamDraws`, que el llamador construye de la fuente
que quiera: posterior bayesiano (`BayesEstimator.posterior_draws`, offline) o un ajuste frecuentista
(`from_grouped`). Así la misma API sirve para el reporte offline y para el live de la web.

Entrega (todo `NamedTuple`/`struct` serializable):
  - `distribution_estimate` — distribución de vida a 3 niveles: observada, estimada (predictiva), bajo
    preventivo (censura en T*), + punto estable (MTTF, tasa 1/MTTF).
  - `parameter_summary` — β/η0/γ (media, IC, densidad en grilla).
  - `master_equation` — tasa de falla de la flota vs tiempo (→ estable) + distribución de edades.
  - `economics_summary` — estabilización, break-even, ahorro total y por componente.
  - `component_alerts` / `vehicle_alerts` / `fleet_alerts` — motor de alertas.

La capa de PNG (offline) vive aparte (`src/analytics/plots.jl`) y consume estos datos.
"""
module Analytics

using Distributions, Statistics, Random
using ..Survival, ..RUL, ..Decision, ..Precursors, ..Economics, ..Policy, ..DamageModels, ..LifeProcess

export ParamDraws, from_grouped, distribution_estimate, parameter_summary, master_equation,
       economics_summary, Alert, component_alerts, vehicle_alerts, fleet_alerts

# ============================================================================
# Draws de parámetros (fuente-agnóstica: bayesiano o frecuentista)
# ============================================================================
"Muestras de (β, η0, γ) de un componente — de un posterior bayesiano o de un ajuste frecuentista."
struct ParamDraws
    component::String
    β::Vector{Float64}
    η0::Vector{Float64}     # escala base a z=0
    γ::Vector{Float64}
end

"""
    from_grouped(fit::GroupedFit; n=400, rng) -> ParamDraws

Construye draws aproximados desde un ajuste frecuentista: β ~ Normal centrada en β̂ con sd del IC
bootstrap; η0 = media de η0 por grupo; γ = γ̂ (puntual). Útil para el live rápido sin MCMC.
"""
function from_grouped(fit; n::Int=400, rng::AbstractRNG=MersenneTwister(1))
    sdβ = max((fit.beta_hi - fit.beta_lo) / 3.92, 1e-3)        # IC95% ≈ ±1.96σ
    β  = clamp.(fit.beta .+ sdβ .* randn(rng, n), 0.2, 12.0)
    η0 = fill(mean(values(fit.eta0)), n)
    γ  = fill(fit.gamma, n)
    return ParamDraws(fit.component, β, η0, γ)
end

_pred_pdf(d::ParamDraws, x, z) = mean(pdf(Weibull(d.β[k], d.η0[k] * exp(d.γ[k] * z)), x) for k in eachindex(d.β))
_mttf(d::ParamDraws, z) = mean(mean(Weibull(d.β[k], d.η0[k] * exp(d.γ[k] * z))) for k in eachindex(d.β))

# ============================================================================
# (1) Distribución de vida a 3 niveles
# ============================================================================
"""
    distribution_estimate(draws, records; vehicle_z=nothing, Tstar=Inf, grid_n=160, rng) -> NamedTuple

Datos para graficar la distribución de vida del componente:
  - `observed_density`: histograma normalizado de las vidas observadas (fallas) — la distribución REAL.
  - `component_pdf`: predictiva estimada a severidad media z̄.
  - `vehicle_pdf`: predictiva a la severidad `vehicle_z` (si se da) — nivel vehículo.
  - `fleet_pdf`: marginal sobre la población de rutas — nivel flota.
  - `preventive_pdf` + `preventive_mass_at_Tstar`: distribución de la vida EFECTIVA bajo preventivo
    (min(T, T*)): densidad bajo T* y masa puntual en T* (reemplazos preventivos).
  - punto estable: `mttf`, `stable_rate` = 1/MTTF.
Todo sobre la misma `grid`.
"""
function distribution_estimate(d::ParamDraws, records; vehicle_z=nothing, Tstar::Float64=Inf,
                               grid_n::Int=160, rng::AbstractRNG=MersenneTwister(1))
    obs = Float64[r.exit_age for r in records if r.status > 0]
    zfleet = Float64[r.route_severity for r in records]
    zbar = isempty(zfleet) ? 0.0 : mean(zfleet)
    xmax = isempty(obs) ? 2 * _mttf(d, zbar) : quantile(obs, 0.99) * 1.15
    grid = collect(range(0.0, xmax, length=grid_n))

    comp_pdf = [_pred_pdf(d, x, zbar) for x in grid]
    veh_pdf  = vehicle_z === nothing ? nothing : [_pred_pdf(d, x, vehicle_z) for x in grid]
    # marginal de flota: promedio de la predictiva sobre una muestra de rutas reales
    zsamp = isempty(zfleet) ? [zbar] : zfleet[1:max(1, length(zfleet) ÷ 200):end]
    fleet_pdf = [mean(_pred_pdf(d, x, z) for z in zsamp) for x in grid]
    # observada (histograma normalizado a la grilla)
    obs_density = _hist_density(obs, grid)
    # bajo preventivo: min(T, T*) → densidad bajo T*, masa en T*
    massT = isinf(Tstar) ? 0.0 :
            mean(ccdf(Weibull(d.β[k], d.η0[k] * exp(d.γ[k] * zbar)), Tstar) for k in eachindex(d.β))
    prev_pdf = [g <= Tstar ? comp_pdf[i] : 0.0 for (i, g) in enumerate(grid)]

    return (component=d.component, grid=grid, observed_density=obs_density, n_obs=length(obs),
            component_pdf=comp_pdf, vehicle_pdf=veh_pdf, fleet_pdf=fleet_pdf,
            preventive_pdf=prev_pdf, preventive_mass_at_Tstar=massT, Tstar=Tstar,
            mttf=_mttf(d, zbar), stable_rate=1 / _mttf(d, zbar), zbar=zbar)
end

"Densidad por histograma sobre los centros de `grid` (∫≈1)."
function _hist_density(x, grid)
    n = length(grid); dens = zeros(n)
    isempty(x) && return dens
    lo, hi = first(grid), last(grid); w = (hi - lo) / (n - 1)
    w <= 0 && return dens                                       # parámetro/grilla constante: sin densidad
    for v in x
        b = clamp(round(Int, (v - lo) / w) + 1, 1, n); dens[b] += 1
    end
    s = sum(dens) * w
    return s > 0 ? dens ./ s : dens
end

# ============================================================================
# (2) Resumen de parámetros (β, η0, γ)
# ============================================================================
"Resumen de cada parámetro: media, IC95% y densidad en grilla (para histograma/KDE en el front)."
function parameter_summary(d::ParamDraws; grid_n::Int=120)
    function q(x)
        lo, hi = quantile(x, 0.001), quantile(x, 0.999)
        hi <= lo && (e = max(abs(lo) * 0.01, 1e-6); lo -= e; hi += e)   # draws constantes: grilla mínima
        g = collect(range(lo, hi, length=grid_n))
        (mean=mean(x), lo=quantile(x, 0.025), hi=quantile(x, 0.975), grid=g, density=_hist_density(x, g))
    end
    return (component=d.component, β=q(d.β), η0=q(d.η0), γ=q(d.γ))
end

# ============================================================================
# (3) Ecuación maestra: tasa de falla de la flota → estable + edades
# ============================================================================
"Días de falla (renovaciones) de una posición a lo largo del horizonte."
function _failure_days(pl)
    di = 0; D0 = pl.Dcum[1]; a0 = pl.a0_D; ti = 1; fds = Int[]
    while ti <= length(pl.thresholds)
        Θ = pl.thresholds[ti]; fday = nothing
        for dd in di:pl.ndays
            (pl.Dcum[dd + 1] - D0 + a0 >= Θ) && (fday = dd; break)
        end
        fday === nothing && break
        push!(fds, fday); (!pl.recurrent) && break
        di = fday; D0 = pl.Dcum[fday + 1]; a0 = 0.0; ti += 1
    end
    fds
end

"""
    master_equation(lives, comp; horizon, binw=30, age_snapshots) -> NamedTuple

Evolución de la ecuación de renovación de la flota para `comp`: tasa de falla por mes (→ estado
estacionario) y distribución de edades en varios tiempos (→ equilibrio S(a)/μ).
"""
function master_equation(lives, comp::AbstractString; horizon::Int, binw::Int=30,
                         age_snapshots::Vector{Int}=[90, 360, horizon - 30])
    pls = [pl for pl in lives if pl.component == comp]
    nb = horizon ÷ binw
    rate = zeros(nb)
    for pl in pls, fd in _failure_days(pl)
        b = min(fd ÷ binw + 1, nb); rate[b] += 1
    end
    rate ./= (length(pls) * binw / 30)                 # fallas/unidad·mes
    months = collect((1:nb) .* (binw / 30))
    # distribución de edades en snapshots
    ages = Dict{Int,Vector{Float64}}()
    for day in age_snapshots
        a = Float64[]
        for pl in pls
            fds = _failure_days(pl); last0 = 0
            for fd in fds; fd < day ? (last0 = fd) : break; end
            push!(a, day - last0)
        end
        ages[day] = a
    end
    stab = Economics._stabilization(rate, collect(binw:binw:horizon))
    return (component=comp, months=months, rate=rate, stabilization_day=stab,
            age_snapshots=age_snapshots, ages=ages)
end

# ============================================================================
# (4) Económica: estabilización, break-even, ahorro total y por componente
# ============================================================================
"""
    economics_summary(lives, truth; cfg, horizon, n_vehicles, rng) -> NamedTuple

Corre reactivo vs predictivo (CBM físico) y resume: estabilización, break-even, ahorro VPN total y el
**desglose por componente** (k MXN/unidad·año, sin costo de programa). T* por componente desde la verdad.
"""
function economics_summary(lives, truth; cfg::Economics.EconConfig=Economics.EconConfig(),
                           horizon::Int, n_vehicles::Int)
    comps = unique(pl.component for pl in lives)
    recs_z(c) = [pl.z for pl in lives if pl.component == c]
    Tstar = Dict{String,Float64}()
    for c in comps
        tc = truth.comp[c]; zb = mean(recs_z(c))
        ηf = mean(v for (k, v) in truth.eta0 if last(k) == c) * exp(tc.gamma * zb)
        Tstar[c] = Decision.optimal_age(tc.beta, ηf, tc.cp, tc.cf)[1]
    end
    cbm   = [c for c in comps if haskey(Precursors.PRECURSOR_INFO, c)]
    alarm = Dict(c => Precursors.alarm_fraction(c) for c in cbm)
    scv   = Dict(c => Precursors.sensor_cv(c) for c in cbm)
    pol   = Policy.PredictiveRUL(alarm, scv, 14, Tstar)
    econ  = Economics.run_economics(lives, Policy.evaluate, Policy.Reactive(), pol, cfg;
                                    horizon_days=horizon, n_vehicles=n_vehicles)
    # desglose por componente (sin costo de programa)
    cfg0 = Economics.EconConfig(annual_discount=cfg.annual_discount, hw_per_vehicle=0.0,
                                monthly_fee=0.0, hours_per_year=cfg.hours_per_year,
                                purchase_price=cfg.purchase_price)
    per_comp = Dict{String,Float64}()
    for c in comps
        lc = [pl for pl in lives if pl.component == c]
        ec = Economics.run_economics(lc, Policy.evaluate, Policy.Reactive(), pol, cfg0;
                                     horizon_days=horizon, n_vehicles=n_vehicles)
        per_comp[c] = ec.cum_savings[end] / (horizon / 365) / n_vehicles    # MXN/unidad·año
    end
    return (months=econ.day_points ./ 30, cum_reactive=econ.cum_reactive,
            cum_preventive=econ.cum_preventive, cum_savings=econ.cum_savings,
            monthly_fail_reactive=econ.monthly_fail_reactive,
            monthly_fail_preventive=econ.monthly_fail_preventive,
            stabilization_day=econ.stabilization_day, breakeven_day=econ.breakeven_day,
            savings_total_vpn=econ.cum_savings[end],
            savings_per_unit_year=econ.cum_savings[end] / (horizon / 365) / n_vehicles,
            savings_by_component=per_comp, Tstar=Tstar)
end

# ============================================================================
# (5) Motor de alertas (componente / vehículo / flota)
# ============================================================================
"Alerta para el servicio de Tracker."
struct Alert
    level::Symbol      # :component | :vehicle | :fleet
    target::String     # componente | vehicle_id | "fleet"
    severity::Symbol   # :info | :warn | :critical
    code::String       # CBM_ALARM | RUL_LOW | PAST_TSTAR | FLEET_RATE_HIGH | FLEET_MANY_CRITICAL
    message::String
    metric::Float64
end

"""
    component_alerts(est; rul_warn=0.25, rul_crit=0.10) -> Vector{Alert}

Alertas para una unidad-componente desde su `MaintenanceEstimate` (Estimator). Reglas:
  - CBM_ALARM (critical): el precursor cruzó el umbral físico.
  - PAST_TSTAR (critical): la edad ya pasó el intervalo óptimo T* (preventivo vencido).
  - RUL_LOW (warn/critical): la RUL relativa a la vida cae bajo umbrales.
`vehicle_id` opcional para etiquetar el target.
"""
function component_alerts(est; vehicle_id::AbstractString="", current_age=nothing,
                          rul_warn::Float64=0.25, rul_crit::Float64=0.10)
    out = Alert[]
    tag = isempty(vehicle_id) ? est.component_type : "$(vehicle_id)/$(est.component_type)"
    if est.cbm_alarm
        push!(out, Alert(:component, tag, :critical, "CBM_ALARM",
              "Precursor cruzó el umbral físico — intervenir ya", 1.0))
    end
    if current_age !== nothing && est.optimal_interval !== nothing && current_age > est.optimal_interval
        push!(out, Alert(:component, tag, :critical, "PAST_TSTAR",
              "Edad $(round(Int,current_age)) > T*=$(round(Int,est.optimal_interval)) — preventivo vencido",
              current_age / est.optimal_interval))
    end
    if current_age !== nothing && (est.rul + current_age) > 0
        rel = est.rul / (est.rul + current_age)                # RUL como fracción de la vida total
        if rel <= rul_crit
            push!(out, Alert(:component, tag, :critical, "RUL_LOW",
                  "RUL ≈ $(round(Int,est.rul)) ($(round(Int,100rel))% de la vida) — crítico", rel))
        elseif rel <= rul_warn
            push!(out, Alert(:component, tag, :warn, "RUL_LOW",
                  "RUL ≈ $(round(Int,est.rul)) ($(round(Int,100rel))% de la vida) — atender", rel))
        end
    end
    return out
end

"""
    vehicle_alerts(vehicle_id, ests; current_ages=nothing) -> Vector{Alert}

Agrega las alertas de los componentes de un vehículo + una alerta de vehículo si tiene ≥1 crítica.
`ests` = MaintenanceEstimate[] del vehículo; `current_ages` = Dict componente→edad (opcional).
"""
function vehicle_alerts(vehicle_id::AbstractString, ests; current_ages=nothing)
    out = Alert[]
    for e in ests
        age = current_ages === nothing ? nothing : get(current_ages, e.component_type, nothing)
        append!(out, component_alerts(e; vehicle_id=vehicle_id, current_age=age))
    end
    ncrit = count(a -> a.severity == :critical, out)
    ncrit > 0 && pushfirst!(out, Alert(:vehicle, vehicle_id, :critical, "VEHICLE_CRITICAL",
        "$ncrit componente(s) en estado crítico", Float64(ncrit)))
    return out
end

"""
    fleet_alerts(ests_by_vehicle, econ; crit_frac=0.10) -> Vector{Alert}

Alertas de flota: fracción de unidades con ≥1 componente crítico, y tasa de falla actual sobre el
estado estacionario. `ests_by_vehicle` = Dict vehicle_id→MaintenanceEstimate[]; `econ` = economics_summary.
"""
function fleet_alerts(ests_by_vehicle, econ; current_ages=nothing, crit_frac::Float64=0.10)
    out = Alert[]
    nveh = length(ests_by_vehicle); nveh == 0 && return out
    ncrit_veh = 0
    for (vid, ests) in ests_by_vehicle
        ages = current_ages === nothing ? nothing : get(current_ages, vid, nothing)
        va = vehicle_alerts(vid, ests; current_ages=ages)
        any(a -> a.level == :vehicle && a.severity == :critical, va) && (ncrit_veh += 1)
    end
    frac = ncrit_veh / nveh
    if frac >= crit_frac
        push!(out, Alert(:fleet, "fleet", :critical, "FLEET_MANY_CRITICAL",
              "$(round(Int,100frac))% de la flota con componente crítico", frac))
    end
    # tasa de falla reciente vs estable (de la economía/maestra)
    mfr = econ.monthly_fail_reactive
    if length(mfr) >= 6
        recent = mean(mfr[max(1, end-2):end]); stable = mean(mfr[max(1, end-5):end])
        if stable > 0 && recent > 1.15 * stable
            push!(out, Alert(:fleet, "fleet", :warn, "FLEET_RATE_HIGH",
                  "Tasa de falla reciente $(round(recent,digits=2)) > 1.15× estable", recent / stable))
        end
    end
    return out
end

end # module Analytics
