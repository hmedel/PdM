# ============================================================================
# build_sysimage.jl — Construye un sysimage del estimador (B.2 de Empaquetado_Libreria_Compilacion.md).
# Mata la latencia JIT del ajuste Weibull-AFT + bootstrap para el job batch server-side
# (`run_pdm_batch.jl --sysimage=build/MaintenanceSim.so`). Requiere Julia en el server.
#
#   julia compile/build_sysimage.jl
# Salida: build/MaintenanceSim.so  (gitignored). Usa un entorno de build aparte (compile/Project.toml)
# con MaintenanceSim dev'd + PackageCompiler — NO contamina el Project.toml del paquete.
# ============================================================================
using Pkg

const ROOT  = abspath(joinpath(@__DIR__, ".."))
const BUILD = joinpath(ROOT, "build"); mkpath(BUILD)

# Entorno de build aislado en compile/ (PackageCompiler ya instalado antes en build/; lo replicamos aquí).
Pkg.activate(@__DIR__)
haskey(Pkg.project().dependencies, "MaintenanceSim") || Pkg.develop(path=ROOT)
haskey(Pkg.project().dependencies, "PackageCompiler") || Pkg.add("PackageCompiler")
Pkg.instantiate()

using PackageCompiler

@info "create_sysimage: horneando MaintenanceSim (estimador) → build/MaintenanceSim.so"
# cpu_target: por defecto = nativo (necesario en Apple Silicon: "generic" rompe con el intrínseco
# AES de aarch64). Para un server x86-64 portar con ENV["PDM_CPU_TARGET"]="generic" (o "x86-64").
kw = haskey(ENV, "PDM_CPU_TARGET") ? (; cpu_target = ENV["PDM_CPU_TARGET"]) : (;)
create_sysimage(["MaintenanceSim"];
    sysimage_path = joinpath(BUILD, "MaintenanceSim.so"),
    precompile_execution_file = joinpath(@__DIR__, "precompile_estimator.jl"),
    kw...)

@info "sysimage listo" path=joinpath(BUILD, "MaintenanceSim.so")
