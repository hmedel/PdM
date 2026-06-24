-- ============================================================================
-- Migración 004 — Integración del estimador PdM con `tracker_prod` (ADAPTADOR).
--
-- Supersede el enfoque de 003_obd_ingestion.sql (esquema WS-A propio). En vez de
-- re-esquematizar Tracker, este script LEE las tablas reales (vehicles, obd_data,
-- maintenance_records, vehicle_mileage) vía vistas que derivan los contratos del
-- estimador (ServiceRecord / LiveUnit), y AÑADE solo: un catálogo, una tabla de
-- salida y (recomendado) una columna `is_corrective`. Diseño: docs/Integracion_BD_Tracker.md.
--
-- ✅ SUPUESTOS CONFIRMADOS contra el DDL real de tracker_prod (modelos SQLAlchemy
--    en ~/PhAIMaT/Tracker-v2/vps-central/api-core/app/models, verificado 2026-06-23):
--   A1. Columna de tiempo de la hypertable `obd_data` = `timestamp` (NO `time`). CORREGIDO abajo.
--   A2. `maintenance_records(vehicle_id, tenant_id, maintenance_type, service_date,
--        odometer_km, engine_hours, ...)`  — exacto. ✓
--   A3. `vehicle_mileage(vehicle_id, odometer_km, engine_hours, last_updated)` — ✓.
--        Matiz: NO tiene `tenant_id` (vehicle_mileage es 1 fila/vehículo); este SQL no lo usa.
--   A4. `vehicles(id, tenant_id, make_model, year, status, ...)` — ✓. Novedad (Epic 12): ya
--        existen `vehicle_category`/`sct_classification` → en el futuro sustituir el 'light' fijo.
--   A5. RLS por `current_setting('app.current_tenant', true)` comparando como TEXT, con bypass
--        `super_admin`, igual que el resto de Tracker (init-db.sql). NO castear a ::uuid (revienta
--        con contexto vacío ''). CORREGIDO abajo.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. (Recomendado, §6.1) Distinguir falla vs preventivo en el historial.
--    Sin esto, el ajuste Weibull no puede separar fallas de reemplazos planeados
--    (sesga β/η). Aditivo y barato; NULL = desconocido (interino: se trata como vida).
-- ----------------------------------------------------------------------------
ALTER TABLE maintenance_records
    ADD COLUMN IF NOT EXISTS is_corrective boolean;   -- TRUE=falla, FALSE=preventivo, NULL=desconocido

COMMENT ON COLUMN maintenance_records.is_corrective IS
    'PdM: TRUE si el servicio fue correctivo (falla); FALSE si preventivo; NULL desconocido.';

-- ----------------------------------------------------------------------------
-- 1. Catálogo: mapa maintenance_type → componente del modelo, clase, precursor, costos.
--    Los parámetros de vida (β/η) viven en el código (DamageModels) y se refinan con datos;
--    aquí van el mapeo, el modo (CBM vs intervalo) y los costos cp/cf por defecto.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pdm_component_catalog (
    maintenance_type text PRIMARY KEY,            -- vocabulario real de maintenance_records
    component_type   text NOT NULL,               -- nombre del modelo (DamageModels)
    vehicle_class    text NOT NULL DEFAULT 'light' CHECK (vehicle_class IN ('light','heavy')),
    precursor_column text,                         -- columna de obd_data (NULL = sin CBM)
    alarm_direction  text CHECK (alarm_direction IN ('low','high')),  -- dirección hacia la falla
    has_cbm          boolean NOT NULL DEFAULT false,
    enabled          boolean NOT NULL DEFAULT true,
    clock            text NOT NULL DEFAULT 'odometer_km',  -- reloj de uso (km para ligeros)
    cp_mxn           numeric,                      -- costo preventivo por defecto (refinable por flota)
    cf_mxn           numeric                       -- costo correctivo por defecto
);

-- Seed para flota LIGERA (vocabulario real OBD-II; ver docs/Integracion_BD_Tracker.md §4-§5).
INSERT INTO pdm_component_catalog
    (maintenance_type, component_type, precursor_column, alarm_direction, has_cbm, enabled, cp_mxn, cf_mxn)
