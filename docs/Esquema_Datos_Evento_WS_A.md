# WS-A — Esquema de datos de evento (las etiquetas)

**Entregable de la Fase 1 / WS-A. Ground truth estructurado para los modelos de supervivencia, recurrentes y de decisión.**
Versión 0.1 — Junio 2026

> Regla rectora: **ningún campo sin un estimador que lo consuma; ningún estimador sin los campos que su verosimilitud exige.** La §6 mapea cada campo a su consumidor. Si un campo no aparece ahí, no va en el esquema.

---

## 0. El objeto atómico: la vida de una instancia de componente

El error más común en datos de confiabilidad de flota es registrar "reparaciones" como filas de texto libre atadas al vehículo. Eso destruye la capacidad de hacer supervivencia. El objeto correcto es:

> **Instancia de componente** = una pieza física concreta (esta balata, número de parte X), instalada en una **posición** concreta (eje delantero, lado izquierdo) de un **vehículo** concreto, en una fecha concreta, y observada desde su instalación hasta su **falla** (evento) o hasta **hoy** (censura por la derecha).

De aquí salen tres entidades obligatorias y una jerarquía de eventos:

```
vehicle (unidad)
   └── position (slot físico: "freno delantero izq.")   ← aquí vive la RECURRENCIA (Kijima)
         └── component_instance (la pieza n-ésima en ese slot)  ← aquí vive la SUPERVIVENCIA
               └── event (install, inspection, failure, replace, adjust, …)  ← aquí viven las ETIQUETAS
```

- La **supervivencia** (Weibull/Cox, Partes II–III) se mide sobre `component_instance`: una vida con entrada (posible truncamiento) y salida (evento o censura).
- La **recurrencia** (sistemas reparables, Kijima, VIII.4) se mide sobre `position`: la secuencia de instancias en el mismo slot a lo largo del tiempo da los tiempos entre reemplazos.
- La **jerarquía** (VII.2: clase → marca → modelo → unidad) son covariables/niveles que cuelgan de `vehicle`.

---

## 1. Diseño: censura, truncamiento y riesgos competitivos (lo que NO se puede improvisar después)

Estos tres puntos, si no están en el esquema desde el día 1, sesgan el modelo de forma irreparable:

1. **Censura por la derecha.** La mayoría de las instancias **siguen vivas**. El esquema debe poder expresar "instalada en $t_0$, sin fallar hasta el corte de observación $T$". Status $= 0$, edad de salida $=$ uso acumulado a $T$.
2. **Truncamiento por la izquierda.** La flota se incorpora a mitad de vida de muchos componentes: una balata ya tenía 30,000 km cuando empezamos a observarla. Si se ignora, el modelo subestima la vida. Se registra `install_time`/`install_odo` (real o, si se desconoce, una **cota mínima conocida** marcada como imputada), y la verosimilitud condiciona sobre "sobrevivió hasta la edad de entrada".
3. **Riesgos competitivos.** Un componente puede fallar por varios modos, y una remoción por *otra* causa censura el modo de interés. Por eso `status` no es binario: es **0 (censurado) o el `mode_id` del modo que terminó la vida** (hazard causa-específico, Parte III).

Subtlety adicional (interval censoring del *onset*): un DTC se dispara en `event_time`, pero el cruce real del umbral ocurrió en algún punto entre la última inspección buena y la detección. Se registran `onset_lower` (último estado bueno conocido) y `onset_upper = event_time`. En Fase 1 se puede aproximar por `event_time`; el esquema ya guarda el intervalo para no perder la información.

---

## 2. Modelo de entidades (DDL — PostgreSQL + TimescaleDB)

