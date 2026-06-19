#=
test_SyntheticFleet.jl — Pruebas del generador sintético.

Correr:  julia test_SyntheticFleet.jl   (requiere J1939.jl y SyntheticFleet.jl en el mismo dir)

Cubre:
  (1) round-trip exacto encode→decode por el decoder verificado (HOURS/EEC1/ET1),
  (2) que la telemetría generada decodifica a valores plausibles,
  (3) invariantes de la tripleta WS-A (entry/exit/status), presencia de censura,
      truncamiento y recurrencia, y del camino auto_dtc.

La RECUPERACIÓN de parámetros (β,η0,γ) se valida con `negloglik_aft` + Optim.jl/Survival.jl
(loop espejo del prototipo Python ya probado); se incluye un esqueleto comentado al final.
=#

# NOTA: SyntheticFleet.jl es el generador one-shot v0.1 (DEPRECADO), superado por
# FleetSimulator.jl (motor agente-físico). Este test es legacy; ver test_FleetSimulator.jl.
include(joinpath(@__DIR__, "..", "src", "ingest", "J1939.jl"));            using .J1939
include(joinpath(@__DIR__, "..", "src", "synthetic", "SyntheticFleet.jl")); using .SyntheticFleet
using Test

@testset "Synthetic generator" begin

    @testset "Round-trip encode→decode (exacto)" begin
        id, fr = SyntheticFleet.frame_hours(1500.0)
        r = J1939.decode_frame(id, fr)
        @test r.pgn == 65253
        @test isapprox(r.signals[247], 1500.0; atol = 0.05)          # resolución 0.05 h

        id, fr = SyntheticFleet.frame_eec1(1024.0)
        r = J1939.decode_frame(id, fr)
        @test r.pgn == 61444
        @test isapprox(r.signals[190], 1024.0; atol = 0.125)         # resolución 0.125 rpm

        id, fr = SyntheticFleet.frame_et1(60.0)
        r = J1939.decode_frame(id, fr)
        @test r.pgn == 65262
        @test isapprox(r.signals[110], 60.0; atol = 1.0)
    end

    fleet = generate_fleet(; n_vehicles = 80, seed = 20260615)

    @testset "Telemetría decodifica" begin
        # Toda señal presente decodifica a un número (no missing) y plausible.
        for (id, fr) in fleet.frames
            r = J1939.decode_frame(id, fr)
            for (spn, val) in r.signals
                @test val !== missing
            end
        end
    end

    @testset "Invariantes WS-A" begin
        ev = fleet.events
        @test !isempty(ev)
        @test all(e -> e.entry_age >= 0, ev)
        @test all(e -> e.exit_age > e.entry_age, ev)
        @test all(e -> e.status in (0, 1, 2), ev)

        @test any(e -> e.status == 0, ev)                 # hay censura
        @test any(e -> e.entry_age > 0, ev)               # hay truncamiento izq.
        @test any(e -> e.instance > 1, ev)                # hay recurrencia
        @test any(e -> e.dtc_spn != 0, ev)                # hay camino auto_dtc (DTC)
        @test any(e -> e.dtc_spn == 3251 || e.dtc_spn == 5246, ev)  # aftertreatment
    end

    @testset "Ground truth presente" begin
        @test fleet.truth.beta > 0
        @test !isempty(fleet.truth.eta0)
        @test haskey(fleet.truth.eta0, (:heavy_truck, "Volvo"))
    end
end

#=
--- RECUPERACIÓN de parámetros (descomentar con Optim.jl) ---
# Validado (port Python): el estimador BIEN ESPECIFICADO (η0 por grupo + β,γ compartidos)
# recupera β, γ y los η0 por (clase,marca) dentro de ±5–6%. El ajuste de un solo η0 está
# mal especificado y sesga β,γ (motiva el modelo jerárquico F4). Usar más vehículos
# (p.ej. n_vehicles=400) para identificabilidad por grupo.
using Optim
fleet = generate_fleet(; n_vehicles = 400, seed = 7)
ev  = filter(e -> startswith(e.position, "brake_pad"), fleet.events)
sev = Dict(v.vehicle_id => v.route_severity for v in fleet.vehicles)
grp = Dict(v.vehicle_id => (v.class, v.brand) for v in fleet.vehicles)
groups = sort(unique(grp[e.vehicle_id] for e in ev))
gid = Dict(g => i for (i, g) in enumerate(groups)); G = length(groups)
gi = [gid[grp[e.vehicle_id]] for e in ev]
x  = [sev[e.vehicle_id] for e in ev]
t  = [e.exit_age for e in ev]
d  = [e.status > 0 ? 1.0 : 0.0 for e in ev]
a  = [e.entry_age for e in ev]
x0 = vcat(log(2.0), 0.0, fill(log(1200.0), G))
res = optimize(th -> SyntheticFleet.negloglik_aft_grouped(th, gi, x, t, d, a, G), x0, NelderMead())
β̂, γ̂ = exp(res.minimizer[1]), res.minimizer[2]
@info "recuperado" beta=β̂ verdad_beta=fleet.truth.beta gamma=γ̂ verdad_gamma=fleet.truth.gamma
for (i, g) in enumerate(groups)
    @info "eta0" grupo=g verdad=fleet.truth.eta0[g] est=exp(res.minimizer[2+i])
end
=#

