# Integración del estimador PdM con la BD real de Tracker (`tracker_prod`)

**Propósito:** diseñar cómo el estimador (`MaintenanceSim.Estimator`, forma batch) se conecta al esquema
**real** de Tracker, en vez de imponer un esquema propio. Documento de diseño — NO toca SQL todavía.
Flota objetivo: **mixta** (ligeros OBD-II hoy; pesados J1939 a futuro). Reemplaza el enfoque de la
migración `003_obd_ingestion.sql` (estilo WS-A con PKs text/J1939), que queda **SUPERSEDED**.

Versión 1.0 — 2026-06-18. Fuente: inspección de `mech@xolotl:~/PhAIMaT/Tracker-v2/`.

---

## 1. Realidad de `tracker_prod` (lo que hay, verificado)

- **Stack:** SaaS multi-tenant, **TimescaleDB pg16**. PKs **UUID**, `tenant_id` en todo, **Row-Level
  Security** por tenant (`app.current_tenant`).
- **`vehicles`**: `id UUID, tenant_id, device_id (Orange Pi), plate_number, vin, make_model, year,
  status`. NO hay clase (pesado/ligero), NI route_severity, NI horas-motor.
- **`obd_data`** (hypertable, **formato ancho**, OBD-II SAE J1979 de **auto ligero**):
  `vehicle_speed_kmh, engine_rpm, engine_load_pct, coolant_temp_c, intake_temp_c, maf_gps,
  fuel_level_pct, fuel_pressure_kpa, fuel_rate_lph, control_module_voltage, dtc_count, mil_status,
  odometer_km (PID 01A6), distance_since_dtc_clear_km, protocol`.
- **`gps_data`** (hypertable): telemetría GPS (para derivar severidad de ruta a futuro).
- **Mantenimiento (Epic 13) YA existe:**
  - `maintenance_schedules`: intervalos configurables (`interval_km/engine_hours/days`, `alert_before_*`).
  - `maintenance_records`: historial de servicio — `maintenance_type, description, odometer_km,
    engine_hours, service_date, cost_mxn/parts/labor, provider_name`. **Sin** distinción falla/preventivo.
  - `vehicle_mileage`: 1 fila/vehículo — `odometer_km, odometer_source, engine_hours, last_updated`.
- **Vocabulario real de `maintenance_type`** (auto ligero): `oil_change, brake_pads, battery,
  coolant_flush, air_filter, fuel_filter, spark_plugs, belts, tire_rotation, transmission_fluid,
  brake_fluid, general_inspection`.

**Implicación de fondo:** la matemática del estimador (Weibull-AFT, RUL, IFR, batch) es **agnóstica al
vehículo**. Lo que debe alinearse a la realidad es (a) el **set de componentes** y (b) el **mapeo de
precursores**. El componente set Clase-8/J1939 (turbo, EGR, SCR, DPF, aire de frenos, wheel-end) se
conserva en el simulador/catálogo para el futuro pesado, pero **no aplica al auto ligero de hoy**.

---

## 2. Principio de integración: ADAPTADOR, no re-esquema

El estimador consume dos contratos: `ServiceRecord[]` (historial) y `LiveUnit` (estado actual), y
produce `MaintenanceEstimate`. La integración es un **adaptador** que:
1. Deriva esos contratos de las tablas EXISTENTES vía **vistas SQL** (sin re-esquematizar Tracker).
2. Corre el job batch en el servidor (`estimate_fleet`).
3. Escribe resultados en **una** tabla nueva (`pdm_prediction`).

El código del estimador **no cambia**. Solo se añade: un lector Julia de la BD (LibPQ), unas vistas, una
tabla de catálogo y una de salida. Todo con UUID + `tenant_id` + RLS (consistente con Tracker).

---

## 3. Mapeo tablas reales → contratos del estimador

### 3.1 `ServiceRecord` (historial de vida) ← `maintenance_records`
Cada servicio de un componente recurrente = una **renovación**. El intervalo entre servicios
consecutivos del MISMO `maintenance_type` en el MISMO vehículo = una **vida realizada**; el intervalo
abierto (desde el último servicio hasta hoy) = observación **censurada**.

