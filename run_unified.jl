#!/usr/bin/env julia
# ============================================================================
# run_unified.jl — Paso 4 del merge: UN solo sustrato (LifeProcess) produce las TRES salidas:
#   (A) eventos WS-A (fallas/reemplazos),  (B) telemetría (operativa + precursor),  (C) economía.
# La MISMA f=Dcum/Θ causa la falla, alimenta el precursor (telemetría) y la decisión (economía).
#
# Uso:  julia run_unified.jl [n_vehicles]
# ============================================================================
using Printf, Statistics, Random
const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
using .MaintenanceSim.LifeProcess, .MaintenanceSim.Precursors, .MaintenanceSim.Survival,
      .MaintenanceSim.Decision, .MaintenanceSim.Policy, .MaintenanceSim.Economics,
      .MaintenanceSim.SignalRegistry, .MaintenanceSim.Powertrain

nv = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 120
comps = [c.name for c in MaintenanceSim.DamageModels.COMPONENTS if :heavy_truck in c.classes]
R = "="^82
sec(t) = (println("\n", R); println(t); println(R))
money(x) = @sprintf("%s MXN", replace(@sprintf("%.0f", x), r"(?<=\d)(?=(\d{3})+$)" => ","))

# ===== UN SOLO SUSTRATO =====
lives, truth, vehlives = generate_life_processes(LifeProcess.LifeConfig(n_vehicles=nv, horizon_days=730, seed=7))
sec("SIMULACIÓN UNIFICADA — eventos WS-A + telemetría + economía de UN sustrato")
@printf("Sustrato: %d vehículos · %d posiciones · semilla 7 · la misma f=Dcum/Θ alimenta todo.\n",
        nv, length(lives))

# damage fraction de la instancia viva en el día d (para precursor); también el día de falla
function f_and_fail(pl)
    di = 0; D0 = pl.Dcum[1]; a0_D = pl.a0_D; ti = 1; series = Tuple{Int,Float64}[]; fdays = Int[]
    while ti <= length(pl.thresholds)
        Θ = pl.thresholds[ti]; fday = nothing
        for d in di:pl.ndays
            (pl.Dcum[d+1]-D0+a0_D >= Θ) && (fday = d; break)
        end
        endd = fday === nothing ? pl.ndays : fday
        for d in di:endd; push!(series, (d, clamp((pl.Dcum[d+1]-D0+a0_D)/Θ, 0, 1))); end
        fday === nothing && break
        push!(fdays, fday); di = fday; D0 = pl.Dcum[fday+1]; a0_D = 0.0; ti += 1
        (!pl.recurrent || fday >= pl.ndays) && break
    end
    return Dict(series), fdays
end

# ===== (A) EVENTOS WS-A =====
ev = reduce(vcat, [evaluate(pl, Reactive()) for pl in lives])
nf = count(o -> o.kind == :failure, ev)
sec("(A) EVENTOS WS-A (run-to-failure sobre el sustrato)")
@printf("%d eventos · %d fallas · %d en ruta · costo correctivo %s\n",
        length(ev), nf, count(o -> o.in_route, ev),
        money(sum(o -> o.kind == :failure ? o.cost : 0.0, ev)))
for c in comps
    fc = count(o -> o.kind == :failure && o.component == c, ev)
    @printf("   %-10s %d fallas\n", c, fc)
end

# ===== (C) ECONOMÍA (fit → T* → políticas → break-even) =====
allrecs = reduce(vcat, [life_records(pl) for pl in lives])
Tstar = Dict{String,Float64}()
for comp in comps
    recs = filter(r -> r.component_type == comp, allrecs)
    f = fit_grouped(recs; nboot=15, rng=MersenneTwister(7))
    dec = Decision.decide(comp, f.beta, f.beta_lo, mean(values(f.eta0)), truth.comp[comp].cp, truth.comp[comp].cf)
    Tstar[comp] = dec.preventive ? dec.Tstar : Inf
end
cbm_comps = [c for c in comps if haskey(Precursors.PRECURSOR_INFO, c)]   # con precursor on-board → CBM
alarm = Dict(c => Precursors.alarm_fraction(c) for c in cbm_comps)
scv   = Dict(c => Precursors.sensor_cv(c) for c in cbm_comps)
cfg = Economics.EconConfig()
econ = run_economics(lives, Policy.evaluate, Reactive(), PredictiveRUL(alarm, scv, 14, Tstar), cfg;
                     horizon_days=730, n_vehicles=nv)
sec("(C) ECONOMÍA (CBM físico sobre el MISMO sustrato)")
@printf("Preventivo aplicable: %s · battery gated (IFR)\n",
        join([c for c in comps if !isinf(Tstar[c])], ", "))
be = econ.breakeven_day
@printf("Break-even predictivo: %s · ahorro neto VPN a 2 años: %s\n",
        be === nothing ? "—" : @sprintf("día %d", be), money(econ.cum_savings[end]))

