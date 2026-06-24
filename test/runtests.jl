# ============================================================================
# Suite agregada de MaintenanceSim. Corre todas las pruebas.
#   julia --project=. test/runtests.jl        (o)   Pkg.test("MaintenanceSim")
# Cada archivo carga el paquete vía src/MaintenanceSim.jl y es ejecutable por separado.
# ============================================================================
using Test

@testset "MaintenanceSim — suite completa" begin
    for f in ("test_J1939.jl", "test_FleetSimulator.jl", "test_telemetry.jl", "test_economics.jl",
              "test_estimator.jl", "test_analytics.jl", "test_tracker_adapter.jl",
              "test_oil_sample.jl")
        @testset "$f" begin
            include(joinpath(@__DIR__, f))
        end
    end
end
