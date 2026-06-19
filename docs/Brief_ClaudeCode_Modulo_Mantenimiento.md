# Brief para Claude Code — Módulo de Mantenimiento Predictivo en Tracker

**Destino:** repositorio de la plataforma Tracker (donde corre Traccar + PostgreSQL + edge Orange Pi).
**Objetivo de este brief:** que Claude Code construya el módulo de mantenimiento predictivo, **empezando por el generador de datos sintéticos** y validando todo contra verdad conocida antes de tocar datos reales.
**Stack:** Julia para el modelado/generador (preferente), Python para captura en el edge, PostgreSQL + TimescaleDB para almacenamiento.

> Este brief es un contrato de trabajo, no una sugerencia. Las secciones "Principios" y "Qué NO hacer" tienen precedencia sobre cualquier impulso de "completar" el sistema. Ante una decisión de diseño no resuelta (ver §8), **pregunta — no inventes**.

---

## 0. Contexto (documentos de referencia)

El diseño ya está investigado y derivado. Claude Code debe leerlos antes de codificar, y tratarlos como fuente de verdad:

- `Investigacion_Mantenimiento_Predictivo_Flota.md` — dossier técnico (arquitectura, física de falla, gobernanza).
- `Fundamentos_Matematicos_Mantenimiento_Predictivo.md` — derivaciones (supervivencia, Weibull/Cox, Wiener/Gamma, jerarquía bayesiana, estimación online, Apéndice B geometría/espectro).
- `Esquema_Datos_Evento_WS_A.md` — esquema de datos de evento (las etiquetas). **Es el contrato de datos.**
- `Especificacion_Adquisicion_Datos.md` — qué señal alimenta cada modelo y el veredicto de disponibilidad (A/P/M/B).
- `Estudio_Ahorro_Mantenimiento_Predictivo.md` + `savings_model.py` — modelo de ahorro (reactivo vs preventivo vs predictivo); base de `decision/optimal_interval.jl`.
- `J1939.jl` + `test_J1939.jl` — **decoder J1939 ya verificado.** Reutilizar, no reescribir.

---

## 1. Principios (no negociables)

1. **Datos primero.** El cuello de botella es dato e identificabilidad, no método. No construir maquinaria de modelado avanzada antes de que el generador sintético y el esquema de datos estén sólidos.
2. **Validar por recuperación de parámetros, no por "corre".** Todo modelo se valida generando datos con verdad conocida y verificando que la recupera dentro de IC. El generador y el ajuste deben formar un loop de recuperación.
3. **Censura y truncamiento por la izquierda son ciudadanos de primera clase.** La tripleta `(entry_age, exit_age, status)` es obligatoria. Ignorarlos sesga (demostrado: ~−13% en vida característica al ignorar censura).
4. **No hardcodear layouts de SPN de memoria.** El diccionario de señales se carga de un DBC/J1939-71 autoritativo (`load_registry!`). La semilla de `J1939.jl` lleva aftertreatment con `pgn=0` a propósito.
5. **Los proxies físicos (energía de frenado, fatiga rainflow) son índices ordinales SIN calibrar.** No presentarlos como medición física hasta tener ground truth. Etiquetarlos como tales en el código y la UI.
6. **Supervisado vs no supervisado.** "Qué es lo más importante en mantenimiento" lo responde el hazard (Cox) + FMECA + costo, no PCA/Koopman/geometría (que son EDA/verificación).
7. **Prioridad Tier-1.** El primer producto alimentable sin calibración es CBM/lifing sobre **J1939 en camión pesado** (aftertreatment, motor, batería, DTC). Construir eso antes que la física-proxy y mucho antes que lo bloqueado por hardware.
8. **TDA está descartado** del plan activo (bloqueado por hardware de baja frecuencia). No introducirlo.

---

## 2. Arquitectura de módulos (dentro de Tracker)

