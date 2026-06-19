# Arquitectura unificada — plan de merge de los dos generadores

**Objetivo:** que el MISMO estado de daño de cada vehículo produzca *simultáneamente* su telemetría
J1939/OBD **y** sus fallas — un solo reloj de degradación. Hoy hay dos generadores paralelos; este
documento define el estado actual, el objetivo y el plan concreto para fusionarlos (resumible si se
corta el contexto).

Versión 1.0 — Junio 2026.

---

## 1. Estado actual (dos pistas paralelas)

### Pista A — fallas + economía (`run_economics.jl`)
`LifeProcess.generate_life_processes(cfg)` → por cada `(vehículo, posición)` un `PositionLife` con:
- `cum_h[d]`: horas-motor acumuladas por día (serie del vehículo, compartida).
- `Dcum[d]`: **reloj de daño** del componente = Σ `engine_h·exp(κ_c·z_c)·ξ` (ley de `DamageModels.damage_increment`).
- `thresholds[i]`: umbrales Θ ~ Weibull(β_c, η_ref_g) pre-sorteados (uno por instancia/renovación).
- `cf_real, cp_real, in_route, downtime, pred_noise, a0_D, a0_h` (truncamiento), `z`, `eta_i`, etc.

**Falla** cuando `Dcum − D0 + a0_D ≥ Θ`. `Policy.evaluate`/`life_records` recorren esto; `Economics`
descuenta los costos. El **CBM** (`PredictiveRUL`) dispara sobre `Dcum/Θ` vía **`Precursors`** (mapa
físico) — ya congruente con la falla.

### Pista B — telemetría (`run_telemetry.jl`)
`TelemetrySim.generate_showcase`/`simulate_segments` → micro-sim por viaje: `Powertrain.instant_state`
da RPM/carga/coolant/EGT/etc. instantáneos; `Diagnostics.HealthState` (SEPARADO) evoluciona blowby∝horas,
ceniza∝combustible, balata∝brake_kj, SoH∝horas·calor → precursores J1939. Emite frames round-trip.

### Compartido
`RouteNetwork`, `TruckAgent`, `DamageModels` (κ, η_ref por componente), `Powertrain`, `TireModel`, y
**`Precursors`** (fuente única degradación→señal: `reading(comp,f)`, `alarm_fraction(comp)`).

### La incongruencia
`Dcum` (Pista A, causa las fallas) y `HealthState` (Pista B, genera telemetría) son **realizaciones
independientes con leyes distintas**. La telemetría de un camión NO refleja la degradación que causa
sus fallas. (Ya documentado en `Auditoria_Tecnica.md` §5.4 y confirmado por la auditoría de congruencia.)

### Ya hecho hacia la unificación
- `Precursors` single-source (mapa f→señal física + alarma) — `src/sim/precursor.jl`.
- CBM físico wireado a `Precursors` (la f que alarma = la f que cruza Θ).
- `FleetSimulator.jl` YA hace una simulación temporal agente-física que produce **fallas (eventos WS-A)
  desde el reloj de daño Dcum Y frames de telemetría** — es la mayor parte del simulador fusionado.

---

## 2. Arquitectura objetivo (un solo reloj)

UNA simulación por vehículo, con `LifeProcess` como **única fuente de degradación**:
- Por vehículo: tipo, marca, corredor, onboarding, serie diaria de viajes (RouteNetwork) → `cum_h`, y
  condiciones operativas por día (para Powertrain).
- Por `(componente, posición)`: `Dcum` (un reloj, ley DamageModels) + Θ ~ Weibull. Falla al cruzar Θ →
  evento + renovación (q=0, nueva Θ). Es lo que ya hace `LifeProcess`.
- **Telemetría derivada del MISMO estado**: a cadencia de registro, por componente vivo, la señal
  precursora = `Precursors.reading(comp, f)` con `f = (Dcum[d]−D0+a0_D)/Θ` (fracción de daño REAL de la
  instancia viva) + ruido de sensor; más las señales operativas (`Powertrain.instant_state`).
- **CBM** dispara sobre esa misma señal (ya lo hace).
- **Economía** consume los eventos de falla/reemplazo.
- Un entry point: `run_unified.jl` → eventos WS-A + telemetría (rows/frames) + economía, todo de UN
  sustrato `LifeProcess`.

**Resultado:** la telemetría que emite un camión y las fallas que sufre salen del mismo `Dcum/Θ`. El
precursor de un componente que va a fallar **tiende a su alarma antes del evento de falla**, por construcción.

