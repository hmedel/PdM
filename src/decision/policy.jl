"""
    Policy

Evaluadores de **política de mantenimiento** sobre el sustrato físico CRN (`LifeProcess`). Cada
política se aplica al MISMO mundo (mismos umbrales Θ, misma operación) — números aleatorios comunes
(Glasserman & Yao 1992) — así la diferencia entre brazos es el efecto de la política, no ruido.

Tres políticas:
  - **Reactive** (run-to-failure): la pieza corre hasta fallar; cada falla es correctiva (c_f, a
    menudo en ruta). Es la línea base "sin mantenimiento preventivo".
  - **AgeReplace(T*)**: reemplazo preventivo al alcanzar la edad óptima T* (o falla, lo que ocurra
    primero). Gate IFR: si β≤1 ⇒ T*=∞ ⇒ se reduce a reactivo (battery).
  - **PredictiveRUL(buffer)**: usa la CONDICIÓN (vida remanente observada con error) para reemplazar
    `buffer` horas antes de la falla — captura más vida que el calendario, acercándose al techo.

Devuelve `Outcome`s por instancia con costo y día calendario, que `Economics` descuenta y acumula.
"""
module Policy

export MaintPolicy, Reactive, AgeReplace, PredictiveRUL, Outcome, evaluate, life_records

abstract type MaintPolicy end
struct Reactive <: MaintPolicy end
struct AgeReplace <: MaintPolicy
    Tstar::Dict{String,Float64}      # comp -> T* (Inf = sin preventivo, gate IFR)
end
"""
CBM por condición, atado al **precursor real de cada componente** (capa `Precursors`):
  brake_pad ← espesor de balata (medible, buen lead)          → alarma temprana, sensor preciso
  dpf       ← ΔP + hollín/ceniza DPF (SPN 3251/3719/3720)      → lead medio
  scr       ← NOx/derate SCR (SPN 5246): el derate ES la falla → lead corto, sensor ruidoso
  battery   ← SoH/voltaje de arranque — gated por IFR (β≈1)    → sin preventivo

`alarm_frac` por componente = nivel de degradación OBSERVADA que dispara el reemplazo; refleja la
detectabilidad/lead de su precursor. `sensor_cv` escala el ruido de medición por componente.
"""
struct PredictiveRUL <: MaintPolicy
    alarm_frac::Dict{String,Float64}   # por componente
    sensor_cv::Dict{String,Float64}    # ruido relativo del sensor por componente
    epoch_days::Int
    Tstar::Dict{String,Float64}        # gate IFR (comp con Inf => sin preventivo)
end

struct Outcome
    component::String
    class::Symbol
    install_day::Int                 # día calendario (desde start_date)
    end_day::Int
    kind::Symbol                     # :failure :preventive :censored
    cost::Float64
    in_route::Bool
    downtime_h::Float64
end

# día preventivo (índice local) según la política; `nothing` si no aplica.
# Firma: recibe también Θ, D0, a0_D para que el CBM observe el DAÑO ACUMULADO HASTA HOY.
_trigger(::Reactive, pl, di, cumh0, a0_h, ti, Θ, D0, a0_D) = nothing

function _trigger(p::AgeReplace, pl, di, cumh0, a0_h, ti, Θ, D0, a0_D)
    T = get(p.Tstar, pl.component, Inf)
    isinf(T) && return nothing
    for d in di:pl.ndays
        (pl.cum_h[d + 1] - cumh0) + a0_h >= T && return d
    end
    return nothing
end

# CBM honesto: inspecciona la DEGRADACIÓN OBSERVADA hasta el día d (el precursor de `Precursors`:
# ΔP de filtro, presión de cárter/blowby, espesor de balata, SoH de batería…) con sesgo de sensor.
# NO usa el futuro. El sesgo produce falsos positivos (sobre-lee → alarma temprano) y falsos
# negativos (sub-lee → la pieza falla antes de alarmar). Captura una fracción φ<1 del techo — real.
function _trigger(p::PredictiveRUL, pl, di, cumh0, a0_h, ti, Θ, D0, a0_D)
    isinf(get(p.Tstar, pl.component, Inf)) && return nothing      # gate IFR
    alarm = get(p.alarm_frac, pl.component, 0.85)
    cv = get(p.sensor_cv, pl.component, 1.0)
    # sesgo de medición del precursor de este componente (escala el ruido base por componente)
    bias = max(1 + (pl.pred_noise[min(ti, length(pl.pred_noise))] - 1) * cv, 0.05)
    d = di
    while d <= pl.ndays
        dmg = pl.Dcum[d + 1] - D0 + a0_D                          # degradación REAL acumulada hasta hoy
        (dmg / Θ) * bias >= alarm && return d                     # la LECTURA del precursor cruza la alarma
        dmg >= Θ && return nothing                                # ya falló antes de alarmar (falso negativo)
        d += p.epoch_days
    end
    return nothing