```
maintenance/
├── synthetic/        # ← EMPEZAR AQUÍ. Generador de flota sintética (mímica de la realidad).
│   ├── SyntheticFleet.jl
│   └── test_SyntheticFleet.jl
├── ingest/
│   ├── J1939.jl              # decoder verificado (ya existe) + TP/BAM (TODO)
│   ├── obd2.jl              # decoder OBD-II (request-response; soporte de PID variable)
│   └── edge_contract.md      # features on-edge (rainflow, energía de frenado) — ver Especificacion §5
├── schema/
│   └── migrations/           # DDL Postgres/TimescaleDB del esquema WS-A
├── features/
│   ├── usage_clock.jl        # horas-motor/km por componente (escala de vida real)
│   ├── brake_energy.jl       # proxy Archard (ORDINAL, sin calibrar)
│   └── rainflow.jl           # daño Miner desde IMU (ORDINAL, sin calibrar)
├── models/
│   ├── survival.jl           # Weibull/Cox con censura + truncamiento
│   ├── hierarchical.jl       # partial pooling clase→marca→modelo→unidad (Turing.jl)
│   ├── recurrent.jl          # Kijima / edad virtual (q)
│   └── rul.jl                # RUL condicional + buffer
├── cbm/
│   └── rules.jl              # DTC (DM1/DM2) + umbrales OEM → órdenes de trabajo (Tier-1)
├── decision/
│   └── optimal_interval.jl   # intervalo óptimo de costo (c_f, c_p) + calculadora de ahorro (1-1/ρ; no preventivo si β≤1)
└── governance/
    └── consent.jl            # registro de consentimiento versionado + lineage (exclusión reproducible)
```

---

## 3. Orden de construcción (fases, cada una con criterio de aceptación)

| Fase | Entregable | Criterio de aceptación (test que debe pasar) |
|---|---|---|
| **F0 — Generador sintético** ← **AHORA** | `SyntheticFleet.jl`: flota heterogénea, perfiles de operación, frames J1939 que round-trip por `J1939.jl`, vidas por modelo forward, eventos WS-A con censura/truncamiento/recurrencia, DTCs | (a) round-trip encode→decode exacto; (b) el estimador **bien especificado** (η0 por (clase,marca) + β,γ compartidos) recupera la verdad dentro de ±5–6% (validado); (c) mostrar que el ajuste de **un solo η0** sesga β,γ — motivación empírica de F4 |
| **F1 — Esquema** | DDL Postgres/TimescaleDB del esquema WS-A | el generador escribe eventos válidos; la vista de supervivencia produce `(entry_age,exit_age,status)` |
| **F2 — CBM/DTC (Tier-1)** | `cbm/rules.jl`: DM1 → alerta → orden de trabajo; umbrales OEM | sobre sintético, un DTC inyectado (SPN 5246/3251) dispara orden; sin falsos en operación normal |
| **F3 — Lifing estadístico** | `survival.jl` + `rul.jl`: Weibull/Cox por componente, RUL con buffer | recuperación de parámetros; RUL calibrado (cobertura del IC) |
| **F4 — Jerárquico** | `hierarchical.jl` (Turing.jl): partial pooling | una marca data-pobre mejora su RUL vía pooling vs standalone (probar el diferenciador) |
| **F5 — Recurrencia + decisión** | `recurrent.jl` (Kijima q) + `optimal_interval.jl` (incluye **calculadora de ahorro**: $C_{\text{rtf}}$, $C^\star$, techo $1-1/\rho$; port de `savings_model.py`) | recuperar `q`; intervalo óptimo minimiza costo esperado simulado; el ahorro reportado coincide con el modelo del estudio |

No avanzar de fase sin que pase el criterio de aceptación de la anterior.

---

## 4. El generador sintético (F0) — especificación

Es el corazón de la validación. Debe **mimetizar la realidad**, no producir datos limpios de juguete.

