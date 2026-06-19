-- ⛔ SUPERSEDED (2026-06-18): este esquema (estilo WS-A, PKs text, J1939, formato largo) NO encaja con
--    la BD real de Tracker (tracker_prod: TimescaleDB, UUID, multi-tenant, obd_data ancho OBD-II).
--    Ver docs/Integracion_BD_Tracker.md para el diseño de integración correcto. No aplicar esta migración.
-- ============================================================================
-- WS-A — Migración 003: ingesta OBD/CAN + entrada/salida del ESTIMADOR.
--
-- Construye SOBRE 001 (jerarquía de activos + eventos) y 002 (vista de supervivencia).
-- Añade lo necesario para el camino de producción server-side:
--   (1) catálogo de señales OBD/CAN (espejo de src/telemetry/SignalRegistry.jl),
--   (2) lecturas crudas de telemetría (lo que publica el edge; serie de tiempo),
--   (3) DTCs activos (DM1) en vivo,
--   (4) vista `live_unit` → contrato de entrada del estimador (Estimator.LiveUnit),
--   (5) tabla `maintenance_estimate` → salida del estimador (estimate_fleet escribe aquí).
--
-- Regla rectora (igual que 001): ningún campo sin un estimador/decisión que lo consuma.
-- Diseño: telemetría en FORMATO LARGO (signal_key, value) — flexible/sparse, apto TimescaleDB.
-- Se guarda el VALOR FÍSICO decodificado (el ingestor decodifica con SignalRegistry).
-- PostgreSQL 14+. NO ejecutado aquí (sin servidor); validar con `schema/load.sh` contra la BD real.
-- ============================================================================

BEGIN;

-- ----- (1) Catálogo de señales OBD/CAN (autodescribe la BD; sincronizable desde SignalRegistry) -----
CREATE TABLE IF NOT EXISTS signal_catalog (
    signal_key      text PRIMARY KEY,                 -- 'spn:110', 'pid:0x05' (clave estable)
    protocol        diag_protocol NOT NULL,           -- 'j1939' | 'obd2'
    code            integer NOT NULL,                 -- SPN (J1939) o PID (OBD-II)
    pgn             integer,                          -- PGN J1939 (NULL para OBD-II)
    name            text NOT NULL,                    -- 'Engine Coolant Temperature'
    unit            text NOT NULL,                    -- 'degC', 'kPa', 'rpm', ...
    component_type  text,                             -- componente PdM asociado (NULL = operativa)
    is_precursor    boolean NOT NULL DEFAULT false,   -- ¿señal precursora de falla? (alimenta CBM)
    verified        boolean NOT NULL DEFAULT false    -- layout confirmado (true) vs a-confirmar
);

-- ----- (2) Lecturas crudas de telemetría (serie de tiempo; lo que el edge sube) -----
CREATE TABLE IF NOT EXISTS telemetry_reading (
    vehicle_id  text NOT NULL REFERENCES vehicle,
    ts          timestamptz NOT NULL,
    signal_key  text NOT NULL REFERENCES signal_catalog,
    value       double precision,                     -- valor físico decodificado (NULL = no-disp./error)
    quality     smallint NOT NULL DEFAULT 0,          -- 0 ok; >0 flags (dropout, fuera de rango, stale)
    PRIMARY KEY (vehicle_id, ts, signal_key)
);
-- "última lectura por (vehículo, señal)" — clave para construir live_unit y CBM:
CREATE INDEX IF NOT EXISTS telemetry_latest_idx
    ON telemetry_reading (vehicle_id, signal_key, ts DESC);

-- ----- (3) DTCs activos (DM1) ingeridos del edge -----
CREATE TABLE IF NOT EXISTS dtc_event (
    vehicle_id        text NOT NULL REFERENCES vehicle,
    ts                timestamptz NOT NULL,
    spn               integer NOT NULL,
    fmi               integer NOT NULL,
    occurrence_count  smallint,
    PRIMARY KEY (vehicle_id, ts, spn, fmi)
);

-- TimescaleDB opcional para las dos series de tiempo (igual patrón que usage_snapshot en 001).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
        CREATE EXTENSION IF NOT EXISTS timescaledb;
        PERFORM create_hypertable('telemetry_reading', 'ts', if_not_exists => TRUE, migrate_data => TRUE);
        PERFORM create_hypertable('dtc_event',         'ts', if_not_exists => TRUE, migrate_data => TRUE);
    END IF;
END $$;

-- ----- (4) Vista live_unit → contrato de ENTRADA del estimador (Estimator.LiveUnit) -----
-- Cada instancia VIVA (removal_time IS NULL) con su clase/marca/severidad, edad actual en horas-motor
-- y la última lectura del precursor de su componente. El job batch hace: SELECT * FROM live_unit.
CREATE OR REPLACE VIEW live_unit AS
WITH precursor_sig AS (   -- la señal precursora por componente (una; la marcada is_precursor)
    SELECT DISTINCT ON (component_type) component_type, signal_key
    FROM signal_catalog WHERE is_precursor AND component_type IS NOT NULL
    ORDER BY component_type, verified DESC
),
latest_reading AS (       -- última lectura de cada señal por vehículo
    SELECT DISTINCT ON (vehicle_id, signal_key) vehicle_id, signal_key, value
    FROM telemetry_reading WHERE value IS NOT NULL
    ORDER BY vehicle_id, signal_key, ts DESC
),
latest_usage AS (         -- horas-motor actuales del vehículo
    SELECT DISTINCT ON (vehicle_id) vehicle_id, engine_h
    FROM usage_snapshot ORDER BY vehicle_id, ts DESC
)
SELECT
    ci.instance_id,
    p.component_type,
    v.class,
    v.brand,
    v.route_severity,
    -- edad actual de la pieza (horas-motor desde su instalación):
    COALESCE(lu.engine_h, 0) - COALESCE(ci.install_engine_h, 0)  AS current_age_h,
    lr.value                                                     AS precursor_reading