---

## 3. Plan de merge (pasos concretos, resumible)

**Paso 1 — exponer las condiciones operativas en el sustrato.** `LifeProcess` ya guarda `cum_h` diario.
Para las señales instantáneas (RPM/carga/coolant) necesita, por día, un resumen operativo del viaje
(grade medio, velocidad, altitud, ambiente, mf). Opciones: (a) guardar un `TripSummary` por día en
`PositionLife`/un nuevo `VehicleLife`; o (b) re-derivar con la misma semilla. Recomendado: añadir un
`VehicleLife` por vehículo con la serie de `(engine_h, km, alt, ambient, grade_mean, mf)` por día (lo
que ya computa el bucle de `generate_life_processes`, hoy descartado salvo `cum_h`/`Dcum`).

**Paso 2 — `src/sim/telemetry_from_life.jl`.** Dado el sustrato (`lives` + `VehicleLife`):
- Para cada vehículo y cada día de registro: caminar las instancias por posición (igual que
  `Policy.life_records`) para saber qué instancia vive y su `f = (Dcum[d]−D0+a0_D)/Θ`.
- Señales operativas: `Powertrain.instant_state(dynspec, mass, speed, grade, alt, ambient)` con el
  resumen del día (o un sub-muestreo del viaje).
- Señales precursoras: por componente vivo, `Precursors.reading(comp, f)` + ruido de sensor (cv de
  `Precursors`). Emitir frames J1939/OBD con `SignalRegistry.encode_pgn`/`encode_obd` (round-trip).
- Devolver `rows` + `frames` (mismo formato que `TelemetrySim.TelemetryRow`/frames).

**Paso 3 — CBM ya congruente.** Sin cambio: usa `Precursors` sobre `Dcum/Θ`. La telemetría del Paso 2
usa el MISMO `Precursors` sobre el MISMO `f`. Un test de congruencia: para una instancia que falla, su
precursor (telemetría) cruza la alarma `f*` ANTES del día de falla (salvo falso negativo por ruido).

**Paso 4 — `run_unified.jl`.** Orquestador único: `generate_life_processes` → (a) WS-A events
(`Policy`/un emisor de eventos), (b) telemetría (`telemetry_from_life`), (c) economía (`run_economics`).
Una sola corrida, un solo sustrato, mismas semillas.

**Paso 5 — deprecación congruente.** `Diagnostics.HealthState` deja de ser una ley paralela: se conserva
como capa de SEÑAL pero alimentada por la `f` del reloj de daño (o se reemplaza por `Precursors`).
`TelemetrySim` o llama a `telemetry_from_life`, o se deprecia su generación paralela. Mantener
`Powertrain`/`TireModel`/`SignalRegistry` (son física compartida, correctos).

**Paso 6 — tests.** (a) Congruencia: el precursor de un componente que falla cruza su alarma antes del
evento (sobre el mismo vehículo). (b) Regresión: las 61 pruebas de telemetría — migrar a
`telemetry_from_life` o mantener `TelemetrySim` en paralelo durante la transición. (c) Round-trip de los
frames del Paso 2. (d) La economía/recuperación de β no cambia (mismo sustrato `LifeProcess`).

---

## 4. Riesgos y decisiones

- **Riesgo:** romper las 61 pruebas de telemetría. Mitigación: construir `telemetry_from_life` en paralelo,
  validar, y migrar; no borrar `TelemetrySim` hasta que pase.
- **Decisión abierta:** ¿la telemetría unificada se genera a 1/min (como hoy) muestreando el día, o a
  resumen por viaje? Recomendado: mantener la cadencia 1/min muestreando dentro del día (reusar
  `simulate_segments`, pero con la `f` del reloj de daño para los precursores).
- **Decisión abierta:** ¿`run_telemetry.jl` (showcase) se mantiene como demo, o se reemplaza por
  `run_unified.jl`? Recomendado: mantener showcase apuntando al nuevo generador.
- **No tocar:** la matemática de confiabilidad/economía (auditada y correcta); `Precursors` (ya es la
  fuente única); el lazo CRN/decisión.

---

## 5. Estado para retomar (checklist)

- [x] `Precursors` single-source (mapa f→señal + alarma física).
- [x] CBM físico wireado a `Precursors`.
- [x] `LifeProcess` produce el reloj de daño `Dcum/Θ` por posición.
- [x] **Paso 2 (núcleo) HECHO**: `run_unified_demo.jl` deriva la telemetría de PRECURSORES de `Dcum/Θ`
      vía `Precursors` (la misma f causa la falla Y genera la señal). Congruencia medida: el precursor
      avisa antes de la falla — balata 86%, DPF 100%, SCR 33% (lead corto físico). CSV: out/unified/precursor_series.csv.