Debe generar:
- **Flota jerárquica:** clases (heavy_truck, light_vehicle, motorcycle), marcas y modelos, con parámetros de vida ground-truth por `(clase, marca, componente)` — para luego probar el pooling.
- **Perfiles de operación** por vehículo: ciclo de servicio (carretera/ciudad/montaña) → `route_severity`; tasa de acumulación de horas-motor/km; protocolo (`j1939` pesado, `obd2` ligero — **el ligero entrega menos señales**, mímica de la brecha real).
- **Telemetría J1939/OBD** como frames CAN reales (id + 8 bytes) que round-trip por `J1939.jl`: al menos HOURS (SPN 247), EEC1 (190), ET1 (110); reducido en OBD. Con ruido de sensor y dropouts ocasionales.
- **Vidas de componente** por modelo forward **independiente** (Weibull-AFT con `route_severity` como covariable; acumulador Archard para frenos; Miner para fatiga). Varios componentes por vehículo.
- **Eventos WS-A** (install, inspection, failure, *_replace) conformes al esquema, con: censura (ventana de observación), truncamiento por la izquierda (fracción onboarded a mitad de vida), recurrencia por `position` (Kijima, `q=0` para reemplazo).
- **DTCs (DM1)** emitidos antes/al momento de ciertas fallas (p. ej. aftertreatment SPN 3251/5246) → ejercita el camino `auto_dtc` de etiquetas.
- **Ground truth exportable** (los parámetros verdaderos) para el loop de recuperación.

**Anti-circularidad (crítico):** el modelo forward del generador y el modelo de ajuste deben ser *implementaciones independientes*. El éxito es recuperar los parámetros del generador con el ajustador, no que "coincidan por construcción".

Una versión inicial (`SyntheticFleet.jl`) acompaña este brief; Claude Code la extiende según §3.

---

## 5. Componentes ya verificados (reutilizar)

- **`J1939.jl`**: decode de PGN/SA (PDU1/PDU2), señal little-endian con escala/offset y manejo NA/error, unpack DM1/DM2 (v4). Núcleo cross-validado (7 vectores). `test_J1939.jl` debe seguir pasando.
- **Encoder** (en `SyntheticFleet.jl`): inverso exacto del decoder, round-trip verificado para HOURS/EEC1/ET1.
- **Modelo forward de supervivencia + ajuste**: Weibull-AFT con censura + truncamiento, recuperación de `(β,η0,γ)` demostrada (ver el prototipo Python `synth_pipeline_demo.py`).

---

## 6. Contratos de datos

- **Esquema WS-A** (`Esquema_Datos_Evento_WS_A.md`): `vehicle → position → component_instance → event`; tripleta de supervivencia derivada; vocabularios controlados; mapa campo→estimador.
- **Contrato del edge** (`Especificacion_Adquisicion_Datos.md §5`): el edge emite features, no señal cruda; rainflow se cuenta en el borde; presupuesto ~40–50 MB/mes no-video.

---

## 7. Qué NO hacer

- No inventar layouts/PGN de SPN; cargar de DBC. (Aftertreatment va con `pgn=0` hasta confirmar.)
- No presentar proxies sin calibrar (frenos, fatiga) como medición física.
- No introducir TDA ni métodos pesados (POMDP, deep nets) antes de F3–F4; no son el cuello de botella.
- No tratar censurado como falla ni ignorar truncamiento.
- No streaming continuo de video ni de IMU por LTE; features on-edge.
- No resolver por cuenta propia las decisiones abiertas (§8); preguntar.

---

## 8. Decisiones abiertas (requieren input humano — NO adivinar)

1. Escala de tiempo primaria por componente (propuesta: horas-motor en pesado, km en ligero).
2. Política de imputación de `install_time` para flota preexistente (+ análisis de sensibilidad).
3. ¿El bridge entrega `brake_energy`/`rainflow` por posición o agregado por vehículo?
4. Fuente de `in_route` (cruce con GPS) y de asignación de conductor.
5. DBC por OEM: licenciar vs construir incremental; SPN exacto de NOx (rango 3200s) a confirmar.
6. ¿`SPN 178/179` (peso por eje) disponible en la flota objetivo? Define masa medida vs asumida para Archard.

---

## 9. Stack y dependencias

- **Julia:** `Distributions.jl`, `Survival.jl` (Weibull/Cox), `Turing.jl` (jerárquico bayesiano), `DifferentialEquations.jl` (degradación PoF), `MLJ.jl` (RF/boosting baseline). `Test` para los criterios de aceptación.
- **Python (edge):** captura J1939/OBD, extracción de features on-edge, MQTT.
- **DB:** PostgreSQL + TimescaleDB (hypertables para series; tablas relacionales para activos/eventos).
