# Empaquetado como librería Julia + compilación a binario standalone

**Objetivo:** (A) convertir el código en una **librería Julia cargable** (`using MaintenanceSim`), y
(B) **compilarla a un ejecutable autónomo** que corra **sin levantar Julia** (deploy en el edge / en
cualquier máquina). Este documento es el plan ejecutable; no se ejecuta aquí por presupuesto de contexto.

Versión 1.0 — Junio 2026.

---

## ESTADO: Paso A COMPLETADO + split simulador/estimador (2026-06-18)

- **Librería cargable HECHA**: `src/MaintenanceSim.jl` (paraguas, incluye los 19 submódulos una vez en
  orden topológico). Los 3 submódulos con deps (`FleetSimulator`, `LifeProcess`, `TelemetrySim`) pasaron
  de `include` ad-hoc a `using ..Modulo`. Los 7 scripts + 4 tests cargan el paquete; `test/runtests.jl`
  agregado. **131 pruebas verdes** + 7 scripts exit 0. `include("src/MaintenanceSim.jl"); using .MaintenanceSim`.
- **Split en TRES fachadas** (decisión del usuario: un repo, 3 módulos + core):
  - `MaintenanceSim.Core` — contrato compartido (J1939/SignalRegistry/Precursors: señal + mapa degradación↔señal).
  - `MaintenanceSim.Estimator` — EL ESTIMADOR de producción (Survival/RUL/Decision/CBM + `estimator/api.jl`).
    Lo llama la API. Contrato: `estimate_maintenance(history::ServiceRecord[], unit::LiveUnit; cp, cf)
    -> MaintenanceEstimate{rul, β, β_lo, η, T*, recommend_preventive, recommend_at_age, cbm_alarm, rationale}`.
  - `MaintenanceSim.Simulator` — EL SIMULADOR (banco de pruebas): física + LifeProcess + telemetría +
    Policy/Economics. Genera datos con verdad conocida para CALAR el estimador.
  - Mismo contrato real (BD) o simulado → el simulador valida el estimador. Demo: `run_estimator_demo.jl`
    (recupera β y decide por componente; battery rehúsa preventivo por IFR). Verificado: β̂≈verdad ±, IFR OK.
- **Pendiente** (Paso B): `julia_main()` + subcomandos + `create_app` (binario sin Julia); `juliac` núcleo.

---

## 0. Estado actual (original — referencia)

- Ya existe `Project.toml` con `name = "MaintenanceSim"`, `version = "0.1.0"` y deps
  (CSV, DataFrames, Distributions, JSON3, Optim, SpecialFunctions). Julia **1.12** instalado (soporta `juliac`).
- Los módulos hoy se cargan con `include(joinpath(@__DIR__, ".."...))` **ad-hoc** y cada uno re-incluye
  sus dependencias (p. ej. `FleetSimulator` incluye `J1939`, `RouteNetwork`, …). Esto funciona para
  scripts, pero **no es un paquete**: re-incluir el mismo archivo desde dos módulos crea módulos
  duplicados / redefiniciones. **Refactor previo necesario** (Paso A.2).

Módulos (orden de dependencia): `J1939` → `RouteNetwork`, `TruckAgent` → `DamageModels` →
`Powertrain`, `TireModel`, `SignalRegistry` → `Diagnostics`, `Precursors` → `FleetSimulator`,
`LifeProcess` → `Survival`, `RUL` → `Decision` → `Policy` → `Economics` → `WSAWriter`, `TelemetrySim`.

---

## A. Librería Julia cargable (`using MaintenanceSim`)

**A.1 — Crear el módulo paraguas** `src/MaintenanceSim.jl`:
```julia
module MaintenanceSim
# incluir CADA submódulo UNA sola vez, en orden de dependencia:
include("ingest/J1939.jl");            using .J1939
include("physics/RouteNetwork.jl");    using .RouteNetwork
include("physics/TruckAgent.jl");      using .TruckAgent
include("physics/DamageModels.jl");    using .DamageModels
include("telemetry/SignalRegistry.jl");using .SignalRegistry
include("telemetry/Powertrain.jl");    using .Powertrain
include("telemetry/TireModel.jl");     using .TireModel
include("telemetry/Diagnostics.jl");   using .Diagnostics
include("sim/precursor.jl");           using .Precursors
include("synthetic/FleetSimulator.jl");using .FleetSimulator
include("sim/life_process.jl");        using .LifeProcess
include("models/survival.jl");         using .Survival
include("models/rul.jl");              using .RUL
include("decision/optimal_interval.jl");using .Decision
include("decision/policy.jl");         using .Policy
include("decision/economics.jl");      using .Economics
include("io/wsa_writer.jl");           using .WSAWriter
include("telemetry/TelemetrySim.jl");  using .TelemetrySim
# re-exportar la API pública (generate_life_processes, simulate_fleet, run_economics, …)
export simulate_fleet, generate_life_processes, fit_grouped, decide, run_economics, ...
end
```

**A.2 — Refactor de los `include` (el trabajo real):** quitar de CADA submódulo los
`include(joinpath(@__DIR__, ".."...))` de sus dependencias y reemplazar por `using ..OtroModulo`
(referencia al módulo hermano dentro del paquete). Ejemplo: `FleetSimulator.jl` hoy hace
`include(".../J1939.jl"); using .J1939` → debe ser `using ..J1939`. Igual en `Powertrain` (usa
`..SignalRegistry`), `LifeProcess`, `TelemetrySim`, `run_economics.jl`, etc. Es mecánico pero toca
~10 archivos; hacer en rama y validar que las 131 pruebas pasen.

**A.3 — Tests del paquete:** mover `test/*.jl` a usar `using MaintenanceSim` en vez de `include`s;
crear `test/runtests.jl` que corra todas las suites. Luego `Pkg.test("MaintenanceSim")`.