end

"""
    evaluate(pl, policy) -> Vector{Outcome}

Recorre las instancias de la posición bajo `policy`, usando los umbrales Θ y la línea de daño/horas
pre-sorteados (CRN). Renueva en cada reemplazo (preventivo o correctivo).
"""
function evaluate(pl, policy::MaintPolicy)
    out = Outcome[]
    di = 0
    D0 = pl.Dcum[1]; cumh0 = pl.cum_h[1]
    a0_D = pl.a0_D; a0_h = pl.a0_h
    ti = 1
    while true
        if ti > length(pl.thresholds)
            # se agotaron los umbrales pre-sorteados: censurar el resto (no perder el evento)
            push!(out, Outcome(pl.component, pl.class, pl.onboard_day + di,
                  pl.onboard_day + pl.ndays, :censored, 0.0, false, 0.0))
            break
        end
        Θ = pl.thresholds[ti]
        # día de falla natural (cruce de daño)
        fday = nothing
        for d in di:pl.ndays
            if pl.Dcum[d + 1] - D0 + a0_D >= Θ
                fday = d; break
            end
        end
        pday = _trigger(policy, pl, di, cumh0, a0_h, ti, Θ, D0, a0_D)

        local endday, kind, cost, inr, dwn
        if pday !== nothing && (fday === nothing || pday < fday)   # empate ⇒ falla (conservador)
            endday = pday; kind = :preventive
            cost = pl.cp_real[ti]; inr = false; dwn = 2.0
        elseif fday !== nothing
            endday = fday; kind = :failure
            cost = pl.cf_real[ti]; inr = pl.in_route[ti]; dwn = pl.downtime[ti]
        else
            push!(out, Outcome(pl.component, pl.class, pl.onboard_day + di,
                  pl.onboard_day + pl.ndays, :censored, 0.0, false, 0.0))
            break
        end

        push!(out, Outcome(pl.component, pl.class, pl.onboard_day + di,
              pl.onboard_day + endday, kind, cost, inr, dwn))

        (!pl.recurrent || endday >= pl.ndays) && break
        # renovar (instancia nueva desde edad 0)
        di = endday
        D0 = pl.Dcum[di + 1]; cumh0 = pl.cum_h[di + 1]
        a0_D = 0.0; a0_h = 0.0; ti += 1
    end
    return out
end

"""
    life_records(pl) -> Vector{NamedTuple}

Vidas de supervivencia del **mundo reactivo** (run-to-failure) de una posición: una por instancia,
en horas-motor, con censura por la derecha y truncamiento por la izquierda. Es lo que el ajustador
(`Survival.fit_grouped`) consume para recuperar (β, γ, η0) — la estimación se hace SIN preventivo.
"""
function life_records(pl)
    recs = NamedTuple[]
    di = 0; D0 = pl.Dcum[1]; cumh0 = pl.cum_h[1]; a0_D = pl.a0_D; a0_h = pl.a0_h; ti = 1
    while ti <= length(pl.thresholds)
        Θ = pl.thresholds[ti]
        fday = nothing
        for d in di:pl.ndays
            if pl.Dcum[d + 1] - D0 + a0_D >= Θ; fday = d; break; end
        end
        if fday === nothing
            push!(recs, (component_type=pl.component, class=pl.class, brand=pl.brand,
                  model=pl.model, vehicle_id=pl.vehicle_id, route_severity=pl.z, entry_age=a0_h,
                  exit_age=a0_h + (pl.cum_h[end] - cumh0), status=0))
            break
        end
        push!(recs, (component_type=pl.component, class=pl.class, brand=pl.brand,
              model=pl.model, vehicle_id=pl.vehicle_id, route_severity=pl.z, entry_age=a0_h,
              exit_age=a0_h + (pl.cum_h[fday + 1] - cumh0), status=pl.mode_id))
        (!pl.recurrent || fday >= pl.ndays) && break
        di = fday; D0 = pl.Dcum[fday + 1]; cumh0 = pl.cum_h[fday + 1]
        a0_D = 0.0; a0_h = 0.0; ti += 1
    end
    return recs
end

end # module