- [x] **Paso 1 HECHO**: `VehicleLife` (serie diaria engine_h/alt/ambient/mass por vehículo) en `LifeProcess`;
      `generate_life_processes` devuelve `(lives, truth, vehlives)` — retro-compatible (`lives,truth=...` sigue).
- [x] **Paso 2 (resto) HECHO**: en `run_unified_demo.jl`, señales operativas (RPM/carga/coolant/EGT vía
      `Powertrain.instant_state` sobre la serie diaria) + precursor (Dcm/Θ) del MISMO vehículo, con frames
      J1939 EEC1/ET1 round-trip ✓. Un solo sustrato → telemetría operativa + precursor + fallas.
- [x] **Paso 4 HECHO**: `run_unified.jl` — UN sustrato (semilla 7) → (A) eventos WS-A + (B) telemetría
      operativa+precursor (frames round-trip ✓) + (C) economía (break-even, ahorro VPN). Congruencia medida:
      la balata avisó antes de 5/5 fallas de la posición. La misma f=Dcm/Θ alimenta las tres salidas.
- [x] **Refinamiento HECHO**: telemetría 1/min (sección B' de `run_unified.jl`: operativa Powertrain +
      precursor por minuto con `f` interpolada del reloj de daño, round-trip ✓ → out/unified/telemetry_1min.csv).
      Camino unificado canónico: `Precursors.reading(comp, f)` con f del sustrato `LifeProcess`.
- [x] **Congruencia de capas CERRADA (Opción A, 2026-06-18)**: el rótulo "DEPRECADO / reloj paralelo"
      era engañoso — la incongruencia vivía en el camino de decisión y ya estaba resuelta. Reescrito en
      `Diagnostics.jl`/`policy.jl`/`precursor.jl`/`run_unified.jl` para reflejar la separación de capas:
      `Precursors`+`LifeProcess` = decisión; `Diagnostics`/`TelemetrySim` = generador standalone (su reloj
      propio es correcto por diseño). Sin cambio de comportamiento; 131 pruebas verdes. Receta de fusión
      (Opción B) ARCHIVADA en §6 — ver nota de decisión.

**MERGE COMPLETO**. La congruencia de decisión está cerrada y la separación de capas es explícita y
documentada. No queda deuda en este frente (retirar `HealthState` sería la Opción B, archivada).

---

## 6. RECETA EXACTA para retirar `HealthState` — ⛔ ARCHIVADA (decisión 2026-06-18)

> **DECISIÓN: NO se ejecuta esta receta.** Tras la unificación del camino de decisión (`run_unified.jl`),
> `HealthState` dejó de ser un "segundo reloj paralelo" en el sentido que la auditoría señaló: esa
> incongruencia vivía en el **camino de decisión** (CBM/economía) y ya está cerrada — ahí el precursor
> = `f = Dcum/Θ` del MISMO reloj de falla, vía `Precursors`.
>
> El `HealthState` que queda vive **solo** dentro de `TelemetrySim` (showcase + Valhalla), que es un
> **generador de telemetría standalone** — un micro-simulador autónomo sin sustrato `LifeProcess`
> detrás, pensado para volverse proyecto aparte. Su "reloj propio" ahí es **correcto por diseño**:
> genera datos OBD/CAN realistas y NO alimenta ninguna decisión. Fusionarlo (esta receta) lo acoplaría
> al substrato de decisión, contradiciendo esa separabilidad, sin ganancia de congruencia real.
>
> **En su lugar (Opción A, aplicada):** se reescribió el rótulo engañoso "DEPRECADO / reloj paralelo"
> en `Diagnostics.jl`, `policy.jl`, `precursor.jl` y `run_unified.jl` para reflejar la separación de
> capas: `Precursors`+`LifeProcess` = camino canónico de decisión; `Diagnostics`/`TelemetrySim` =
> generador de datasets. Comportamiento sin cambios; las 131 pruebas siguen verdes.
>
> La receta se conserva abajo solo como referencia por si en el futuro se decide explícitamente fusionar
> el generador en el substrato de decisión (Opción B).

`HealthState` hace 3 cosas entrelazadas que las 61 pruebas verifican: (a) heterogeneidad de flota
inicial, (b) señales NO-lifed (filtros/turbo/blowby, sin componente de falla), (c) evolución. Por eso
no es un borrado simple. Pasos exactos:

**1. [x] HECHO** — Extender `Precursors` (`src/sim/precursor.jl`) — `PInfo` añadidos para señales
no-lifed (oil_filter, fuel_filter, air_filter, crankcase, turbo); `Precursors` ya es la fuente única
COMPLETא (lifed + no-lifed). Falta solo, idealmente, añadirlas como `PhysComponent` con reloj real.
Rangos usados (alineados a `Diagnostics`):
   - `oil_filter`: new 45, fail 320, alarm 200, cv 1.0 (kPa, ΔP).
   - `fuel_filter`: new 18, fail 220, alarm 150, cv 1.0.
   - `air_filter`: new 1, fail 8, alarm 6, cv 1.0.
   - `crankcase`: new 0.3, fail 12, alarm 8, cv 1.2 (kPa, blowby).
   - `turbo`: usar el rango de turbo_rpm actual.
   (Idealmente: añadir estos como `PhysComponent` en `DamageModels.COMPONENTS` con su κ/η para que
   tengan un reloj de daño real; si no, basta el mapa f→señal para la telemetría.)

**2. Estado de daño por componente en `TelemetrySim` (reemplaza `HealthState`)** — en `VState` cambiar
   `health::HealthState` por `dmg::Dict{String,Float64}` (fracción 0..1 por señal) + un factor de
   **fragilidad/edad de flota** por vehículo (preserva la heterogeneidad: muestrear odómetro inicial
   como `initial_health`, mapear a `dmg` inicial por señal). En `generate_showcase`, inicializar
   `dmg` con la misma dispersión que `initial_health` (odo 60k–800k → dmg correlacionado con edad).

**3. Avanzar `dmg` por viaje** — en `simulate_segments`, tras el viaje: `dmg[c] += rate_c·engine_h`
   con `rate_c` calibrado a la vida típica (filtros ∝ km, blowby ∝ horas, etc.). Resetear al servicio
   (clog→0) como hoy.

**4. Señales desde `Precursors`** — reemplazar `Diagnostics.diagnostic_signals` por
   `Precursors.reading(señal, dmg[señal])` + ruido de sensor para CADA campo de `TelemetryRow`
   (crankcase, oil/fuel/air filt ΔP, brake_lining, batt_soh→cranking_v, dpf_ash, etc.). Para los
   LIFED (brake/dpf/scr/battery) usar la `f` del reloj de daño unificado.

**5. Borrar** `HealthState`, `initial_health`, `evolve_health!`, `diagnostic_signals` de
   `Diagnostics.jl` (queda solo, si acaso, un alias a `Precursors`). Quitar `using .Diagnostics` y la
   inicialización de salud en `TelemetrySim`/`run_valhalla_demo.jl`.

**6. Migrar las 61 pruebas** (`test/test_telemetry.jl`):
   - El testset "estado de salud — evolución e inicial" llama `initial_health`/`evolve_health!` por
     nombre → reescribir contra el nuevo `dmg`/fragilidad (o eliminar y cubrir con un test de `dmg`).
   - "Precursores PdM + heterogeneidad": las aserciones de rango (crankcase 0–12, oil_filt 40–320,
     batt_soh 0.15–1, brake_lining 0.5–20, cranking_v 9–13.5) deben seguir cumpliéndose con los rangos
     de `Precursors` del paso 1 — calibrar `PInfo` para que coincidan. La heterogeneidad
     (`cor(odo, crankcase) > 0.3`) se preserva si `dmg` inicial correlaciona con el odómetro de flota.

**Validación**: `julia test/test_telemetry.jl` (61) + `julia run_telemetry.jl` (round-trip) + comparar
el dataset showcase antes/después (rangos físicos iguales). El resto de suites no se toca.

**Riesgo**: medio (modifica código con pruebas). Hacer en rama, validar las 61, no borrar `HealthState`
hasta que pasen. Tiempo estimado: 1 sesión con presupuesto completo.
- [x] ~~Paso 5: deprecar `HealthState` paralelo.~~ → Resuelto vía Opción A (separación de capas explícita).
- [x] ~~Paso 6: tests de congruencia + migración de telemetría.~~ → Innecesario: el generador queda standalone (Opción B archivada).

Archivos clave: `src/sim/life_process.jl`, `src/sim/precursor.jl`, `src/telemetry/{TelemetrySim,Powertrain,Diagnostics,SignalRegistry}.jl`, `src/decision/policy.jl`, `run_economics.jl`.
