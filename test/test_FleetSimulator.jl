# ============================================================================
# Criterios de aceptación del simulador + algoritmo (Brief §3, fase F0).
# Correr:  julia test/test_FleetSimulator.jl
# ============================================================================
using Test, Random, Statistics

const ROOT = abspath(joinpath(@__DIR__, ".."))
isdefined(Main, :MaintenanceSim) || include(joinpath(ROOT, "src", "MaintenanceSim.jl"))
using .MaintenanceSim
using .MaintenanceSim.J1939, .MaintenanceSim.FleetSimulator, .MaintenanceSim.Survival,
      .MaintenanceSim.RUL, .MaintenanceSim.CBM, .MaintenanceSim.Decision

@testset "FleetSimulator — criterio de aceptación F0" begin

    # --- (a) round-trip J1939: encode → decode exacto ---
    @testset "round-trip J1939 (telemetría)" begin
        for (h, spn) in [(1500.0, 247)]
            id, data = FleetSimulator.frame_hours(h)
            dec = decode_frame(id, data)
            @test isapprox(dec.signals[247], h; atol=0.05)
        end
        id, data = FleetSimulator.frame_eec1(1450.0)
        @test isapprox(decode_frame(id, data).signals[190], 1450.0; atol=0.125)
        id, data = FleetSimulator.frame_et1(88.0)
        @test isapprox(decode_frame(id, data).signals[110], 88.0; atol=1.0)
        id, data = FleetSimulator.frame_vep1(13.6)
        @test isapprox(decode_frame(id, data).signals[168], 13.6; atol=0.05)
    end

    # genera una flota una vez para los demás tests
    out = simulate_fleet(FleetSimulator.SimConfig(n_vehicles=200, horizon_days=730, seed=20240617))

    # --- todos los frames emitidos hacen round-trip ---
    @testset "todos los frames emitidos round-trip" begin
        ok = true
        for f in out.frames
            dec = decode_frame(f.can_id, f.data)
            isempty(dec.signals) && (ok = false)
            for (_, v) in dec.signals
                (v === missing || isfinite(v)) || (ok = false)
            end
        end
        @test ok
    end

    # --- censura y truncamiento son ciudadanos de primera clase ---
    @testset "censura + truncamiento presentes" begin
        @test count(s -> s.status == 0, out.survival) > 0          # censura por la derecha
        @test count(s -> s.entry_age > 0, out.survival) > 0        # truncamiento por la izquierda
        @test all(s -> s.exit_age >= s.entry_age, out.survival)    # consistencia de la tripleta
        @test count(s -> s.status > 0, out.survival) > 0           # hay fallas
    end

    # --- recurrencia: hay posiciones con >1 instancia (renovación Kijima q=0) ---
    @testset "recurrencia por posición" begin
        per_pos = Dict{Int,Int}()
        for i in out.instances
            per_pos[i.position_id] = get(per_pos, i.position_id, 0) + 1
        end
        @test maximum(values(per_pos)) > 1
    end

    # --- realismo agente-físico: varios tipos de camión y corredores emergentes ---
    @testset "agente-físico — tipos y corredores" begin
        models = unique([v.model for v in out.vehicles])
        @test length(models) >= 6                                 # varios tipo×marca
        sevs = unique(round.([v.route_severity for v in out.vehicles], digits=2))
        @test length(sevs) >= 4                                   # varios corredores (severidad emergente)
        @test any(v -> v.protocol == :obd2, out.vehicles)         # ligeros OBD-II
        @test any(v -> v.protocol == :j1939, out.vehicles)        # pesados J1939
    end

    # --- (b) recuperación de β y γ=−κ del estimador BIEN ESPECIFICADO ---
    #     La vida EMERGE de la física; aun así el ajustador independiente recupera la verdad.
    #     Se prueban componentes data-ricos a la escala del test (brake_pad: desgaste; battery: β≈1).
    #     scr/dpf (vida larga, pocas fallas en 2 años) se validan a mayor escala en el orquestador.
    @testset "recuperación de β y γ=−κ vs verdad" begin
        # brake_pad (desgaste, data-rico): recuperación COMPLETA β, γ=−κ y η0 por grupo.
        let comp = "brake_pad"
            recs = filter(r -> r.component_type == comp, out.survival)
            fit = fit_grouped(recs; nboot=20, rng=MersenneTwister(3))
            tβ = out.truth.comp[comp].beta
            tγ = out.truth.comp[comp].gamma                       # = −κ (sensibilidad física)
            @test abs(fit.beta - tβ) / tβ < 0.08                  # β dentro de ±8%
            @test abs(fit.gamma - tγ) < 0.15                      # γ recupera −κ
            @test fit.converged
            errs = [abs(e - out.truth.eta0[(g[1], g[2], comp)]) / out.truth.eta0[(g[1], g[2], comp)]
                    for (g, e) in fit.eta0]
            @test median(errs) < 0.15                             # η0 por grupo (η_ref) recuperado
        end
        # battery (β≈1, fallas casi sin memoria): SOLO se recupera β bien; la pendiente AFT γ y η0
        # están DÉBILMENTE identificadas a β≈1 (covariable de severidad poco distinguible del ruido
        # exponencial) — por eso mismo IFR rehúsa preventivo (ver testset de regla IFR). Asertar γ/η0
        # finos aquí sería exigirle al estimador algo que la estadística no permite a β≈1.
        let comp = "battery"
            recs = filter(r -> r.component_type == comp, out.survival)
            fit = fit_grouped(recs; nboot=20, rng=MersenneTwister(3))
            @test abs(fit.beta - out.truth.comp[comp].beta) / out.truth.comp[comp].beta < 0.10
            @test fit.converged
        end
    end

    # --- (c) covariable de MANEJO (OBD/CAN): mueve la vida por unidad y es RECUPERABLE ---
    #     Con drive_spread>0 cada conductor tiene un índice de manejo observable (OBD/CAN-derivado);
    #     la vida por unidad se desplaza (η_i = η0·exp(−κ·z_ruta − κ_drive·(idx−0.5))) y el AFT de 2
    #     covariables recupera γ_drive = −κ_drive. brake_pad = caso data-rico y más sensible al manejo
    #     (mecanismo :brake ⇒ κ_drive=1.0). Validación del loop para la 2ª covariable.
    @testset "covariable de manejo — recupera γ_drive" begin
        outd = simulate_fleet(FleetSimulator.SimConfig(n_vehicles=300, horizon_days=900,
                                                       seed=424242, drive_spread=1.0))
        recs = filter(r -> r.component_type == "brake_pad", outd.survival)
        @test var([r.driving_index for r in recs]) > 1e-3              # el manejo varía entre unidades
        fit = fit_grouped(recs; nboot=15, rng=MersenneTwister(7))
        tβ = outd.truth.comp["brake_pad"].beta
        @test abs(fit.beta - tβ) / tβ < 0.08                          # β sigue recuperándose
        @test abs(fit.gamma - outd.truth.comp["brake_pad"].gamma) < 0.15   # γ_route sigue recuperándose
        κ_drive = MaintenanceSim.DamageModels.drive_sensitivity(:brake)
        @test abs(fit.gamma_drive - (-κ_drive)) < 0.15                # γ_drive ≈ −κ_drive = −1.0
        # sin manejo (drive_spread=0, la flota base `out`) la 2ª covariable no varía ⇒ γ_drive=0 exacto
        recs0 = filter(r -> r.component_type == "brake_pad", out.survival)
        @test fit_grouped(recs0; nboot=5, rng=MersenneTwister(7)).gamma_drive == 0.0
    end

    # --- regla IFR: battery (β≈1) → IC incluye 1 → rechazo de preventivo ---
    @testset "regla IFR — battery rechaza preventivo" begin
        recs = filter(r -> r.component_type == "battery", out.survival)
        fit = fit_grouped(recs; nboot=25, rng=MersenneTwister(5))
        # β≈1 (sin desgaste): el IC no identifica desgaste firme ⇒ su cota inferior queda en ~1.
        # Tolerancia (no bracket exacto de 1.0) para ser robusto al stream de RNG global; la intención
        # —β indistinguible de 1 y, en consecuencia, IFR rehúsa preventivo— se verifica abajo y en β≈truth.
        @test fit.beta_lo <= 1.05                                 # cota inferior esencialmente en 1
        dec = Decision.decide("battery", fit.beta, fit.beta_lo,
                              mean(values(fit.eta0)), 1500.0, 9000.0)
        @test dec.preventive == false                            # rehúsa
    end

    # --- desgaste real: brake_pad → preventivo SÍ, T* finito, ahorro positivo ---
    @testset "desgaste — brake_pad recomienda preventivo" begin
        recs = filter(r -> r.component_type == "brake_pad", out.survival)
        fit = fit_grouped(recs; nboot=25, rng=MersenneTwister(5))
        @test fit.beta_lo > 1.0                                   # IC excluye 1
        dec = Decision.decide("brake_pad", fit.beta, fit.beta_lo,
                              mean(values(fit.eta0)), 2700.0, 22700.0)
        @test dec.preventive == true
        @test dec.Tstar !== nothing && dec.Tstar > 0
        @test 0 < dec.s_prev < dec.s_ceiling                     # ahorro por debajo del techo predictivo
    end

    # --- sesgo del modelo de un solo η0 (motiva el jerárquico F4) ---
    @testset "sesgo de η0 único vs agrupado" begin
        recs = filter(r -> r.component_type == "brake_pad", out.survival)
        grouped = fit_grouped(recs; nboot=10, rng=MersenneTwister(9))
        pooled = fit_pooled(recs)
        tβ = out.truth.comp["brake_pad"].beta
        # el agrupado (bien especificado) está más cerca de la verdad que el pooled
        @test abs(grouped.beta - tβ) <= abs(pooled.beta - tβ) + 0.05
    end

    # --- CBM/DTC: un DTC inyectado dispara orden; derate SCR es la prioridad máxima ---
    @testset "CBM/DTC — derate SCR es prioridad máxima" begin
        posveh = Dict(p.position_id => p.vehicle_id for p in out.positions)
        poscomp = Dict(p.position_id => p.component_type for p in out.positions)
        iv = Dict(i.instance_id => posveh[i.position_id] for i in out.instances)
        ic = Dict(i.instance_id => poscomp[i.position_id] for i in out.instances)
        wos = CBM.work_orders(out.events, iv, ic)
        @test !isempty(wos)
        @test first(wos).spn == 5246                             # derate SCR primero
        @test first(wos).stranding_risk == true
        @test all(w -> w.priority >= 1, wos)
    end

    # --- RUL: finita, positiva, decreciente con la edad ---
    @testset "RUL condicional bien formada" begin
        @test RUL.rul(0.0, 2.3, 1500.0) ≈ 1500.0 * Decision.mttf(2.3, 1.0) atol=1.0
        r1 = RUL.rul(500.0, 2.3, 1500.0)
        r2 = RUL.rul(1200.0, 2.3, 1500.0)
        @test r1 > 0 && r2 > 0
        @test r2 < r1                                            # IFR: RUL cae con la edad
    end

    # --- descompostura en ruta: existe el camino c_f con grúa/downtime ---
    @testset "descompostura en ruta (c_f)" begin
        inroute = filter(e -> e.type == :failure && e.in_route, out.events)
        @test !isempty(inroute)
        @test any(e -> e.cost_towing > 0, inroute)               # hubo grúa
        @test any(e -> e.downtime_h > 0, inroute)
        @test any(e -> e.mode_id == 3 && e.cost_fine > 0, inroute)  # derate SCR con multa
    end
end