VALUES
    ('battery',        'battery',     'control_module_voltage', 'low',  true,  true,  2500,  6000),
    ('coolant_flush',  'cooling',     'coolant_temp_c',         'high', true,  true,  1800,  9000),
    ('fuel_filter',    'fuel_system', 'fuel_pressure_kpa',      'low',  true,  true,  1500,  7000),
    ('air_filter',     'air_filter',   NULL,                    NULL,   false, true,   600,  2500),
    ('brake_pads',     'brake_pad',    NULL,                    NULL,   false, true,  2200,  8000),
    ('oil_change',     'oil',          NULL,                    NULL,   false, true,  1200, 15000),
    ('spark_plugs',    'spark_plugs',  NULL,                    NULL,   false, true,  1500,  5000),
    ('belts',          'belt',         NULL,                    NULL,   false, true,  1800,  9000),
    ('tire_rotation',  'tire',         NULL,                    NULL,   false, true,  1000,  6000),
    ('transmission_fluid', 'transmission', NULL,                NULL,   false, true,  3000, 40000)
    -- brake_fluid, general_inspection = tareas, no componentes de falla → no se siembran.
ON CONFLICT (maintenance_type) DO NOTHING;

-- Seed PESADO/J1939 — extensión v1.1 (input de experto 2026-06-23; ver docs/Componentes_PdM_Extension.md §2).
-- enabled=false e INERTE: la flota viva es ligera OBD-II; estos modos son de camión pesado (freno de
-- aire, drivetrain) y se activan al onboardear J1939 (confirmar maintenance_type real y SPN entonces).
-- Nota: fuel_injectors/fuel_pump TAMBIÉN aplican a ligero con CBM vía OBD (fuel-trim/fuel_pressure);
-- para activarlos en ligero hay que extender el CASE de pdm_live_unit y una fuente de precursor/DTC.
INSERT INTO pdm_component_catalog
    (maintenance_type, component_type, vehicle_class, precursor_column, alarm_direction, has_cbm, enabled, cp_mxn, cf_mxn)
VALUES
    ('air_relay_valve',   'air_distribution_valve', 'heavy', NULL,              NULL,  false, false,  900,  9000),
    ('wheel_studs',       'wheel_stud',             'heavy', NULL,              NULL,  false, false,  300, 30000),
    ('brake_chamber',     'brake_chamber',          'heavy', NULL,              NULL,  false, false,  700,  6000),
    ('fuel_injectors',    'fuel_injector',          'heavy', 'fuel_pressure_kpa','low', true,  false, 1500,  7000),
    ('fuel_pump',         'fuel_pump',              'heavy', 'fuel_pressure_kpa','low', true,  false, 1200,  6000),
    ('differential_service','differential',         'heavy', NULL,              NULL,  false, false, 4000, 35000)
ON CONFLICT (maintenance_type) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2. Salida: predicciones del estimador (lo que consume el frontend/alertas de Tracker).
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pdm_prediction (
    id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           uuid NOT NULL,
    vehicle_id          uuid NOT NULL,
    component_type      text NOT NULL,
    run_id              uuid NOT NULL,             -- agrupa una corrida batch
    run_ts              timestamptz NOT NULL DEFAULT now(),
    current_age_km      double precision,
    rul_km              double precision,          -- vida remanente esperada
    beta                double precision,
    beta_lo             double precision,          -- IC inferior de β (gobierna IFR)
    eta                 double precision,
    optimal_interval_km double precision,          -- T* (NULL si IFR rehúsa preventivo)
    recommend_preventive boolean,
    recommend_at_km     double precision,
    cbm_alarm           boolean,
    rationale           text
);
CREATE INDEX IF NOT EXISTS pdm_prediction_lookup
    ON pdm_prediction (tenant_id, vehicle_id, component_type, run_ts DESC);

-- ----------------------------------------------------------------------------
-- 3. Vista: ServiceRecord ← maintenance_records (intervalos consecutivos por odómetro).
--    Cada par de servicios consecutivos del MISMO maintenance_type = una vida realizada.
--    El intervalo abierto (último servicio → odómetro actual) = censura por la derecha.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW pdm_survival_record AS
WITH svc AS (
    SELECT mr.vehicle_id, mr.tenant_id, mr.maintenance_type, mr.service_date,
           mr.odometer_km, mr.is_corrective,
           LAG(mr.odometer_km) OVER w AS prev_odo
    FROM maintenance_records mr
    WINDOW w AS (PARTITION BY mr.vehicle_id, mr.maintenance_type ORDER BY mr.service_date)  -- [A2]
),
closed AS (   -- vidas realizadas: servicio_{n-1} → servicio_n
    SELECT s.tenant_id, s.vehicle_id, c.component_type,
           (s.odometer_km - s.prev_odo)::double precision AS exit_age_km,
           -- falla=1 (status>0); preventivo=0 (censurado). NULL desconocido → 1 interino (§6.1).
           CASE WHEN COALESCE(s.is_corrective, true) THEN 1 ELSE 0 END AS status
    FROM svc s
    JOIN pdm_component_catalog c ON c.maintenance_type = s.maintenance_type AND c.enabled
    WHERE s.prev_odo IS NOT NULL AND s.odometer_km > s.prev_odo
),
last_svc AS (   -- último servicio por (vehicle, maintenance_type)
    SELECT DISTINCT ON (vehicle_id, maintenance_type)
           vehicle_id, tenant_id, maintenance_type, odometer_km AS last_odo
    FROM maintenance_records
    ORDER BY vehicle_id, maintenance_type, service_date DESC      -- [A2]
),
censored AS (   -- cola abierta: último servicio → odómetro actual (vida en curso)
    SELECT ls.tenant_id, ls.vehicle_id, c.component_type,
           GREATEST(0, vm.odometer_km - ls.last_odo)::double precision AS exit_age_km,
           0 AS status
    FROM last_svc ls
    JOIN pdm_component_catalog c ON c.maintenance_type = ls.maintenance_type AND c.enabled
    JOIN vehicle_mileage vm ON vm.vehicle_id = ls.vehicle_id      -- [A3]
    WHERE vm.odometer_km > ls.last_odo
)
SELECT tenant_id, vehicle_id, component_type,
       'light'::text AS class,                    -- §6.4 interino: clase única
       'generic'::text AS brand,                  -- §3.1 interino: pooled (refinar con make_model)
       0.0::double precision AS route_severity,   -- §6.3 interino: pooled sin covariable
       0.0::double precision AS entry_age_km,     -- cada servicio renueva el componente (sin trunc.)
       exit_age_km, status