- `component_type` ← mapa desde `maintenance_type` (ver §4).
- `entry_age` / `exit_age` ← **odómetro** (km) como reloj de uso: `exit_age = odo(servicio_n) −
  odo(servicio_{n−1})`; el primer intervalo desde onboarding usa truncamiento por la izquierda.
- `status` ← **falla vs preventivo** — **BRECHA** (ver §6.1); interino: tratar intervalos como vidas.
- `route_severity` (covariable AFT) ← **BRECHA** (ver §6.3); interino: ajuste pooled sin covariable.
- `class`, `brand` ← `vehicles.make_model`/`year` (parseo) — o clase única "ligero" por ahora.

Vista `pdm_survival_record` (bosquejo):
```sql
-- intervalos consecutivos por (vehicle, maintenance_type) usando odómetro como edad
WITH svc AS (
  SELECT vehicle_id, tenant_id, maintenance_type, service_date, odometer_km,
         LAG(odometer_km)  OVER w AS prev_odo,
         LAG(service_date) OVER w AS prev_date
  FROM maintenance_records
  WINDOW w AS (PARTITION BY vehicle_id, maintenance_type ORDER BY service_date)
)
SELECT ... maintenance_type AS component_type,
       (odometer_km - prev_odo) AS exit_age_km,   -- vida realizada
       1 AS status                                  -- TODO: falla vs preventivo (§6.1)
FROM svc WHERE prev_odo IS NOT NULL;
-- + filas CENSURADAS: último servicio → odómetro actual (vehicle_mileage), status=0
```

### 3.2 `LiveUnit` (estado actual) ← `vehicle_mileage` + `obd_data` + `vehicles`
Por cada (vehículo, componente) vivo:
- `current_age` ← `vehicle_mileage.odometer_km − odo(último servicio de ese tipo)`.
- `precursor_reading` ← última fila de `obd_data` en la columna del precursor del componente (§5);
  `NULL` si el componente no tiene precursor OBD (→ estadístico por intervalo).
- `class`, `brand`, `route_severity` ← como en §3.1.

Vista `pdm_live_unit` (bosquejo): join de `vehicles` × componentes-aplicables × último `maintenance_record`
× `vehicle_mileage` × última `obd_data`.

### 3.3 Salida ← tabla nueva `pdm_prediction`
`tenant_id, vehicle_id, component_type, run_id, run_ts, current_age_km, rul_km, beta, beta_lo, eta,
optimal_interval_km, recommend_preventive, recommend_at_km, cbm_alarm, rationale`. UUID PK, RLS por tenant.
Lo consume el frontend/alertas de Tracker (se integra con el `MaintenanceItemStatus` existente:
ok/upcoming/due/overdue).

---

## 4. Catálogo de componentes (mapa `maintenance_type` → modelo)

Tabla `pdm_component_catalog` (o config en código + seed): por componente, su `maintenance_type`(s),
clase aplicable, precursor (señal/columna), `has_cbm`, y parámetros del modelo (β/η/cp/cf) — estos
últimos pueden vivir en `DamageModels.COMPONENTS` (código) y refinarse con datos de la flota.

Mapeo propuesto para la flota LIGERA (vocabulario real):

| maintenance_type | componente (modelo) | precursor OBD-II | modo |
|---|---|---|---|
| `battery` | battery | `control_module_voltage` | **CBM** |
| `coolant_flush` | cooling | `coolant_temp_c` | **CBM** |
| `fuel_filter` | fuel_system | `fuel_pressure_kpa` / `fuel_rate_lph` | **CBM** |
| `air_filter` | air_filter | (MAF/carga indirecto) | intervalo |
| `brake_pads` | brake_pad | — | intervalo (km) |
| `oil_change` | oil | — (auto ligero no expone presión) | intervalo (km) |
| `spark_plugs` | spark_plugs *(nuevo)* | misfire Mode 06 (no en obd_data) | intervalo |
| `belts` | belt *(nuevo)* | — | intervalo |
| `tire_rotation` | tire | TPMS (no en OBD-II básico) | intervalo |
| `transmission_fluid` | transmission *(nuevo)* | — | intervalo |
| `brake_fluid`, `general_inspection` | (tareas, no componentes de falla) | — | — |

Componentes PESADOS (J1939) del catálogo actual (turbo, egr, scr, dpf, air_system, wheel_end) quedan
marcados `class=heavy` y `enabled=false` para la flota ligera; se activan cuando entren camiones.

