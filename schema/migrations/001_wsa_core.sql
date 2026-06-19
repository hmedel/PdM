-- ============================================================================
-- WS-A — Esquema de datos de evento del módulo de mantenimiento predictivo.
-- Migración 001: vocabularios, jerarquía de activos, modos de falla, eventos, uso.
--
-- Espejo ejecutable de docs/Esquema_Datos_Evento_WS_A.md §2. Diseñado para
-- PostgreSQL 14+. TimescaleDB es OPCIONAL: la hypertable de usage_snapshot se crea
-- solo si la extensión está disponible (ver bloque DO al final).
--
-- Regla rectora: ningún campo sin un estimador que lo consuma (ver §6 del doc).
-- ============================================================================

BEGIN;

-- ----- Vocabularios controlados (enums estables) -----
DO $$ BEGIN
  CREATE TYPE vehicle_class   AS ENUM ('heavy_truck','light_vehicle','motorcycle');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE diag_protocol   AS ENUM ('j1939','obd2','none');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE event_type      AS ENUM ('install','inspection','failure',
                                       'preventive_replace','corrective_replace',
                                       'adjust','clean','removal','auto_dtc');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  CREATE TYPE event_source    AS ENUM ('shop_order','dvir','auto_dtc','sensor_threshold','manual');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ----- Jerarquía de activos -----
CREATE TABLE IF NOT EXISTS vehicle (
    vehicle_id          text PRIMARY KEY,
    class               vehicle_class NOT NULL,
    brand               text NOT NULL,
    model               text NOT NULL,
    model_year          smallint,
    gvwr_kg             numeric,
    diagnostic_protocol diag_protocol NOT NULL,
    onboarded_at        date NOT NULL,              -- inicio de observación (truncamiento a nivel flota)
    route_severity      numeric,                    -- covariable x ∈ [0,1] (perfil de operación)
    hours_per_day       numeric,
    created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS position (               -- slot físico; aquí vive la recurrencia (Kijima)
    position_id     bigint PRIMARY KEY,
    vehicle_id      text NOT NULL REFERENCES vehicle,
    component_type  text NOT NULL,
    location        text NOT NULL,
    UNIQUE (vehicle_id, component_type, location)
);

CREATE TABLE IF NOT EXISTS component_instance (     -- la pieza n-ésima en un slot; aquí vive la supervivencia
    instance_id     bigint PRIMARY KEY,
    position_id     bigint NOT NULL REFERENCES position,
    part_number     text,
    supplier        text,
    install_time    date NOT NULL,                  -- entrada (truncamiento por la izquierda)
    install_known   boolean NOT NULL DEFAULT true,  -- false = imputado (componente preexistente)
    install_engine_h numeric,
    removal_time    date                            -- NULL = sigue viva (censurada)
);

-- ----- Taxonomía de modos de falla (FMECA) -----
CREATE TABLE IF NOT EXISTS failure_mode (
    mode_id         bigint PRIMARY KEY,
    component_type  text NOT NULL,
    code            text NOT NULL UNIQUE,
    description     text NOT NULL,
    fmeca_severity  smallint CHECK (fmeca_severity BETWEEN 1 AND 10),
    fmeca_detection smallint CHECK (fmeca_detection BETWEEN 1 AND 10),
    typical_dtc     text
);

-- ----- Eventos: la tabla de etiquetas -----
CREATE TABLE IF NOT EXISTS event (
    event_id        bigint PRIMARY KEY,
    instance_id     bigint NOT NULL REFERENCES component_instance,
    type            event_type NOT NULL,
    event_time      date NOT NULL,
    onset_lower     date,                           -- último estado bueno conocido (interval censoring)
    onset_upper     date,                           -- = event_time normalmente
    engine_h        numeric,
    odo_km          numeric,
    mode_id         bigint REFERENCES failure_mode,
    restoration_q   numeric CHECK (restoration_q BETWEEN 0 AND 1),  -- Kijima: 0=as-good-as-new
    cost_parts      numeric,
    cost_labor      numeric,
    cost_towing     numeric,                        -- premium de falla EN RUTA
    downtime_h      numeric,
    in_route        boolean,                        -- falla en ruta (dispara c_f alto, VI.1)
    cost_fine       numeric,
    source          event_source NOT NULL,
    dtc_spn         integer,
    dtc_fmi         integer,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS event_instance_time_idx ON event (instance_id, event_time);
CREATE INDEX IF NOT EXISTS event_mode_idx          ON event (mode_id);
CREATE INDEX IF NOT EXISTS event_dtc_idx           ON event (dtc_spn, dtc_fmi) WHERE type = 'auto_dtc';

-- ----- Snapshot de uso / feature store (serie de tiempo) -----
CREATE TABLE IF NOT EXISTS usage_snapshot (
    vehicle_id          text NOT NULL REFERENCES vehicle,
    ts                  date NOT NULL,
    engine_h            numeric,
    odo_km              numeric,
    brake_energy_cum    numeric,   -- PROXY ordinal sin calibrar (Archard) — NO es medición física
    rainflow_miner_cum  numeric,   -- PROXY ordinal sin calibrar (Miner) — NO es medición física
    route_severity      numeric,
    PRIMARY KEY (vehicle_id, ts)
);

-- TimescaleDB opcional: convertir a hypertable solo si la extensión existe.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'timescaledb') THEN
        CREATE EXTENSION IF NOT EXISTS timescaledb;
        PERFORM create_hypertable('usage_snapshot', 'ts', if_not_exists => TRUE, migrate_data => TRUE);
    END IF;
END $$;

-- ----- Semilla de modos de falla (ligada al FMECA y a J1939) -----
INSERT INTO failure_mode (mode_id, component_type, code, description, fmeca_severity, fmeca_detection, typical_dtc) VALUES
    (1, 'brake_pad', 'BRK_PAD_WEAR', 'desgaste de balata al mínimo de espesor',                 6, 4, NULL),
    (2, 'dpf',       'DPF_SAT',      'saturación / regeneración fallida del DPF',                6, 3, 'SPN 3251 / FMI 16'),
    (3, 'scr',       'NOX_DRIFT',    'deriva NOx / derate SCR — unidad puede quedar varada',     9, 2, 'SPN 5246 / FMI 4'),
    (4, 'battery',   'BATT_DEGRADE', 'caída de capacidad / falla de arranque (aleatoria, β≈1)',  5, 6, NULL)
ON CONFLICT (mode_id) DO NOTHING;

COMMIT;
