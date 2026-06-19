"""
    CBM — Condition-Based Maintenance (Tier-1, sin calibración).

El primer producto alimentable sin calibrar: DTCs (DM1/DM2 de J1939) → órdenes de trabajo
priorizadas por severidad FMECA. No requiere modelo estadístico — es regla determinista sobre
el código de diagnóstico — y por eso es el Tier-1 del Brief §1.7.

Cada (SPN, FMI) se mapea a una descripción y una severidad (S de la RPN, 1–10). Las órdenes se
ordenan por prioridad. El caso crítico es el **derate SCR (SPN 5246 / FMI 4)**: la unidad entra
en par reducido y puede **quedar varada en ruta** — exactamente el evento de costo `c_f` alto que
el mantenimiento predictivo existe para evitar.
"""
module CBM

export DtcRule, DTC_RULES, work_orders, WorkOrder

struct DtcRule
    spn::Int
    fmi::Int
    description::String
    severity::Int          # S de la RPN (FMECA), 1–10
    stranding_risk::Bool   # ¿puede dejar la unidad varada en ruta? (dispara c_f)
end

# Reglas semilla (ligadas al FMECA). Aftertreatment confirmado por SPN; layout PGN en J1939.jl
# queda pgn=0 hasta confirmar contra DBC (no inventar).
const DTC_RULES = Dict{Tuple{Int,Int},DtcRule}(
    (5246, 4)  => DtcRule(5246, 4,  "Derate SCR — par reducido, unidad puede quedar VARADA", 9, true),
    (3251, 16) => DtcRule(3251, 16, "ΔP DPF alto — saturación / regeneración requerida",      6, false),
    (1761, 1)  => DtcRule(1761, 1,  "Nivel DEF bajo — riesgo de inducement",                   5, false),
)

"Orden de trabajo generada por un DTC."
struct WorkOrder
    vehicle_id::String
    instance_id::Int
    component_type::String
    spn::Int
    fmi::Int
    description::String
    priority::Int
    stranding_risk::Bool
    event_time::Any        # Date del DTC (lead time antes de la falla)
end

"""
    work_orders(events, instance_pos, pos_vehicle, pos_comp) -> Vector{WorkOrder}

Genera órdenes de trabajo a partir de los eventos `:auto_dtc`. Recibe mapas para resolver
instancia → (vehículo, componente). Ordena por prioridad (severidad FMECA) descendente,
y dentro de igual prioridad, los de riesgo de varado primero.
"""
function work_orders(events, instance_vehicle::Dict, instance_comp::Dict)
    wos = WorkOrder[]
    for e in events
        e.type == :auto_dtc || continue
        rule = get(DTC_RULES, (e.dtc_spn, e.dtc_fmi),
                   DtcRule(e.dtc_spn, e.dtc_fmi, "DTC no catalogado — revisar", 5, false))
        push!(wos, WorkOrder(get(instance_vehicle, e.instance_id, "?"), e.instance_id,
              get(instance_comp, e.instance_id, "?"), e.dtc_spn, e.dtc_fmi,
              rule.description, rule.severity, rule.stranding_risk, e.event_time))
    end
    sort!(wos, by = w -> (-w.priority, !w.stranding_risk, w.event_time))
    return wos
end

end # module