---

## 5. Precursores OBD-II → columna de `obd_data` (lo realmente observable, auto ligero)

| Componente | Columna `obd_data` | Dirección de alarma |
|---|---|---|
| battery | `control_module_voltage` | baja (< ~12.2 V en reposo / arranque débil) |
| cooling | `coolant_temp_c` | sube (> umbral, p.ej. 105–110 °C) |
| fuel_system | `fuel_pressure_kpa` | baja (filtro/bomba) |

El resto (balatas, llantas, aceite, bujías, banda) **no tiene precursor en OBD-II básico** ⇒ PdM
**estadístico por intervalo de km** (Weibull sobre el odómetro), no CBM. Esto es honesto: el valor
inmediato del CBM en auto ligero está en batería, enfriamiento y combustible.

> A futuro (pesado/J1939): los SPN ricos (oil 100, EGR 412, turbo 103, aire 117…) requieren que el edge
> publique J1939. Decisión de cómo aterrizan: extender `obd_data` con columnas J1939, o una tabla
> `can_data` ancha, o formato largo `telemetry_signal`. Se decide al onboardear pesados (§6.5).

---

## 6. Brechas y decisiones a resolver (antes de implementar)

1. **Falla vs preventivo en `maintenance_records`** (crítico para supervivencia). Hoy no se distingue.
   Opciones: (a) añadir columna `is_corrective boolean` / `event_kind` a `maintenance_records` (mini-
   migración a Tracker); (b) inferir de DTC previo (`dtc_count`/`distance_since_dtc_clear_km`) o de
   `status='maintenance'` del vehículo; (c) interino: tratar todo intervalo como vida (sesga β, pero
   arranca). **Recomendado:** (a) — el dato es barato de capturar y es el más informativo.
2. **Reloj de uso = odómetro (km)** para ligeros (no hay horas-motor reales). El estimador es agnóstico
   a la unidad; el simulador usa horas-motor — alinear la documentación/unidades (km universal para
   ligeros; horas-motor para pesados si se prefiere).
3. **Covariable `route_severity`** ausente en `vehicles`. Opciones: derivar de `gps_data` (terreno/
   uso/altitud), o ajuste **pooled sin covariable** al inicio. **Recomendado:** pooled ahora; derivar de
   GPS después (mejora η por vehículo).
4. **Clase de vehículo** ausente. Añadir `vehicle_class` (o inferir de `make_model`) cuando entren
   pesados; por ahora, clase única "ligero".
5. **Aterrizaje de telemetría J1939** (pesado): diseñar al onboardear el primer camión (no ahora).
6. **`maintenance_type` ↔ componente**: confirmar el mapa de §4 con el equipo (p.ej. ¿`air_filter`
   alimenta `fuel_system` o es su propio componente?).

---

## 7. Qué NO cambia y plan de implementación

**No cambia:** el código del estimador (`fit_component`/`estimate`/`estimate_fleet`) — consume
`ServiceRecord`/`LiveUnit`. Tampoco las tablas existentes de Tracker (solo se LEEN; se añade salida).

**Se añade (cuando se apruebe este doc):**
1. Vistas `pdm_survival_record` y `pdm_live_unit` (adaptan tracker_prod → contratos).
2. Tabla `pdm_component_catalog` (mapa maintenance_type→componente, clase, precursor, params).
3. Tabla `pdm_prediction` (salida) + RLS por tenant.
4. (Opcional, recomendado) columna `is_corrective` en `maintenance_records`.
5. Lector Julia de la BD con **LibPQ** (hasta ahora evitado a propósito) en `src/io/` — `read_history`,
   `read_live_units`, `write_predictions`, y un `julia_main()` que orqueste BD→`estimate_fleet`→BD.
6. Reemplazar/retirar `schema/migrations/003_obd_ingestion.sql` (superseded) por las migraciones de arriba.

**Riesgo:** bajo — todo aditivo y de solo-lectura sobre Tracker, salvo la columna opcional `is_corrective`.
La incógnita real es la calidad/volumen del historial de `maintenance_records` para ajustar Weibull con
sentido (con poca historia, el IC de β será ancho y el IFR rehusará — comportamiento correcto y honesto).