```sql
-- ===== Vocabularios controlados (enums estables) =====
CREATE TYPE vehicle_class      AS ENUM ('heavy_truck','light_vehicle','motorcycle');
CREATE TYPE diag_protocol      AS ENUM ('j1939','obd2','none');
CREATE TYPE event_type         AS ENUM ('install','inspection','failure',
                                        'preventive_replace','corrective_replace',
                                        'adjust','clean','removal');
CREATE TYPE event_source       AS ENUM ('shop_order','dvir','auto_dtc','sensor_threshold','manual');
CREATE TYPE consent_purpose    AS ENUM ('operate','improve_models','publish');

-- ===== Jerarquía de activos =====
CREATE TABLE vehicle (
    vehicle_id        text PRIMARY KEY,                 -- id de la unidad (natural)
    class             vehicle_class NOT NULL,
    brand             text NOT NULL,
    model             text NOT NULL,
    model_year        smallint,
    gvwr_kg           numeric,                          -- separa OBD-II (<~6350) de J1939
    diagnostic_protocol diag_protocol NOT NULL,
    onboarded_at      timestamptz NOT NULL,             -- inicio de observación (truncamiento a nivel flota)
    consent_record_id bigint,                           -- FK al registro de consentimiento versionado (gobernanza §10.4)
    created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE position (                                  -- slot físico; aquí vive la recurrencia
    position_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id        text NOT NULL REFERENCES vehicle,
    component_type    text NOT NULL,                    -- 'brake_pad','tire','wheel_bearing',...
    location          text NOT NULL,                    -- 'front_left','drive_axle_right',...
    UNIQUE (vehicle_id, component_type, location)
);

CREATE TABLE component_instance (                        -- la pieza n-ésima en un slot; aquí vive la supervivencia
    instance_id       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    position_id       bigint NOT NULL REFERENCES position,
    part_number       text,
    supplier          text,
    install_time      timestamptz NOT NULL,             -- entrada (truncamiento por la izquierda)
    install_known     boolean NOT NULL DEFAULT true,    -- false = imputado (componente preexistente)
    install_odo_km    numeric,
    install_engine_h  numeric,
    removal_time      timestamptz,                       -- NULL = sigue viva (censurada)
    UNIQUE (position_id, install_time)
);

-- ===== Taxonomía de modos de falla (FK; crece, ligada a FMECA) =====
CREATE TABLE failure_mode (
    mode_id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    component_type    text NOT NULL,
    code              text NOT NULL UNIQUE,             -- 'BRK_PAD_WEAR','TIRE_TREAD_WEAR','BRG_SPALL',...
    description       text NOT NULL,
    fmeca_severity    smallint CHECK (fmeca_severity BETWEEN 1 AND 10),   -- S de RPN (VI.2)
    fmeca_detection   smallint CHECK (fmeca_detection BETWEEN 1 AND 10),  -- D de RPN
    typical_dtc       text                              -- patrón SPN/FMI o P-code asociado
);

-- ===== Eventos: la tabla de etiquetas =====
CREATE TABLE event (
    event_id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    instance_id       bigint NOT NULL REFERENCES component_instance,
    type              event_type NOT NULL,
    event_time        timestamptz NOT NULL,             -- tiempo de detección/registro
    onset_lower       timestamptz,                       -- último estado bueno conocido (interval censoring)
    onset_upper       timestamptz,                       -- = event_time normalmente
    odo_km            numeric,                            -- uso a la fecha del evento
    engine_h          numeric,
    mode_id           bigint REFERENCES failure_mode,    -- requerido si type es failure/replace y la causa se conoce
    restoration_q     numeric CHECK (restoration_q BETWEEN 0 AND 1),  -- Kijima (VIII.4): 0=as-good-as-new, 1=as-bad-as-old
    cost_parts        numeric,
    cost_labor        numeric,
    cost_towing       numeric,
    downtime_h        numeric,
    in_route          boolean,                            -- falla en ruta (dispara c_f alto, VI.1)
    cost_fine         numeric,
    root_cause        text,                               -- 'misalignment','overload',... (covariable de atribución)
    source            event_source NOT NULL,
    consent_record_id bigint,                             -- lineage de consentimiento (exclusión reproducible)
    dtc_spn           integer,                            -- provenance si vino de J1939
    dtc_fmi           integer,
    dtc_pcode         text,                               -- provenance si vino de OBD-II
    notes             text,                               -- texto libre, NO usado por modelos
    created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON event (instance_id, event_time);
CREATE INDEX ON event (mode_id);

-- ===== Snapshot de uso / feature store (hypertable de series de tiempo) =====
CREATE TABLE usage_snapshot (
    vehicle_id        text NOT NULL REFERENCES vehicle,
    ts                timestamptz NOT NULL,
    odo_km            numeric,
    engine_h          numeric,
    brake_energy_cum  numeric,   -- proxy de energía de frenado (Archard, V.1) — POR POSICIÓN si se desagrega
    rainflow_miner_cum numeric,  -- daño de fatiga acumulado (Miner, V.3) desde IMU
    route_severity    numeric,   -- severidad de ruta (pendiente, baches)
    PRIMARY KEY (vehicle_id, ts)
);
SELECT create_hypertable('usage_snapshot','ts');
```

