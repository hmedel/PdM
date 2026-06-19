# ============================================================================
# api.jl — Superficie pública del ESTIMADOR de mantenimiento preventivo.
#
# Esqueleto pensado para montarse en una API que consume la BD por (vehículo, componente):
#   - ENTRADA (de la BD): historial de instancias del componente (`ServiceRecord`) + estado actual
#     de la unidad viva (`LiveUnit`).
#   - SALIDA: `MaintenanceEstimate` con RUL, intervalo óptimo T*, veredicto IFR y cuándo intervenir.
#
# El MISMO contrato sirve con datos reales (BD) o simulados (banco de pruebas FleetSimulator): por eso
# el simulador sirve para "calar" este estimador (le metes data con β/γ/η conocidos y verificas que los
# recupere). Ver docs/Arquitectura_Unificada_Merge.md y el split estimador/simulador.
#
# Envuelve: Survival.fit_grouped (β,γ,η + IC bootstrap), RUL.mean_residual_life/conditional_eta,
# Decision.decide (regla IFR + materialidad), Precursors (umbral físico de alarma CBM).
# ============================================================================

"""
Registro histórico de una instancia de componente (una pieza instalada), tal como lo entrega la BD.
Edades en horas-motor (la escala de tiempo basada en uso). `status>0` = falló; `0` = censurado (vivo).
`route_severity` es la covariable AFT z (severidad del corredor, normalizada).
"""
struct ServiceRecord
    component_type::String
    class::Symbol
    brand::String
    route_severity::Float64
    entry_age::Float64     # edad al inicio de observación (trunc. izquierda)
    exit_age::Float64      # edad a la falla o a la censura
    status::Int            # >0 falló, 0 censurado
end

"""
Unidad viva que requiere decisión de mantenimiento — su estado actual desde la BD.
`precursor_reading` es la última lectura del sensor precursor del componente (opcional; habilita CBM).
"""
struct LiveUnit
    component_type::String
    class::Symbol
    brand::String
    route_severity::Float64
    current_age::Float64
    precursor_reading::Union{Nothing,Float64}
end
LiveUnit(c, cl, b, z, age) = LiveUnit(c, cl, b, z, age, nothing)

"Salida del estimador para una unidad."
struct MaintenanceEstimate
    component_type::String
    rul::Float64                              # vida remanente esperada (horas-motor)
    beta::Float64
    beta_lo::Float64                          # límite inferior IC de β (gobierna IFR)
    eta::Float64                              # η condicional de la unidad (η0_grupo·e^{γz})
    optimal_interval::Union{Float64,Nothing}  # T* (nothing si IFR rehúsa preventivo)
    recommend_preventive::Bool
    recommend_at_age::Float64                 # edad de la pieza a la que se recomienda intervenir
    cbm_alarm::Bool                           # ¿la lectura actual cruzó el umbral físico?
    rationale::String
end

"""
    crossed_alarm(component, reading) -> Bool

¿La lectura actual del precursor cruzó el umbral físico de alarma? La dirección la define el mapa
físico de `Precursors` (p. ej. balata BAJA hacia la falla; ΔP DPF SUBE).
"""
function crossed_alarm(component::AbstractString, reading::Real)
    haskey(PRECURSOR_INFO, component) || return false
    p = PRECURSOR_INFO[component]
    p.fail_val >= p.new_val ? reading >= p.alarm_val : reading <= p.alarm_val
end

"""
    estimate_maintenance(history, unit; cp, cf, nboot=200, rng=MersenneTwister(1)) -> MaintenanceEstimate

Estima cuándo hacer mantenimiento de `unit` a partir del `history` de su tipo de componente.
`cp`/`cf` = costo preventivo / correctivo (para la regla IFR y T*). `history` es cualquier vector de
registros con los campos de `ServiceRecord` (la BD los provee; el simulador también, idéntico contrato).

Lógica del esqueleto:
  1. Ajusta Weibull-AFT agrupado → (β, β_lo, γ, η0 por grupo) con IC bootstrap.
  2. η condicional de la unidad = η0_grupo·e^{γ·z}; RUL = E[T−t | T>t].
  3. Decisión IFR: si β_lo>1 y el ahorro es material → preventivo en T*; si no, run-to-failure.
  4. CBM: si hay lectura y cruzó el umbral físico → intervenir ya.

Conveniencia para una sola unidad. Para procesar muchas unidades del MISMO componente, usa el camino
batch (`fit_component` una vez + `estimate` por unidad); para toda la flota usa `estimate_fleet`.
"""
estimate_maintenance(history::AbstractVector, unit::LiveUnit;
                     cp::Real, cf::Real, nboot::Int=200, rng::AbstractRNG=MersenneTwister(1)) =
    estimate(fit_component(history; cp=cp, cf=cf, nboot=nboot, rng=rng), unit)

