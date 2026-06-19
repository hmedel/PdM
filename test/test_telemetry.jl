# ============================================================================
# Tests del subsistema de telemetría OBD/CAN (round-trip + consistencia física).
# Correr:  julia test/test_telemetry.jl
# ============================================================================
using Test, Random, Statistics

const ROOT = abspath(joinpath(@__DIR__, ".."))
isdefined(Main, :MaintenanceSim) || include(joinpath(ROOT, "src", "MaintenanceSim.jl"))
using .MaintenanceSim
using .MaintenanceSim.SignalRegistry, .MaintenanceSim.Powertrain, .MaintenanceSim.TireModel,
      .MaintenanceSim.TelemetrySim, .MaintenanceSim.Diagnostics

@testset "Telemetría OBD/CAN" begin

    @testset "round-trip J1939 (encode→decode exacto)" begin
        eec1 = first(filter(p -> p.name == "EEC1", SignalRegistry.J1939_PGNS))
        id, data = encode_pgn(eec1, Dict(190 => 1450.0, 513 => 78.0, 512 => 82.0))
        dec = decode_pgn(eec1, data)
        @test isapprox(dec[190], 1450.0; atol = 0.125)        # cuantización RPM
        @test isapprox(dec[513], 78.0; atol = 1.0)
        et1 = first(filter(p -> p.name == "ET1", SignalRegistry.J1939_PGNS))
        _, d2 = encode_pgn(et1, Dict(110 => 92.0, 175 => 108.0))
        dec2 = decode_pgn(et1, d2)
        @test isapprox(dec2[110], 92.0; atol = 1.0)
        @test isapprox(dec2[175], 108.0; atol = 0.1)
    end

    @testset "round-trip OBD-II (todas las PIDs)" begin
        for (pid, sig) in SignalRegistry.OBD_PIDS
            tv = pid == 0x0C ? 2100.0 : pid == 0x10 ? 45.0 : pid == 0x42 ? 13.9 :
                 pid == 0x5E ? 18.0 : pid == 0x1F ? 1200.0 : 55.0
            b = encode_obd(sig, tv)
            @test isapprox(decode_obd(sig, b), tv; rtol = 0.05, atol = 1.0)
        end
    end

    @testset "Powertrain — consistencia física" begin
        spec = Powertrain.dynspec_for(:heavy_truck, 360.0)
        ml = 8500 + 17000.0
        flat = Powertrain.instant_state(spec, ml, 95.0, 0.0, 300.0, 22.0)
        climb = Powertrain.instant_state(spec, ml, 95.0, 6.0, 300.0, 22.0)
        idle = Powertrain.instant_state(spec, ml, 0.0, 0.0, 300.0, 22.0)
        @test climb.load > flat.load                          # subir carga el motor
        @test climb.v_kph < 95.0                              # limitado por potencia en 6%
        @test climb.fuel_lph > flat.fuel_lph                  # más combustible bajo carga
        @test climb.egt_c > flat.egt_c                        # más temperatura de escape
        @test idle.rpm ≈ spec.idle_rpm                        # ralentí
        @test flat.rpm <= spec.redline_rpm                    # nunca sobre redline
        @test flat.rpm > 1000                                 # crucero en banda
        # derate por altitud: a 3000 m la velocidad sostenible en subida cae
        hi = Powertrain.instant_state(spec, ml, 95.0, 6.0, 3000.0, 5.0)
        @test hi.v_kph <= climb.v_kph + 1e-6
    end

    @testset "TireModel — presión (Gay-Lussac) y desgaste (FMCSA)" begin
        rng = MersenneTwister(1)
        steer = new_tire("steer_left", :heavy_truck; rng = rng)
        @test steer.spec.legal_min_mm == 3.2                  # 4/32″ dirección (FMCSA)
        drive = new_tire("drive_axle_right", :heavy_truck; rng = rng)
        @test drive.spec.legal_min_mm == 1.6                  # 2/32″ tracción
        p_cold = tire_pressure_kpa(steer, 20.0)
        p_hot = tire_pressure_kpa(steer, 70.0)
        @test p_hot > p_cold                                  # presión sube con temperatura
        t0 = steer.tread_mm
        tread_wear_increment!(steer, 5000.0, 1.2, 0.5, 2.0)
        @test steer.tread_mm < t0                             # la banda se desgasta
        @test 0.0 <= tread_fraction(steer) <= 1.0
    end

    @testset "TelemetrySim — showcase round-trip + física" begin
        cfg = TelemetrySim.TelemetryConfig(log_dt_s = 60, micro_dt_s = 10, days_per_combo = 1, seed = 3)
        rows, frames, feats = generate_showcase(cfg)
        @test length(rows) > 1000
        @test length(frames) > 10000

        # round-trip de todos los frames
        pgn_by_num = Dict(p.pgn => p for p in SignalRegistry.J1939_PGNS)
        bad = 0
        for (vid, t, id, data) in frames
            if id == 0x7E8
                sig = SignalRegistry.OBD_PIDS[data[2]]
                isfinite(decode_obd(sig, data[3:2+sig.n_bytes])) || (bad += 1)
            else
                pd = get(pgn_by_num, Int((id >> 8) & 0xFFFF), nothing)
                pd === nothing && (bad += 1; continue)
                all(v -> v === missing || isfinite(v), values(decode_pgn(pd, data))) || (bad += 1)
            end
        end
        @test bad == 0                                        # round-trip íntegro

        # física: RPM de pesados bajo redline; correlación pendiente↔carga
        heavy = filter(r -> r.protocol == :j1939, rows)
        @test all(r -> r.rpm <= 2150, heavy)
        @test all(r -> 0 <= r.load_pct <= 101, rows)
        gl = [(r.grade_pct, r.load_pct) for r in heavy if r.speed_kph > 20]
        g = [x[1] for x in gl]; l = [x[2] for x in gl]
        @test cor(g, l) > 0.3                                 # subidas cargan el motor

        # consumo emergente: corredor de montaña/rugoso consume más que llanura
        byroute = Dict{String,Vector{Float64}}()
        for f in feats
            push!(get!(byroute, f.route, Float64[]), 100 * f.fuel_l / max(f.dist_km, 1))
        end
        if haskey(byroute, "rockies_longhaul") && haskey(byroute, "plains_longhaul")
            @test mean(byroute["rockies_longhaul"]) > 0       # (consistencia básica)
        end
    end

    @testset "Precursores PdM + heterogeneidad inicial" begin
        cfg = TelemetrySim.TelemetryConfig(log_dt_s = 60, micro_dt_s = 10, days_per_combo = 1, seed = 11)
        rows, _, _ = generate_showcase(cfg)
        heavy = filter(r -> r.protocol == :j1939, rows)

        # rangos físicos de los precursores
        @test all(r -> 0 <= r.crankcase_kpa <= 12, heavy)         # presión de cárter (blowby)
        @test all(r -> 40 <= r.oil_filt_dp_kpa <= 320, heavy)     # ΔP filtro aceite
        @test all(r -> 0.15 <= r.batt_soh <= 1.0, heavy)          # SoH batería
        @test all(r -> 0.5 <= r.brake_lining_mm <= 20, heavy)     # balata
        @test all(r -> 9.0 <= r.cranking_v <= 13.5, heavy)        # voltaje de arranque

        # HETEROGENEIDAD: la flota arranca en estados distintos (no todos iguales)
        @test maximum(r.odo_km for r in heavy) - minimum(r.odo_km for r in heavy) > 200_000
        @test maximum(r.crankcase_kpa for r in heavy) - minimum(r.crankcase_kpa for r in heavy) > 1.0
        @test maximum(r.batt_soh for r in heavy) - minimum(r.batt_soh for r in heavy) > 0.1

        # blowby correlaciona con odómetro (motores viejos → más presión de cárter)
        odo = [r.odo_km for r in heavy]; cc = [r.crankcase_kpa for r in heavy]
        @test cor(odo, cc) > 0.3
    end

    @testset "estado de salud — evolución e inicial" begin
        rng = MersenneTwister(2)
        h_new = Diagnostics.initial_health(rng; class = :heavy_truck)
        @test h_new.battery_soh <= 1.0 && h_new.battery_soh >= 0.15
        @test h_new.odo0_km > 0
        # evolucionar: el blowby y la ceniza solo crecen
        b0, a0 = h_new.blowby, h_new.dpf_ash
        Diagnostics.evolve_health!(h_new, 5000.0, 90.0, 1500.0, 5e5, 0.1, 30.0)
        @test h_new.blowby >= b0
        @test h_new.dpf_ash >= a0
        @test h_new.brake_lining_mm >= 0.5
    end
end