Notas de diseño:
- `position` separada de `component_instance` es lo que permite la recurrencia: `SELECT ... FROM component_instance WHERE position_id = X ORDER BY install_time` da la secuencia Kijima.
- `usage_snapshot` es hypertable (alta frecuencia); las tablas relacionales no. El `brake_energy_cum` y `rainflow_miner_cum` son **proxies sin calibrar** (riesgo registrado en dossier §11): se guardan como features ordinales, no como medición física, hasta calibrarlos.
- `consent_record_id` en `vehicle` y en `event` permite excluir unidades de los sets de entrenamiento de forma reproducible si se retira el consentimiento (gobernanza §10.4).

---

## 3. La vista derivada que alimenta supervivencia (Cox/Weibull)

El modelo no consume las tablas crudas: consume, por cada `(component_type, mode)` modelado, una tabla de vidas con entrada, salida y status. Semántica (boceto SQL para una escala de tiempo dada; la escala —km, horas-motor, o un proxy físico— se elige por componente, Parte II/IV):

```sql
-- Ejemplo: vidas de balata delantera en escala de horas-motor, modo desgaste.
-- entry_age = uso a la entrada de observación menos uso a la instalación (truncamiento izq.)
-- exit_age  = uso a la salida (evento o censura) menos uso a la instalación
-- status    = mode_id si el evento terminal es falla de ese modo; 0 si censurado
CREATE VIEW surv_brake_pad_engineh AS
WITH term AS (   -- evento terminal de cada instancia (falla/reemplazo) o NULL si sigue viva
  SELECT DISTINCT ON (e.instance_id) e.instance_id, e.engine_h AS exit_h, e.mode_id, e.type
  FROM event e
  WHERE e.type IN ('failure','corrective_replace','preventive_replace','removal')
  ORDER BY e.instance_id, e.event_time DESC
)
SELECT
  ci.instance_id,
  v.vehicle_id, v.class, v.brand, v.model,                       -- niveles jerárquicos (VII.2)
  GREATEST(0, COALESCE(us0.engine_h,0) - ci.install_engine_h)   AS entry_age,   -- truncamiento izq.
  COALESCE(t.exit_h, us_now.engine_h) - ci.install_engine_h      AS exit_age,
  CASE WHEN t.type='failure' OR t.type='corrective_replace'
       THEN t.mode_id ELSE 0 END                                 AS status,      -- 0=censura / mode_id=falla
  rs.route_severity, /* … covariables x del Cox … */            -- covariables (III)
  ci.install_known                                               AS entry_imputed
FROM component_instance ci
JOIN position p   ON p.position_id = ci.position_id AND p.component_type='brake_pad'
JOIN vehicle v    ON v.vehicle_id  = p.vehicle_id
LEFT JOIN term t  ON t.instance_id = ci.instance_id
/* us0 = snapshot al onboarding del vehículo; us_now = último snapshot (censura); rs = severidad … */
;
```

Lo importante no es el SQL exacto (la escala y covariables cambian por componente) sino las **tres columnas que no pueden faltar**: `entry_age` (truncamiento), `exit_age`, `status` (censura/modo). Esa es la tripleta que Cox/Weibull exigen.

---

## 4. Tipos en Julia (capa de ingesta / validación)