# ===== (B) TELEMETRÍA (operativa + precursor) + CONGRUENCIA con (A) =====
sec("(B) TELEMETRÍA del MISMO sustrato + congruencia con las fallas")
vl = vehlives[findfirst(v -> v.class == :heavy_truck, vehlives)]
dyn = Powertrain.dynspec_for(vl.class, vl.engine_kw)
bpl = lives[findfirst(l -> l.vehicle_id == vl.vehicle_id && l.component == "brake_pad", lives)]
fmap, fdays = f_and_fail(bpl)
eec1 = first(filter(p -> p.name == "EEC1", SignalRegistry.J1939_PGNS))
rt = true
for d in 60:120:min(vl.ndays, 540)
    vl.eng_h_day[d] == 0 && continue
    s = Powertrain.instant_state(dyn, vl.mass_day[d], vl.route_speed, vl.route_grade, vl.alt_day[d], vl.ambient_day[d])
    bal = Precursors.reading("brake_pad", get(fmap, d, 0.0))
    id1, dt1 = encode_pgn(eec1, Dict(190 => s.rpm))
    global rt &= isapprox(decode_pgn(eec1, dt1)[190], s.rpm; atol=0.5)
    @printf("   día %3d  RPM=%.0f carga=%.0f%% EGT=%.0f°C · balata=%.1f mm\n", d, s.rpm, s.load, s.egt_c, bal)
end
# congruencia: el precursor avisó antes de cada falla de esa balata
warned = count(fd -> any(p -> p[2] >= Precursors.alarm_fraction("brake_pad") && p[1] < fd && p[1] >= fd-200, collect(fmap)), fdays)
@printf("\nFrames round-trip: %s · balata avisó antes de %d/%d fallas de esta posición.\n",
        rt ? "✓" : "✗", warned, length(fdays))

# ===== (B') TELEMETRÍA A CADENCIA 1/min desde el sustrato unificado =====
sec("(B') TELEMETRÍA 1/min — operativa + precursor por minuto, del MISMO reloj de daño")
rng = MersenneTwister(1)
rows = NamedTuple[]; rt1 = true
opdays = [d for d in 1:vl.ndays if vl.eng_h_day[d] > 0][1:min(3, count(>(0), vl.eng_h_day))]
for d in opdays
    fday = get(fmap, d, 0.0); fnext = get(fmap, min(d+1, vl.ndays), fday)
    nmin = max(1, round(Int, vl.eng_h_day[d] * 60))
    for m in 1:nmin
        frac = m / nmin
        sp = vl.route_speed * (0.8 + 0.4*rand(rng))           # variación intra-viaje
        gr = vl.route_grade * (rand(rng) < 0.4 ? -1 : 1) * (0.3 + 0.7*rand(rng))
        s = Powertrain.instant_state(dyn, vl.mass_day[d], sp, gr, vl.alt_day[d], vl.ambient_day[d])
        f = clamp(fday + frac*(fnext-fday), 0, 1)             # f interpolada por minuto
        bal = Precursors.reading("brake_pad", f)
        push!(rows, (day=d, min=m, rpm=round(s.rpm,digits=1), load=round(s.load,digits=1),
              coolant=round(s.coolant_set,digits=1), egt=round(s.egt_c,digits=1), balata_mm=round(bal,digits=2)))
    end
end
# round-trip de una muestra de frames operativos
for r in rows[1:50:end]
    id1, dt1 = encode_pgn(eec1, Dict(190 => r.rpm))
    global rt1 &= isapprox(decode_pgn(eec1, dt1)[190], r.rpm; atol=0.6)
end
outdir = joinpath(ROOT, "out", "unified"); mkpath(outdir)
open(joinpath(outdir, "telemetry_1min.csv"), "w") do io
    println(io, "day,minute,rpm,load_pct,coolant_c,egt_c,balata_mm")
    for r in rows; @printf(io, "%d,%d,%.1f,%.1f,%.1f,%.1f,%.2f\n", r.day,r.min,r.rpm,r.load,r.coolant,r.egt,r.balata_mm); end
end
@printf("%d filas 1/min (%d días op.) · operativa+precursor del MISMO sustrato · round-trip %s → out/unified/telemetry_1min.csv\n",
        length(rows), length(opdays), rt1 ? "✓" : "✗")

sec("RESUMEN")
println("✓ UN sustrato (semilla 7) → eventos WS-A (A) + telemetría operativa+precursor (B) + economía (C).")
println("✓ La misma f=Dcum/Θ causa la falla, genera el precursor observado y dispara el CBM. Reloj unificado.")
println("  Telemetría 1/min (B') + precursor por minuto del mismo reloj. (Diagnostics/TelemetrySim = generador standalone, capa aparte.)")