FROM (SELECT * FROM closed UNION ALL SELECT * FROM censored) u
WHERE exit_age_km > 0;

-- ----------------------------------------------------------------------------
-- 4. Vista: LiveUnit ← vehicles × catálogo × vehicle_mileage × última obd_data.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE VIEW pdm_live_unit AS
WITH last_svc AS (
    SELECT DISTINCT ON (vehicle_id, maintenance_type)
           vehicle_id, maintenance_type, odometer_km AS last_odo
    FROM maintenance_records
    ORDER BY vehicle_id, maintenance_type, service_date DESC      -- [A2]
),
last_obd AS (   -- última telemetría por vehículo (columnas de precursor)
    SELECT DISTINCT ON (vehicle_id)
           vehicle_id, control_module_voltage, coolant_temp_c, fuel_pressure_kpa
    FROM obd_data
    ORDER BY vehicle_id, timestamp DESC                           -- [A1] columna de tiempo (confirmada: `timestamp`)
)
SELECT
    v.tenant_id, v.id AS vehicle_id, c.component_type,
    'light'::text AS class,
    'generic'::text AS brand,
    0.0::double precision AS route_severity,
    GREATEST(0, COALESCE(vm.odometer_km, 0) - COALESCE(ls.last_odo, 0))::double precision AS current_age_km,
    CASE c.component_type      -- precursor real por componente (§5); NULL = sin CBM
        WHEN 'battery'     THEN lo.control_module_voltage
        WHEN 'cooling'     THEN lo.coolant_temp_c
        WHEN 'fuel_system' THEN lo.fuel_pressure_kpa
        ELSE NULL END AS precursor_reading
FROM vehicles v                                                   -- [A4]
CROSS JOIN pdm_component_catalog c
LEFT JOIN last_svc ls       ON ls.vehicle_id = v.id AND ls.maintenance_type = c.maintenance_type
LEFT JOIN vehicle_mileage vm ON vm.vehicle_id = v.id             -- [A3]
LEFT JOIN last_obd lo       ON lo.vehicle_id = v.id
WHERE c.enabled AND c.vehicle_class = 'light';

-- ----------------------------------------------------------------------------
-- 5. Row-Level Security por tenant. [A5] Idioma idéntico al resto de Tracker
--    (init-db.sql): comparar tenant_id::TEXT contra el setting (NO ::uuid, que revienta con
--    contexto vacío '') y permitir el bypass de super_admin. FOR ALL ⇒ el USING vale también
--    como WITH CHECK del INSERT (el batch fija app.current_tenant y escribe filas de ese tenant).
-- ----------------------------------------------------------------------------
ALTER TABLE pdm_prediction ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pdm_prediction_tenant ON pdm_prediction;
CREATE POLICY pdm_prediction_tenant ON pdm_prediction
    FOR ALL USING (
        tenant_id::TEXT = current_setting('app.current_tenant', true)
        OR current_setting('app.user_role', true) = 'super_admin'
    );

ALTER TABLE pdm_component_catalog ENABLE ROW LEVEL SECURITY;       -- catálogo global (sin tenant): lectura libre
DROP POLICY IF EXISTS pdm_catalog_read ON pdm_component_catalog;
CREATE POLICY pdm_catalog_read ON pdm_component_catalog FOR SELECT USING (true);

COMMIT;
