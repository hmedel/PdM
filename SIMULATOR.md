# Simulador de flota + algoritmo de mantenimiento predictivo (F0)

Simulación de **eventos discretos en el tiempo** de una flotilla de camiones de transporte, y el
algoritmo de mantenimiento predictivo corriendo sobre ella — **validado contra verdad conocida**.
Es la Fase F0 del [Brief](docs/Brief_ClaudeCode_Modulo_Mantenimiento.md): el corazón de la
validación antes de tocar datos reales, y el formato de datos que la plataforma Tracker consumirá.

## Qué hace (en una corrida)

```
simular flota (DES temporal) → escribir WS-A (CSV/SQL) → ajustar supervivencia →
RUL → CBM/DTC → decisión/ahorro → VALIDAR recuperación de parámetros vs verdad
```

**Simulación basada en agentes con física de falla.** Cada camión es un agente con tipo (Clase 8
sleeper/day-cab, Clase 6/7, ligero), masa en vacío y **carga variable por viaje**, asignado a un
**corredor tipo Norteamérica** (montaña / llanura / desierto / urbano / rolling). Cada día conduce
un viaje: acumula horas-motor y km, emite telemetría J1939 derivada de la física (round-trip exacto
por `J1939.jl`), y sus componentes **acumulan daño físico** (energía de frenado por pendiente·masa,
hollín por ralentí, ciclado térmico, fatiga por rugosidad). La pieza falla cuando el daño cruza un
umbral — la vida **no se postula, emerge** del corredor y de la carga. Todo produce un **flujo de
eventos ordenado en el tiempo conforme al esquema WS-A**.

**Híbrido físico-recuperable** (lo que hace esto riguroso): el umbral de falla se sortea
Weibull(β, η_ref), de modo que la vida en horas-motor es `T ~ Weibull(β, η_ref·exp(−κ·z))`, con
`z` la severidad física del corredor. Así la **forma β y la pendiente AFT γ = −κ** siguen siendo
verdad conocida y **recuperable** por un ajustador independiente — mientras la heterogeneidad de
vida (montaña vs llanura) es genuinamente física. Se obtiene realismo *y* validación por
recuperación de parámetros (Brief §1.2), sin sacrificar ninguno.

## Correr

```bash
julia run_simulation.jl                 # 200 vehículos, 730 días, semilla por defecto
julia run_simulation.jl 400 1095 42     # n_vehículos, horizonte_días, semilla
julia test/test_FleetSimulator.jl       # 40 criterios de aceptación (F0)

julia run_telemetry.jl                  # genera telemetría OBD/CAN (frames round-trip + features)
julia test/test_telemetry.jl            # 61 tests: round-trip + consistencia física
```

### Telemetría OBD/CAN (datos sintéticos con sustento real)

Generador de telemetría profesional: cada camión-agente conduce su corredor y la **micro-simulación
física por viaje** deriva señales OBD/CAN *coherentes entre sí* (RPM↔velocidad↔marcha, %carga↔
pendiente·masa, consumo↔potencia, boost/EGT/NOx↔carga, TPMS por Gay-Lussac), encodeadas como frames
J1939/OBD-II que hacen **round-trip exacto**, a cadencia telemática real con ruido y dropouts.
**Cada parámetro físico tiene origen documental** — ver [`docs/Sustento_Fisico_Telemetria.md`](docs/Sustento_Fisico_Telemetria.md)
(SAE J1939-71/J1979, EPA SmartWay, AASHTO, FMCSA §393.75, Gillespie, Garrett/Cummins). El consumo
por corredor (montaña > llanura) y la correlación pendiente↔carga (r≈0.76) **emergen** de la física.

Cargar el flujo de eventos a PostgreSQL (esquema WS-A real):

```bash
DB=maintenance ./schema/load.sh         # aplica migraciones + \copy de out/wsa/*.csv
# luego:  psql -d maintenance -c "SELECT * FROM surv_engineh LIMIT 10;"
#         psql -d maintenance -c "SELECT * FROM cbm_work_orders LIMIT 10;"
```

> Dependencias Julia: `Distributions, Optim, DataFrames, CSV, JSON3, SpecialFunctions` (ver
> `Project.toml`). PostgreSQL 14+ para la carga; TimescaleDB es opcional (la migración lo detecta).

## Lo que la simulación demuestra (resultados de la corrida por defecto)

| Componente | β real → β̂ | γ=−κ real → γ̂ | ¿Preventivo? | Lectura |
|---|---|---|---|---|
| `brake_pad` | 2.3 → 2.31 | −1.0 → −0.95 | **SÍ** | desgaste por frenado; T*≈550 h, ahorro ~50% |
| `dpf` | 2.0 → 1.92 | −0.7 → −0.76 | **SÍ** | hollín; DTC ΔP con lead time |
| `scr` | 2.6 → 2.51 | −0.6 → −0.57 | **SÍ** | derate → varado; prioridad CBM máxima |
| `battery` | 1.0 → 1.02 [0.99, 1.05] | −0.5 → −0.45 | **NO** | β≈1: falla aleatoria → **IFR rehúsa** |