**A.4 — Instalar localmente:** `Pkg.develop(path=".")` o `Pkg.add(url=...)`; `using MaintenanceSim`.

Resultado: `using MaintenanceSim; out = simulate_fleet(...)` desde cualquier proyecto Julia.

---

## B. Compilación para el SERVIDOR (job batch sobre la BD) — NO edge

> **Objetivo corregido (decisión 2026-06-18):** el estimador corre en el **servidor de Tracker**,
> consume la **BD** y procesa a **toda la flota** en una pasada (batch), para quitarle cómputo al edge.
> "Compilado" = eliminar la latencia de arranque/JIT de Julia para que el job corra rápido sobre miles
> de unidades. En un servidor el tamaño del bundle NO importa; importa el tiempo a-primer-resultado.

### B.1 — PackageCompiler.jl → `create_app` (CAMINO ELEGIDO)
Empaqueta el **runtime de Julia + el código precompilado** en un bundle de ~150–400 MB que arranca
rápido (imagen precompilada). Ideal para un servicio/cron en el server.
```julia
using PackageCompiler
create_app(".", "build/PdMEstimatorApp"; precompile_execution_file="precompile_run.jl")
```
Requiere `julia_main()::Cint` (en `MaintenanceSim`) que: (1) conecte a la BD, (2) lea historiales por
tipo de componente + unidades vivas, (3) `Estimator.estimate_fleet(...)` sobre toda la flota,
(4) escriba resultados (RUL / fecha de mantenimiento / veredicto) de vuelta a la BD. `precompile_run.jl`
debe ejercitar ese camino para precompilarlo.

### B.2 — Sysimage (alternativa si ya hay Julia en el server)
`create_sysimage` acelera el arranque pero requiere Julia instalado — válido si el server ya lo tiene
(servicio Julia de larga vida o sysimage para cron). Más simple que `create_app`.

### ~~B.3 — `juliac` binario chico para edge~~ (DESCARTADO)
El binario AOT pequeño de `juliac` era para embeber en el edge (Orange Pi). Como el cómputo es 100%
server-side, ya no aplica. Se conserva la nota solo como referencia histórica.

**Nota de rendimiento (clave para "toda la BD"):** el `Estimator` debe ajustar el modelo Weibull-AFT
**una vez por tipo de componente** (`fit_component`) y luego **evaluar cada unidad barato** (`estimate`).
NO re-ajustar por unidad. `estimate_fleet` orquesta: agrupa registros por componente, ajusta N modelos,
evalúa M unidades. Así el server procesa miles de unidades en milisegundos tras el ajuste.

---

## C. Recomendación y checklist

**Plan:** (1) Paso A (librería) — HECHO; habilita `using MaintenanceSim`. (2) API batch del estimador
(`fit_component`/`estimate`/`estimate_fleet`) + ingesta de la BD. (3) `create_app` en el **servidor** para
el job batch sobre toda la flota (sin edge).

Checklist:
- [x] A.1 `src/MaintenanceSim.jl` (módulo paraguas, orden de deps).
- [x] A.2 Refactor de `include`→`using ..Modulo`; 131 pruebas verdes.
- [x] A.3 `test/runtests.jl` (`Pkg.test` listo).
- [x] Split en fachadas Core/Estimator/Simulator + `estimator/api.jl` + `run_estimator_demo.jl`.
- [x] Estimator batch: `fit_component(history)->ComponentModel` + `estimate(model,unit)` + `estimate_fleet(history,units,costs)`.
      Ajuste 1× por componente (~805 ms/modelo, nboot=50); evaluación ~21 µs/unidad (T* reescalado por η,
      exacto en Weibull). Demo `run_estimator_demo.jl`; tests `test/test_estimator.jl` (16). 145 verdes.
- [x] Ingesta BD: adaptador puro `MaintenanceSim.TrackerAdapter` (`run_estimates`) + runner LibPQ. (commit 7321a4d)
- [x] B.1 `julia_main()` + estructura `create_app`: paquete-app `apps/PdMBatchApp` (módulo con `julia_main`/
      `run_batch`, deps LibPQ/Tables/UUIDs + MaintenanceSim por `[sources]`), `compile/build_app.jl` +
      `compile/precompile_app.jl`. App carga como paquete y falla limpio sin `TRACKER_DB_URL`. Compilar:
      `julia compile/build_app.jl` (en el server con red; binario en `build/PdMBatchApp/bin/`).
- [x] B.2 Sysimage del estimador: `compile/build_sysimage.jl` + `compile/precompile_estimator.jl` →
      `build/MaintenanceSim.so` (mata la latencia JIT del fit Weibull). Correr: `julia -Jbuild/MaintenanceSim.so …`.

**Fixes necesarios para empaquetar (descubiertos al compilar):** el `Project.toml` del paquete carecía de
`uuid` y de los stdlibs (`Random`/`Printf`/`Dates`/`LinearAlgebra`/`Statistics`) que los submódulos `using` —
funcionaba vía `include` pero NO como paquete instalado. Añadidos. En Apple Silicon, `cpu_target="generic"`
rompe (`LLVM ERROR aese`); el build usa target nativo por defecto y `ENV["PDM_CPU_TARGET"]` para el server x86-64.

**Riesgo:** A.2 (hecho) tocó includes con pruebas; validado 131 verdes. El resto es aditivo.

**Por qué importa:** una librería cargable + app compilada permite (a) integrar el motor en la plataforma
Tracker sin copiar scripts, (b) correr el estimador en el **servidor** sobre toda la flota de la BD con
arranque rápido (cómputo fuera del edge), (c) versionar y testear como paquete.
