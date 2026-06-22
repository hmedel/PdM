#!/usr/bin/env julia
# ============================================================================
# run_pdm_batch.jl — Shim de DEV para correr el job batch PdM SIN compilar.
#
# La lógica (BD → estimate → BD) vive en el paquete-app `apps/PdMBatchApp` (compilable a binario
# standalone con `create_app`; ver compile/build_app.jl). Este shim solo activa ese entorno y corre.
# El mapeo/estimación es puro y vive en `MaintenanceSim.TrackerAdapter` (test/test_tracker_adapter.jl).
#
#   TRACKER_DB_URL=postgresql://user:pass@host:5432/tracker_prod  julia run_pdm_batch.jl
# (requiere el entorno apps/PdMBatchApp instanciado: LibPQ, Tables, UUIDs, MaintenanceSim por path.)
# ============================================================================
import Pkg
Pkg.activate(joinpath(@__DIR__, "apps", "PdMBatchApp"))
using PdMBatchApp
PdMBatchApp.run_batch()