```julia
# Espejo de las tablas para la capa de ingesta y validación (Julia-first).
using Dates

@enum VehicleClass heavy_truck light_vehicle motorcycle
@enum DiagProtocol j1939 obd2 none
@enum EventType install inspection failure preventive_replace corrective_replace adjust clean removal
@enum EventSource shop_order dvir auto_dtc sensor_threshold manual

struct Vehicle
    vehicle_id::String
    class::VehicleClass
    brand::String
    model::String
    model_year::Union{Int,Missing}
    gvwr_kg::Union{Float64,Missing}
    protocol::DiagProtocol
    onboarded_at::DateTime
    consent_record_id::Union{Int,Missing}
end

struct ComponentInstance
    instance_id::Int
    position_id::Int
    part_number::Union{String,Missing}
    install_time::DateTime
    install_known::Bool            # false ⇒ truncamiento por la izquierda con edad imputada
    install_odo_km::Union{Float64,Missing}
    install_engine_h::Union{Float64,Missing}
    removal_time::Union{DateTime,Missing}   # missing ⇒ viva (censurada)
end

struct Event
    event_id::Int
    instance_id::Int
    type::EventType
    event_time::DateTime
    onset_lower::Union{DateTime,Missing}    # interval censoring del onset
    onset_upper::Union{DateTime,Missing}
    odo_km::Union{Float64,Missing}
    engine_h::Union{Float64,Missing}
    mode_id::Union{Int,Missing}             # requerido si falla/replace con causa conocida
    restoration_q::Union{Float64,Missing}   # Kijima: 0=as-good-as-new … 1=as-bad-as-old
    cost::NamedTuple                        # (parts, labor, towing, downtime_h, in_route, fine)
    root_cause::Union{String,Missing}
    source::EventSource
    consent_record_id::Union{Int,Missing}
    dtc::NamedTuple                         # (spn, fmi, pcode) — provenance
end

# La tripleta de supervivencia que se deriva, no se captura:
struct SurvivalRecord
    instance_id::Int
    entry_age::Float64      # truncamiento por la izquierda (≥ 0)
    exit_age::Float64       # evento o censura
    status::Int             # 0 = censurado ; mode_id = falla causa-específica
    covariates::NamedTuple  # niveles jerárquicos + x del Cox
    entry_imputed::Bool
end
```

---

## 5. Vocabularios controlados (semilla)

El texto libre es veneno para supervivencia. `failure_mode` se siembra desde el FMECA (Fase 0) y se liga a J1939/OBD. Semilla mínima:

| `code` | `component_type` | descripción | `typical_dtc` |
|---|---|---|---|
| `BRK_PAD_WEAR` | brake_pad | desgaste de balata al mínimo de espesor | — |
| `BRK_PAD_CRACK` | brake_pad | fractura/desprendimiento de material | — |
| `TIRE_TREAD_WEAR` | tire | banda al mínimo legal | — |
| `TIRE_IRREGULAR` | tire | desgaste irregular (alineación/suspensión) | — |
| `BRG_SPALL` | wheel_bearing | fatiga de contacto (spalling) | — |
| `DPF_SAT` | dpf | saturación / regeneración fallida | ΔP DPF alto |
| `NOX_DRIFT` | aftertreatment | deriva de sensor NOx / derate | SPN 5246 / FMI 4 |
| `BATT_DEGRADE` | battery | caída de capacidad / arranque | — |

`event_type` y `source` ya son enums (§2). `action`/calidad de reparación se infiere de `type` + `restoration_q`: un `*_replace` ⇒ renovación (`restoration_q = 0`); un `adjust`/`clean` ⇒ imperfecto (`restoration_q ∈ (0,1)`, a estimar, VIII.4).

---

## 6. Mapa campo → estimador que lo consume (justificación de cada columna)

| Campo | Consumidor | Parte |
|---|---|---|
| `install_time/_odo/_engine_h`, `install_known` | truncamiento por la izquierda | II, III |
| `event_time`, `onset_lower/upper` | tiempo a evento; interval censoring | II, V |
| `odo_km`, `engine_h` | escala de vida por uso real (no calendario) | II, IV |
| `mode_id` (→ `status`) | hazard causa-específico / riesgos competitivos | III |
| `fmeca_severity`, `fmeca_detection` | RPN = S·O·D (priorización) | VI.2 |
| `restoration_q`, secuencia por `position` | Kijima / edad virtual / sistemas reparables | VIII.4 |
| `cost_*`, `downtime_h`, `in_route`, `cost_fine` | $c_f, c_p$ del intervalo óptimo | VI.1 |
| `class`, `brand`, `model` | niveles de la jerarquía bayesiana (pooling) | VII.2 |
| `route_severity`, `root_cause`, covariables | covariables del Cox/AFT | III, IV.5 |
| `brake_energy_cum`, `rainflow_miner_cum` | features físicas (proxy, sin calibrar) | V.1, V.3 |
| `dtc_spn/fmi/pcode`, `source`, `consent_record_id` | provenance + lineage de consentimiento | §2.1, §10.4 |

