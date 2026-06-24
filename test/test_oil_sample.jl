# ============================================================================
# Contrato de análisis de aceite (OilSample): mapeo PURO muestra → fracción de degradación.
#   julia test/test_oil_sample.jl
# ============================================================================
using Test

const ROOT = abspath(joinpath(@__DIR__, ".."))
isdefined(Main, :MaintenanceSim) || include(joinpath(ROOT, "src", "MaintenanceSim.jl"))
using .MaintenanceSim
using .MaintenanceSim.OilSample

@testset "OilSample — contrato y mapeo" begin

    # --- wear_fraction: 0 en la base, 1 en el límite, monótona y con clamp ---
    @testset "wear_fraction" begin
        lim = WearLimit(10.0, 100.0, 1.0)
        @test wear_fraction(10.0, lim) == 0.0                 # línea base → 0
        @test wear_fraction(100.0, lim) == 1.0                # límite → 1
        @test isapprox(wear_fraction(55.0, lim), 0.5; atol=1e-9)   # punto medio → 0.5
        @test wear_fraction(5.0, lim) == 0.0                  # bajo la base → clamp 0
        @test wear_fraction(500.0, lim) == 1.0                # sobre el límite → clamp 1
        @test wear_fraction(40.0, lim) < wear_fraction(70.0, lim)  # monótona creciente
        @test wear_fraction(50.0, WearLimit(50.0, 50.0, 1.0)) == 0.0  # den<=0 protegido
    end

    # --- normalize_ppm: normaliza por edad de aceite (mismos ppm sobre más horas = menos preocupante) ---
    @testset "normalize_ppm" begin
        @test isapprox(normalize_ppm(100.0, 250.0; h_ref=250.0), 100.0; atol=1e-9)  # a la referencia
        @test isapprox(normalize_ppm(100.0, 500.0; h_ref=250.0), 50.0;  atol=1e-9)  # doble edad → mitad
        @test isapprox(normalize_ppm(100.0, 125.0; h_ref=250.0), 200.0; atol=1e-9)  # media edad → doble
        @test normalize_ppm(80.0, 0.0) == 80.0                                       # edad 0 → crudo
    end

    # --- system_fraction: el metal peor gobierna; recupera una fracción conocida ---
    @testset "system_fraction" begin
        # Fe normalizado al punto medio de su límite de motor (10..100) ⇒ f_Fe = 0.5·w(1.0) = 0.5
        s = OilSampleRecord("VEH-1", :engine, 8000.0, 320000.0, 250.0,
                            Dict(:iron_fe => 55.0, :copper_cu => 5.0), 13.5, 1.2, 7.0)
        f, driver = system_fraction(s, DEFAULT_LIMITS[:engine])
        @test isapprox(f, 0.5; atol=1e-6)
        @test driver == :iron_fe                              # Fe domina

        # aceite SANO a la edad de referencia (metales en base) ⇒ fracción 0
        s0 = OilSampleRecord("VEH-2", :engine, 5000.0, 200000.0, 250.0,
                             Dict(:iron_fe => 10.0, :copper_cu => 5.0), 14.0, 0.1, 10.0)
        @test first(system_fraction(s0, DEFAULT_LIMITS[:engine])) == 0.0

        # semántica de TASA: los MISMOS 10 ppm de Fe en solo 50 h de aceite = tasa alta ⇒ alarma (>0).
        s_fast = OilSampleRecord("VEH-2b", :engine, 5000.0, 200000.0, 50.0,
                                 Dict(:iron_fe => 10.0), 14.0, 0.1, 10.0)
        @test first(system_fraction(s_fast, DEFAULT_LIMITS[:engine])) > 0.3

        # componente AL LÍMITE ⇒ fracción 1 (alarma)
        sL = OilSampleRecord("VEH-3", :differential, 12000.0, 480000.0, 250.0,
                             Dict(:iron_fe => 300.0), 0.0, 0.0, 0.0)
        @test first(system_fraction(sL, DEFAULT_LIMITS[:differential])) == 1.0

        # normalización por edad: mismos ppm con MÁS horas de aceite ⇒ menor fracción
        s_young = OilSampleRecord("V", :engine, 8000.0, 3.2e5, 125.0, Dict(:iron_fe => 55.0), 13.5, 1.0, 7.0)
        s_old   = OilSampleRecord("V", :engine, 8000.0, 3.2e5, 500.0, Dict(:iron_fe => 55.0), 13.5, 1.0, 7.0)
        @test first(system_fraction(s_young, DEFAULT_LIMITS[:engine])) >
              first(system_fraction(s_old,   DEFAULT_LIMITS[:engine]))
    end
end