FROM component_instance ci
JOIN position p           ON p.position_id = ci.position_id
JOIN vehicle  v           ON v.vehicle_id  = p.vehicle_id
LEFT JOIN latest_usage lu ON lu.vehicle_id = v.vehicle_id
LEFT JOIN precursor_sig ps ON ps.component_type = p.component_type
LEFT JOIN latest_reading lr ON lr.vehicle_id = v.vehicle_id AND lr.signal_key = ps.signal_key
WHERE ci.removal_time IS NULL;   -- solo piezas vivas (necesitan decisión)

-- ----- (5) Salida del estimador: lo que estimate_fleet escribe por corrida batch -----
CREATE TABLE IF NOT EXISTS maintenance_estimate (
    estimate_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    run_id               text NOT NULL,                       -- id de la corrida (un job batch)
    run_ts               timestamptz NOT NULL DEFAULT now(),
    instance_id          bigint NOT NULL REFERENCES component_instance,
    component_type       text NOT NULL,
    current_age_h        numeric,
    rul_h                numeric NOT NULL,                    -- vida remanente esperada
    beta                 numeric,
    beta_lo              numeric,                             -- IC inferior de β (gobierna IFR)
    eta                  numeric,                             -- η condicional de la unidad
    optimal_interval_h   numeric,                             -- T* (NULL si IFR rehúsa preventivo)
    recommend_preventive boolean NOT NULL,
    recommend_at_age_h   numeric,                             -- edad de la pieza a la que intervenir
    cbm_alarm            boolean NOT NULL,                    -- ¿precursor cruzó el umbral físico?
    rationale            text
);
CREATE INDEX IF NOT EXISTS estimate_instance_idx ON maintenance_estimate (instance_id, run_ts DESC);
CREATE INDEX IF NOT EXISTS estimate_run_idx      ON maintenance_estimate (run_id);

-- ----- Modos de falla de los 8 componentes añadidos (mode_id 5–12; DTC de DamageModels) -----
INSERT INTO failure_mode (mode_id, component_type, code, description, fmeca_severity, fmeca_detection, typical_dtc) VALUES
    (5,  'cooling',     'COOL_OVERHEAT', 'sobrecalentamiento (bomba/termostato/mangueras)',     8, 3, 'SPN 110 / FMI 0'),
    (6,  'turbo',       'TURBO_WEAR',    'desgaste/coking de turbo (VGT) → derate',             7, 3, 'SPN 103 / FMI 1'),
    (7,  'egr',         'EGR_FOUL',      'fatiga térmica / ensuciamiento de válvula-cooler EGR', 7, 3, 'SPN 412 / FMI 0'),
    (8,  'fuel_system', 'FUEL_RESTRICT', 'restricción/desgaste de combustible (filtro/bomba/inyector)', 6, 3, 'SPN 94 / FMI 1'),
    (9,  'oil',         'ENGINE_WEAR',   'desgaste de motor (cojinetes/camisas) — proxy aceite', 9, 4, 'SPN 100 / FMI 1'),
    (10, 'air_system',  'AIR_PRESS_LOW', 'pérdida de presión neumática (compresor/secador)',     8, 4, 'SPN 117 / FMI 1'),
    (11, 'tire',        'TIRE_WEAR',     'desgaste/falla de neumático (estadístico; sin precursor de banda)', 7, 6, NULL),
    (12, 'wheel_end',   'HUB_BEARING',   'falla de rodamiento de cubo (estadístico; sin SPN estándar)', 9, 7, NULL)
ON CONFLICT (mode_id) DO NOTHING;

-- ----- Semilla del catálogo: señales PRECURSORAS (las que alimentan el CBM por componente) -----
-- (las señales operativas y el resto del catálogo se cargan en bloque desde SignalRegistry — ver
--  tools/dump_signal_catalog.jl, pendiente; estas 6 son las críticas para la decisión.)
INSERT INTO signal_catalog (signal_key, protocol, code, pgn, name, unit, component_type, is_precursor, verified) VALUES
    ('spn:110',  'j1939', 110, 65262, 'Engine Coolant Temperature',  'degC', 'cooling',     true, true),
    ('spn:103',  'j1939', 103, 65176, 'Turbocharger Speed',          'rpm',  'turbo',       true, false),
    ('spn:412',  'j1939', 412, 64948, 'EGR Temperature',             'degC', 'egr',         true, false),
    ('spn:94',   'j1939',  94, 65263, 'Engine Fuel Delivery Pressure','kPa', 'fuel_system', true, true),
    ('spn:100',  'j1939', 100, 65263, 'Engine Oil Pressure',         'kPa',  'oil',         true, true),
    ('spn:117',  'j1939', 117, 65198, 'Brake Primary Reservoir Pressure','kPa','air_system',true, true)
ON CONFLICT (signal_key) DO NOTHING;
-- nota: brake_pad/dpf/scr/battery (componentes originales) ya tienen su precursor en el modelo;
-- sus señales se añadirán al catálogo en el volcado completo desde SignalRegistry.

COMMIT;
