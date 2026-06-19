# Módulo de Mantenimiento Predictivo — Paquete de diseño e implementación de referencia

Contexto completo del módulo de mantenimiento predictivo para la plataforma Tracker (flota MDVR + telemetría). Diseño investigado y derivado, código verificado, y una implementación de referencia ejecutable. Pensado para trabajarse con **Claude Code / Cowork** sobre el repositorio de Tracker.

---

## Punto de entrada

**Empieza por `docs/Brief_ClaudeCode_Modulo_Mantenimiento.md`.** Es el contrato de trabajo: principios no negociables, arquitectura de módulos, orden de construcción por fases (F0–F5) con criterios de aceptación, y las decisiones abiertas que requieren input humano (no adivinar).

> **¿Quieres correrlo ya?** La Fase **F0 está implementada y validada** en Julia:
> un **simulador de eventos de flota en el tiempo** + el algoritmo end-to-end. Ver
> **[`SIMULATOR.md`](SIMULATOR.md)** y `julia run_simulation.jl`.

---

## Estructura

```
docs/      Diseño y derivaciones (leer en este orden)
  Brief_ClaudeCode_Modulo_Mantenimiento.md   <- ENTRY POINT (qué construir y en qué orden)
  Investigacion_Mantenimiento_Predictivo_Flota.md   <- la idea del proyecto (dossier)
  Fundamentos_Matematicos_Mantenimiento_Predictivo.md   <- toda la matemática, desde 1os principios
  Esquema_Datos_Evento_WS_A.md   <- el contrato de datos (las etiquetas)
  Especificacion_Adquisicion_Datos.md   <- qué señal alimenta cada modelo (J1939/OBD/IMU)
  Estudio_Ahorro_Mantenimiento_Predictivo.md   <- el caso económico (cuánto y bajo qué condición)
  Mapa_Trabajo_Estimacion_Online.md   <- plan del motor de estimación online
  Auditoria_Critica_y_Evaluacion_Publicacion.md   <- auditoría de corrección + veredicto de publicación
  Referencias_Mantenimiento_Predictivo.md   <- bibliografía maestra (A–P)

src/                          # implementación Julia (F0 ejecutada y validada)
  ingest/J1939.jl             <- decoder J1939 VERIFICADO (PGN/PDU1-2, señal LE, DM1/DM2)
  physics/                    <- RouteNetwork, TruckAgent, DamageModels (corredores, masas, leyes de daño)
  telemetry/                  <- SignalRegistry, Powertrain, TireModel, Diagnostics, TelemetrySim (generador OBD/CAN standalone)
  synthetic/FleetSimulator.jl <- motor agente-físico (eventos WS-A + telemetría desde el reloj de daño)
  sim/                        <- life_process (sustrato Dcum/Θ) + precursor (fuente única f→señal)
  models/                     <- survival (Weibull-AFT agrupado + bootstrap), rul (forma cerrada)
  decision/                   <- optimal_interval (T*, regla IFR), policy (políticas + CBM honesto), economics (VPN/EUAC)
  cbm/rules.jl                <- reglas CBM/DTC
  io/wsa_writer.jl            <- materialización a CSV WS-A (cargable a Postgres)
  reference_python/           <- implementación de referencia (validación cruzada, no es el camino de producción)

schema/                       migraciones SQL WS-A + load.sh
test/                         # 131 criterios verdes: FleetSimulator 40 · telemetría 61 · economía 18 · J1939 12
  test_FleetSimulator.jl, test_telemetry.jl, test_economics.jl, test_J1939.jl

context/   Contexto original de hardware/red (Orange Pi Zero 3, Headscale)
_archive/  Versiones antiguas/duplicadas (no usar; conservadas por trazabilidad)
```

---

## Cómo correr la implementación de referencia (Python)

Valida el lazo del producto sin necesidad de datos reales ni de Julia:

```bash
pip install numpy scipy --break-system-packages
python3 src/reference_python/maintenance_engine.py   # motor end-to-end sobre flota sintética
python3 src/reference_python/savings_model.py        # modelo de ahorro y ramp-up
python3 src/reference_python/synth_pipeline_demo.py  # recuperación de parámetros (validación)
```

El motor demuestra la disciplina clave: **prueba estadísticamente que β>1 (IC bootstrap excluye 1) antes de recomendar preventivo**; donde la falla es aleatoria (β≈1) rehúsa, como dicta el teorema IFR.

---

## Estado de validación (honesto)

- **Implementado, ejecutado y validado (Julia, F0):** simulador agente-físico (FleetSimulator), telemetría OBD/CAN con sustento documental, rutas reales Valhalla, estudio económico contrafactual y camino de decisión unificado. **131 pruebas verdes** (FleetSimulator 40 · telemetría 61 · economía 18 · J1939 12). Auditoría técnica de 3 agentes aplicada (ver `docs/Auditoria_Tecnica.md`).
- **Validación cruzada (Python de referencia):** decoder/encoder J1939, recuperación de parámetros (±5–8%), forma cerrada de la RUL, modelo de ahorro, motor end-to-end.
- **Stubs/caveats declarados:** reensamblado TP/BAM de J1939-21 (DM1 con >1 DTC); layouts de SPN a confirmar contra DBC/J1939-71; defaults de demo vs producción en `survival.jl` (NelderMead→LBFGS, nboot≥500).
- **Error encontrado y corregido en la auditoría:** supervivencia del proceso Gamma (Fundamentos IV.2), gamma incompleta inferior vs superior.

---

## Decisiones abiertas (requieren input humano — ver Brief §8)

Escala de tiempo por componente; imputación de `install_time`; `brake_energy`/`rainflow` por posición vs agregado; fuente de `in_route` y de asignación de conductor; DBC por OEM (licenciar vs incremental) y SPN exacto de NOx; disponibilidad de peso por eje (SPN 178/179).

---

## Stack

Julia (modelado/producción: Distributions, Survival, Turing, DifferentialEquations) · Python (edge + referencia) · PostgreSQL + TimescaleDB.

*Paquete generado para handoff a Claude Code / Cowork. La matemática central está auditada; los riesgos restantes son insumos sin verificar y código Julia no ejecutado, ambos cerrables mecánicamente.*