# ============================================================================
# API BATCH (servidor: ajustar una vez por componente, evaluar muchas unidades).
# Clave de eficiencia: el ajuste Weibull-AFT + bootstrap + decisión IFR es CARO y va 1× por tipo de
# componente; la evaluación por unidad es BARATA. Y como en Weibull T* ∝ η y el ahorro `s_prev` es
# invariante de escala, la decisión IFR se calcula UNA vez (a una η representativa) y T* se reescala
# por unidad con η_unidad/η_rep — exacto, sin re-optimizar por unidad.
# ============================================================================

"Modelo ajustado de un tipo de componente — caro de calcular, reusable para miles de unidades."
struct ComponentModel
    component_type::String
    fit::GroupedFit                            # β, β_lo, γ, η0 por grupo (clase,marca)
    decision::DecisionResult                   # IFR/materialidad (invariante de η) + T* a η_rep
    eta_rep::Float64                            # η representativa usada en `decision` (para reescalar T*)
    cp::Float64
    cf::Float64
    has_precursor::Bool                         # ¿tiene precursor on-board? (si no → estadístico, sin CBM)
end

"""
    fit_component(history; cp, cf, nboot=200, rng) -> ComponentModel

Ajusta el modelo de vida de UN tipo de componente (deriva el nombre de `history`). Caro: hazlo una
sola vez por componente y reusa el `ComponentModel` con `estimate`/`estimate_fleet`.
"""
function fit_component(history::AbstractVector; cp::Real, cf::Real,
                       nboot::Int=200, rng::AbstractRNG=MersenneTwister(1))
    isempty(history) && error("fit_component: historial vacío")
    comp = first(history).component_type
    fit = fit_grouped(history; nboot=nboot, rng=rng)
    eta_rep = sum(values(fit.eta0)) / length(fit.eta0)          # η representativa (media de grupos)
    dec = decide(comp, fit.beta, fit.beta_lo, eta_rep, cp, cf)  # IFR/materialidad: invariante de η
    return ComponentModel(comp, fit, dec, eta_rep, Float64(cp), Float64(cf),
                          haskey(PRECURSOR_INFO, comp))
end

"""
    estimate(model, unit) -> MaintenanceEstimate

Evalúa UNA unidad viva con un `ComponentModel` ya ajustado (barato). η condicional de la unidad por su
grupo/severidad; T* reescalado por η_unidad/η_rep; CBM si hay precursor y lectura.
"""
function estimate(model::ComponentModel, unit::LiveUnit)
    eta0_group = get(model.fit.eta0, (unit.class, unit.brand), first(values(model.fit.eta0)))
    eta_u = conditional_eta(eta0_group, model.fit.gamma, unit.route_severity)
    rul = mean_residual_life(unit.current_age, model.fit.beta, eta_u)

    # T* de esta unidad: la decisión IFR es invariante de η; T* escala lineal con η (exacto en Weibull).
    tstar_u = (model.decision.preventive && model.decision.Tstar !== nothing) ?
              model.decision.Tstar * (eta_u / model.eta_rep) : nothing

    alarm = (model.has_precursor && unit.precursor_reading !== nothing) ?
            crossed_alarm(model.component_type, unit.precursor_reading) : false

    # Cuándo intervenir: CBM (alarma física) manda → ya; si no y IFR aprueba → en T*; si no → run-to-failure.
    rec_age = alarm ? unit.current_age :
              (model.decision.preventive ? something(tstar_u, unit.current_age + rul) :
               unit.current_age + rul)

    return MaintenanceEstimate(model.component_type, rul, model.fit.beta, model.fit.beta_lo, eta_u,
                               tstar_u, model.decision.preventive, rec_age, alarm, model.decision.reason)
end

"""
    estimate_fleet(history, units, costs; nboot=200, rng) -> Vector{MaintenanceEstimate}

Procesa TODA la flota: agrupa `history` por componente, ajusta UN `ComponentModel` por tipo (presente
en `units` y con historial y costo), y evalúa cada unidad. `costs[comp]` = `(cp, cf)` o `(cp=, cf=)`.
Unidades cuyo componente no tiene historial o costo se omiten (no se pueden ajustar). Pensado para el
job batch del servidor que lee la BD y escribe los resultados.
"""
function estimate_fleet(history::AbstractVector, units::AbstractVector, costs::AbstractDict;
                        nboot::Int=200, rng::AbstractRNG=MersenneTwister(1))
    by_comp = Dict{String,Vector{eltype(history)}}()
    for r in history
        push!(get!(by_comp, r.component_type, eltype(history)[]), r)
    end
    models = Dict{String,ComponentModel}()
    for comp in unique(u.component_type for u in units)
        (haskey(by_comp, comp) && haskey(costs, comp)) || continue
        cp, cf = costs[comp]
        models[comp] = fit_component(by_comp[comp]; cp=cp, cf=cf, nboot=nboot, rng=rng)
    end
    out = MaintenanceEstimate[]
    for u in units
        haskey(models, u.component_type) && push!(out, estimate(models[u.component_type], u))
    end
    return out
end
