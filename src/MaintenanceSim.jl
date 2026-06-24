"""
    MaintenanceSim

Módulo paraguas del sistema de mantenimiento predictivo de flota (Tracker). Carga CADA submódulo
**una sola vez** en orden de dependencia, de modo que las referencias internas `using ..Modulo`
(p. ej. `FleetSimulator` → `J1939`, `TelemetrySim` → `Powertrain`) resuelven contra este paquete.

Uso como librería:
```julia
include("src/MaintenanceSim.jl"); using .MaintenanceSim
using .MaintenanceSim.LifeProcess        # trae generate_life_processes, LifeConfig, …
lives, truth, vehlives = generate_life_processes(LifeProcess.LifeConfig(n_vehicles=120))
```
o, instalado como paquete (`Pkg.develop(path=".")`): `using MaintenanceSim`.

Dos capas (ver docs/Arquitectura_Unificada_Merge.md):
  - **Decisión/economía**: `LifeProcess` (sustrato Dcum/Θ) + `Precursors` (f→señal) + `Survival`/`RUL`/
    `Decision`/`Policy`/`Economics`. Camino canónico, un solo reloj de daño.
  - **Generación de telemetría standalone**: `TelemetrySim` + `Diagnostics` (showcase + rutas Valhalla).
"""
module MaintenanceSim

# --- Submódulos, incluidos UNA vez en orden de dependencia ----------------------------------------
# base sin dependencias entre sí
include("ingest/J1939.jl");              using .J1939
include("physics/RouteNetwork.jl");      using .RouteNetwork
include("physics/TruckAgent.jl");        using .TruckAgent
include("physics/DamageModels.jl");      using .DamageModels
include("telemetry/SignalRegistry.jl");  using .SignalRegistry
include("telemetry/Powertrain.jl");      using .Powertrain        # → SignalRegistry
include("telemetry/TireModel.jl");       using .TireModel
include("telemetry/Diagnostics.jl");     using .Diagnostics
include("sim/precursor.jl");             using .Precursors
# dependientes
include("synthetic/FleetSimulator.jl");  using .FleetSimulator    # → J1939, RouteNetwork, TruckAgent, DamageModels
include("sim/life_process.jl");          using .LifeProcess       # → RouteNetwork, TruckAgent, DamageModels
include("models/survival.jl");           using .Survival
include("models/rul.jl");                using .RUL
include("decision/optimal_interval.jl"); using .Decision
include("decision/policy.jl");           using .Policy
include("decision/economics.jl");        using .Economics
include("io/wsa_writer.jl");             using .WSAWriter
include("io/oil_sample.jl");             using .OilSample        # contrato off-board de análisis de aceite
include("telemetry/TelemetrySim.jl");    using .TelemetrySim      # → RouteNetwork, TruckAgent, SignalRegistry, Powertrain, TireModel, Diagnostics
include("cbm/rules.jl");                 using .CBM
include("analytics/analytics.jl");       using .Analytics   # → Survival, RUL, Decision, Precursors, Economics, …

# --- Handles de submódulos re-exportados (acceso como MaintenanceSim.X o `using MaintenanceSim`) ---
export J1939, RouteNetwork, TruckAgent, DamageModels, SignalRegistry, Powertrain, TireModel,
       Diagnostics, Precursors, FleetSimulator, LifeProcess, Survival, RUL, Decision, Policy,
       Economics, WSAWriter, OilSample, TelemetrySim, CBM, Analytics

# --- API pública de alto nivel re-exportada por conveniencia --------------------------------------
export simulate_fleet, generate_life_processes, fit_grouped, run_economics

# ============================================================================
# FACHADAS — dos productos sobre un contrato común (split simulador ↔ estimador).
#   using .MaintenanceSim.Estimator   → estima cuándo hacer mantenimiento (consume BD); va en la API.
#   using .MaintenanceSim.Simulator   → genera datos sintéticos para CALAR el estimador.
#   using .MaintenanceSim.Core        → contrato compartido (señal + mapa degradación↔señal).
# Los módulos hoja siguen accesibles directamente (MaintenanceSim.Survival, etc.).
# ============================================================================

"Contrato compartido: decodificación de señal (J1939/OBD) + mapa físico degradación↔señal."
module Core
    using ..J1939, ..SignalRegistry, ..Precursors
    export encode_pgn, decode_pgn, reading, alarm_fraction, sensor_cv, precursor_units,
           PRECURSOR_INFO, PInfo
end

"EL ESTIMADOR (producción): ajusta la vida, calcula RUL y decide cuándo intervenir. Lo llama la API."
module Estimator
    using Random
    using ..Survival, ..RUL, ..Decision, ..CBM, ..Precursors
    include("estimator/api.jl")
    export estimate_maintenance, estimate_fleet, fit_component, estimate, ComponentModel,
           ServiceRecord, LiveUnit, MaintenanceEstimate, crossed_alarm,
           fit_grouped, mean_residual_life, conditional_eta, decide, DecisionResult, GroupedFit
end

"ADAPTADOR BD↔estimador (producción): mapeo puro fila→contrato + orquestación batch. SIN LibPQ (vive en el runner)."
module TrackerAdapter
    using Random
    using ..Estimator: ServiceRecord, LiveUnit, MaintenanceEstimate, ComponentModel, fit_component, estimate
    include("io/tracker_adapter.jl")
    export to_service_record, to_live_unit, to_costs, to_prediction_row, run_estimates
end

"EL SIMULADOR (banco de pruebas): genera eventos + telemetría con verdad conocida para calar el estimador."
module Simulator
    using ..FleetSimulator, ..LifeProcess, ..TelemetrySim, ..Powertrain, ..TireModel,
          ..Diagnostics, ..RouteNetwork, ..TruckAgent, ..DamageModels, ..WSAWriter,
          ..Policy, ..Economics, ..SignalRegistry, ..Precursors
    export simulate_fleet, SimConfig, generate_life_processes, LifeConfig, generate_showcase,
           simulate_segments, run_economics
end

export Core, Estimator, Simulator, TrackerAdapter

end # module MaintenanceSim
