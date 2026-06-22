# ============================================================================
# build_app.jl — Compila el job batch a un EJECUTABLE STANDALONE (sin Julia en destino) con
# PackageCompiler `create_app` (B.1 de Empaquetado_Libreria_Compilacion.md). Bundle ~150–400 MB
# que arranca rápido; ideal para un cron/servicio en el servidor de Tracker.
#
#   julia compile/build_app.jl
# Salida: build/PdMBatchApp/  (gitignored) con bin/PdMBatchApp. Correr:
#   TRACKER_DB_URL=postgresql://… build/PdMBatchApp/bin/PdMBatchApp
#
# Requisitos: el entorno apps/PdMBatchApp debe estar instanciado (Pkg.instantiate) con LibPQ, Tables,
# UUIDs y MaintenanceSim (por [sources] path). El precompile NO toca la BD (solo el estimador).
# Para un server x86-64 distinto a la máquina de build, pasar cpu_target vía ENV["PDM_CPU_TARGET"].
# ============================================================================
using Pkg

const ROOT  = abspath(joinpath(@__DIR__, ".."))
const APP   = joinpath(ROOT, "apps", "PdMBatchApp")
const BUILD = joinpath(ROOT, "build"); mkpath(BUILD)

Pkg.activate(@__DIR__)                                   # entorno con PackageCompiler
haskey(Pkg.project().dependencies, "PackageCompiler") || Pkg.add("PackageCompiler")

# Asegura el entorno del app instanciado (deps resueltas) antes de compilar.
Pkg.activate(APP); Pkg.instantiate()
Pkg.activate(@__DIR__)

using PackageCompiler

kw = haskey(ENV, "PDM_CPU_TARGET") ? (; cpu_target = ENV["PDM_CPU_TARGET"]) : (;)
@info "create_app: compilando PdMBatchApp → build/PdMBatchApp (esto tarda varios minutos)"
create_app(APP, joinpath(BUILD, "PdMBatchApp");
    executables = ["PdMBatchApp" => "julia_main"],
    precompile_execution_file = joinpath(@__DIR__, "precompile_app.jl"),
    incremental = false, force = true, kw...)

@info "app compilada" bin=joinpath(BUILD, "PdMBatchApp", "bin", "PdMBatchApp")