La vida **emerge de la física de agentes** (corredor, terreno, carga) y aun así el ajustador
independiente recupera la forma β *y* la sensibilidad física γ=−κ. Eso es el híbrido en acción.

Las cuatro afirmaciones que hacen esto serio y no charlatanería:

1. **Recuperación de parámetros** (±5–8%) con un ajustador *independiente* del generador
   (anti-circularidad): el éxito es *recuperar* la verdad, no que coincida por construcción.
2. **Disciplina de censura/truncamiento**: la tripleta `(entry_age, exit_age, status)` se deriva,
   no se inventa; ignorarla sesga la vida característica (~−13%, demostrado en el prototipo).
3. **Regla IFR**: el preventivo se recomienda *solo* si el IC bootstrap de β excluye 1. En
   `battery` (β≈1) el motor **rehúsa** — impide vender un preventivo que no ahorra.
4. **Descompostura en ruta = el costo `c_f`**: ρ = c_f/c_p ≈ 6–9×. El predictivo convierte un
   `c_f` no planeado (grúa + downtime + multa por derate) en un `c_p` en taller, *antes* de la
   falla — pero solo donde hay desgaste.

## Arquitectura (módulos, alineados al Brief §2)

```
src/
  ingest/J1939.jl              decoder verificado (PGN/SPN/DM1) — reutilizado, no reescrito
  physics/
    RouteNetwork.jl            corredores tipo-NA (montaña/llanura/desierto/urbano/rolling) calibrados
    TruckAgent.jl              tipos de camión, masa en vacío, carga útil variable por viaje
    DamageModels.jl            física de falla + puente recuperable (reloj de daño, γ=−κ)
  telemetry/                   ← GENERADOR OBD/CAN (datos sintéticos con sustento real)
    SignalRegistry.jl          catálogo J1939 (~28 SPN) + OBD-II (~15 PID), encode/decode round-trip
    Powertrain.jl              dinámica longitudinal instantánea (RPM, carga, consumo, boost, EGT, NOx)
    TireModel.jl               desgaste de banda + TPMS (presión/temp por llanta, FMCSA + Gay-Lussac)
    TelemetrySim.jl            micro-sim por viaje → señales coherentes → frames + features a cadencia
  synthetic/FleetSimulator.jl  ← SIMULADOR agente-físico (núcleo) + encoder round-trip
  models/
    survival.jl                Weibull-AFT agrupado (η0 por grupo + β,γ) con censura+trunc., IC β
    rul.jl                     RUL condicional, forma cerrada (gamma incompleta superior)
  cbm/rules.jl                 DTC (DM1/DM2) → órdenes de trabajo por severidad FMECA (Tier-1)
  decision/optimal_interval.jl intervalo óptimo de edad + ahorro + regla de rechazo IFR
  io/wsa_writer.jl             SimOutput → CSV alineado al esquema WS-A
schema/
  migrations/001_wsa_core.sql  DDL: enums, vehicle/position/instance/event/usage_snapshot, FMECA
  migrations/002_survival_view.sql  vista surv_engineh (tripleta) + cbm_work_orders
  load.sh                      aplica migraciones + \copy
run_simulation.jl              orquestador end-to-end + reporte
test/test_FleetSimulator.jl    40 criterios de aceptación
out/                           wsa/*.csv (flujo de eventos + ground truth) + report.txt
```

## Decisiones del simulador (explícitas, no adivinadas)

Estas son decisiones de la **simulación** (no comprometen las decisiones abiertas del Brief §8,
que requieren input humano para datos reales):

- **Escala de vida primaria: horas-motor** para todos los componentes (Brief §8.1 lo deja abierto;
  aquí se fija para el sintético y se documenta).
- **`route_severity` es emergente**, no inventada: la fija el corredor asignado al agente (su
  terreno/altitud/clima/ralentí). La covariable física `z` por componente recupera γ=−κ.
- **Corredores y umbrales calibrados** a estadísticas plausibles de Norteamérica, NO a datos
  geográficos reales (decisión del usuario: arquetipos auto-contenidos, sin dependencias de red).
- **Proxies físicos** (`brake_energy_cum` = energía de descenso integrada, `rainflow_miner_cum` =
  dosis rugosidad·masa) ahora se computan de la física real, pero siguen siendo **índices ordinales
  SIN calibrar** — etiquetados como tales; no se usan como medición física hasta tener ground truth.
- **Aftertreatment**: SPN 3251 (ΔP DPF) y 5246 (derate SCR) verificados; el *layout PGN* sigue con
  `pgn=0` en `J1939.jl` hasta confirmar contra DBC (no inventar).

## Próximos pasos (hacia Tracker)

- **F4 jerárquico** (`models/hierarchical.jl`, Turing.jl): el sesgo del modelo de un solo η0 (que
  el simulador ya exhibe) motiva el *partial pooling* — una marca data-pobre mejora su RUL.
- **F5 recurrencia explícita** (Kijima `q`) y calculadora de ahorro como servicio.
- **Ingesta real**: el edge Python publica los mismos frames J1939; el esquema WS-A no cambia.
- **Cerrar las decisiones abiertas del Brief §8** con el equipo antes de ingerir a escala.