Si una columna no está en esta tabla, no debería estar en el esquema. Si un estimador necesita algo que no está aquí, falta una columna.

---

## 7. Restricciones de calidad e supuestos a resolver (lo incómodo)

El esquema es **necesario pero no suficiente**. Riesgos y decisiones abiertas que hay que cerrar con ustedes antes de ingerir a escala:

1. **El texto libre del taller.** La fuente real son órdenes de taller con odómetro inconsistente y descripción libre. El esquema obliga vocabulario, pero hay que **validar en la ingesta** (un parser/clasificador que mapee texto → `mode_id`, con cola de revisión humana para lo ambiguo). Sin esto, `mode_id` se llena de NULLs y la supervivencia causa-específica muere.
2. **Fechas de instalación desconocidas (flota preexistente).** Decisión: usar `install_known = false` con una **cota mínima** (p. ej. fecha de onboarding) y tratar la entrada como truncamiento por la izquierda con edad imputada; documentar el supuesto y hacer análisis de sensibilidad a la imputación.
3. **Onset vs detección.** Fase 1: aproximar onset por `event_time`. El intervalo `[onset_lower, onset_upper]` queda guardado para refinar a interval censoring cuando haya inspecciones regulares.
4. **Identificabilidad de `restoration_q`.** Con datos escasos, $q$ de ajustes imperfectos puede ser no identificable. Decisión por defecto: fijar $q=0$ para reemplazos (renovación) y $q$ libre solo donde haya suficientes secuencias por `position`; lo demás, prior informativo.
5. **Desagregación por posición de las features físicas.** `brake_energy_cum` ideal es por rueda/posición, no por vehículo. Si el bridge solo entrega el agregado, la atribución por posición es aproximada — registrar la limitación.
6. **Granularidad de costo.** `c_f` depende de si la falla fue en ruta; `in_route` debe poblarse de forma fiable (cruce con GPS/estado de operación), o el intervalo óptimo (VI.1) se sesga.

---

## 8. Ejemplo mínimo (ciclo de vida de una balata)

```
vehicle  TRK-014 (heavy_truck, Freightliner/Cascadia, j1939, onboarded 2026-01-10)
position 88  (TRK-014, brake_pad, front_left)
  instance 401: install 2026-01-10 (known=false, imputada), install_engine_h=4200
     event: inspection 2026-03-01, engine_h=4810, source=dvir   (estado bueno → onset_lower)
     event: failure    2026-04-12, engine_h=5060, mode=BRK_PAD_WEAR, source=auto_dtc,
            cost_parts=1800 MXN, cost_labor=900, downtime_h=3, in_route=false, q=0
  instance 402: install 2026-04-12 (known=true), install_engine_h=5060   ← recurrencia en el slot 88
     (sigue viva → censurada en el último snapshot)
```
Vidas derivadas (escala horas-motor, modo desgaste):
- instancia 401: `entry_age = 4810-4200 = 610`? No — entry al onboarding: `entry_age = max(0, engine_h(onboarding) − install_engine_h)`. Como install es imputada al onboarding, `entry_age = 0`; `exit_age = 5060−4200 = 860`; `status = BRK_PAD_WEAR`.
- instancia 402: `entry_age = 0`; `exit_age = engine_h(hoy) − 5060`; `status = 0` (censurada).

---

## 9. Decisiones para cerrar antes de implementar

1. ¿Escala de tiempo primaria por componente? (propuesta: horas-motor para motor/freno/embrague; km para neumático; ciclos/energía donde el proxy físico exista).
2. ¿Política de imputación de `install_time` para la flota preexistente, y su análisis de sensibilidad?
3. ¿El bridge entrega `brake_energy`/`rainflow` por posición o solo agregado por vehículo?
4. ¿Fuente y fiabilidad de `in_route` (cruce con GPS)?
5. ¿Quién mantiene el vocabulario `failure_mode` y cómo se versiona junto al FMECA?

Cerradas estas cinco, WS-A pasa de esquema a ingesta.
