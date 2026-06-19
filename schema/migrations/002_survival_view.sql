-- ============================================================================
-- WS-A — Migración 002: la vista derivada que alimenta supervivencia (Cox/Weibull).
--
-- El modelo NO consume las tablas crudas: consume, por cada instancia, la tripleta
-- (entry_age, exit_age, status). Esta vista la deriva en escala de HORAS-MOTOR
-- (escala de vida primaria del simulador; ver Esquema_Datos_Evento_WS_A.md §3).
--
--   entry_age = horas-motor a la entrada de observación − a la instalación  (truncamiento izq.)
--   exit_age  = horas-motor a la salida (evento terminal o último snapshot)  − a la instalación
--   status    = mode_id si el evento terminal es falla; 0 si censurada (sigue viva)
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW surv_engineh AS
WITH term AS (   -- evento terminal de cada instancia (falla/reemplazo/remoción) o NULL si vive
    SELECT DISTINCT ON (e.instance_id)
           e.instance_id, e.engine_h AS exit_h, e.mode_id, e.type
    FROM event e
    WHERE e.type IN ('failure','corrective_replace','preventive_replace','removal')
    ORDER BY e.instance_id, e.event_time DESC
),
last_snap AS (   -- último uso conocido del vehículo (para censura por la derecha)
    SELECT DISTINCT ON (vehicle_id) vehicle_id, engine_h
    FROM usage_snapshot
    ORDER BY vehicle_id, ts DESC
)
SELECT
    ci.instance_id,
    p.component_type,
    v.vehicle_id, v.class, v.brand, v.model,                       -- niveles jerárquicos (VII.2)
    v.route_severity,                                              -- covariable x del AFT/Cox
    GREATEST(0, COALESCE(ci.install_engine_h, 0) - COALESCE(ci.install_engine_h, 0)) AS entry_age_base,
    -- entry_age: si la instalación es imputada (preexistente) la edad de entrada es > 0;
    -- el simulador ya materializa la tripleta exacta, esta vista la reconstruye desde eventos.
    COALESCE(t.exit_h, ls.engine_h) - COALESCE(ci.install_engine_h, 0) AS exit_age,
    CASE WHEN t.type IN ('failure','corrective_replace') THEN COALESCE(t.mode_id, 0)
         ELSE 0 END                                                AS status,
    NOT ci.install_known                                           AS entry_imputed
FROM component_instance ci
JOIN position p ON p.position_id = ci.position_id
JOIN vehicle  v ON v.vehicle_id  = p.vehicle_id
LEFT JOIN term      t  ON t.instance_id = ci.instance_id
LEFT JOIN last_snap ls ON ls.vehicle_id = v.vehicle_id;

-- Vista de conveniencia: órdenes de trabajo activas por DTC (CBM Tier-1), priorizadas.
CREATE OR REPLACE VIEW cbm_work_orders AS
SELECT
    e.event_id, e.event_time, v.vehicle_id, p.component_type,
    e.dtc_spn, e.dtc_fmi,
    fm.code, fm.description, fm.fmeca_severity AS priority
FROM event e
JOIN component_instance ci ON ci.instance_id = e.instance_id
JOIN position p ON p.position_id = ci.position_id
JOIN vehicle  v ON v.vehicle_id  = p.vehicle_id
LEFT JOIN failure_mode fm ON fm.component_type = p.component_type
WHERE e.type = 'auto_dtc'
ORDER BY fm.fmeca_severity DESC NULLS LAST, e.event_time;

COMMIT;
