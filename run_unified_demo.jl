#!/usr/bin/env julia
# ============================================================================
# MERGE de los generadores — Paso 2 (núcleo): la telemetría de precursores se deriva del MISMO
# reloj de daño (LifeProcess.Dcum/Θ) que causa las fallas. Un solo estado → telemetría Y fallas.
#
# Demuestra la CONGRUENCIA: el precursor (balata mm, ΔP DPF, …) de una instancia que va a fallar
# tiende a su alarma física ANTES del evento de falla — por construcción, no por dos modelos paralelos.
#
# Uso:  julia run_unified_demo.jl [n_vehicles]
# Salida: out/unified/precursor_series.csv  (serie temporal del precursor por instancia)
# ============================================================================
using Printf, Statistics
const ROOT = @__DIR__
include(joinpath(ROOT, "src", "MaintenanceSim.jl")); using .MaintenanceSim
using .MaintenanceSim.LifeProcess, .MaintenanceSim.Precursors,
      .MaintenanceSim.SignalRegistry, .MaintenanceSim.Powertrain

nv = length(ARGS) >= 1 ? parse(Int, ARGS[1]) : 120
lives, truth, vehlives = generate_life_processes(LifeProcess.LifeConfig(n_vehicles=nv, horizon_days=730, seed=7))

"""
Serie temporal del precursor de una posición, derivada del reloj de daño: por instancia viva, a
cadencia `every`, la lectura física = Precursors.reading(comp, f) con f = daño/Θ (+ ruido de sensor).
Devuelve filas (vid, comp, day, f, reading, alarmed, failed_today).
"""
function precursor_series(pl; every::Int=14)
    out = NamedTuple[]
    di = 0; D0 = pl.Dcum[1]; a0_D = pl.a0_D; ti = 1
    cv = Precursors.sensor_cv(pl.component)
    af = Precursors.alarm_fraction(pl.component)
    while ti <= length(pl.thresholds)
        Θ = pl.thresholds[ti]
        fday = nothing
        for d in di:pl.ndays
            if pl.Dcum[d + 1] - D0 + a0_D >= Θ; fday = d; break; end
        end
        endd = fday === nothing ? pl.ndays : fday
        bias = max(1 + (pl.pred_noise[min(ti, length(pl.pred_noise))] - 1) * cv, 0.05)
        d = di
        while d <= endd
            f = clamp((pl.Dcum[d + 1] - D0 + a0_D) / Θ, 0.0, 1.0)
            fobs = clamp(f * bias, 0.0, 1.0)                          # fracción OBSERVADA (sensor)
            push!(out, (vid=pl.vehicle_id, comp=pl.component, day=pl.onboard_day + d,
                  f=f, reading=Precursors.reading(pl.component, fobs),
                  alarmed=(fobs >= af), failed=(fday !== nothing && d == fday)))
            d += every
        end
        fday === nothing && break
        di = fday; D0 = pl.Dcum[fday + 1]; a0_D = 0.0; ti += 1
        (!pl.recurrent || fday >= pl.ndays) && break
    end
    return out
end

R = "="^80
println(R); println("MERGE — telemetría de precursores DERIVADA del reloj de daño (un solo estado)"); println(R)
@printf("Flota: %d vehículos · la MISMA f=Dcum/Θ causa la falla Y genera el precursor.\n\n", nv)

# --- congruencia: ¿el precursor alarma ANTES de la falla? (por componente con CBM) ---
println("[CONGRUENCIA] el precursor cruza su alarma física antes del evento de falla:")
@printf("  %-10s %-26s %10s %12s\n", "comp", "señal", "alarma f*", "% avisó antes")
allrows = NamedTuple[]
for comp in ["brake_pad", "dpf", "scr"]            # battery: gated por IFR, sin CBM
    pls = filter(l -> l.component == comp, lives)
    warned = 0; failed = 0
    for pl in pls
        s = precursor_series(pl)
        append!(allrows, s)
        # por cada instancia que falló, ¿hubo alguna lectura 'alarmed' antes del día de falla?
        # agrupamos por tramos entre fallas
        fdays = [r.day for r in s if r.failed]
        for fd in fdays
            failed += 1
            any(r -> r.alarmed && r.day < fd && r.day >= fd - 200, s) && (warned += 1)
        end
    end
    @printf("  %-10s %-26s %9.2f %11.0f%%\n", comp, Precursors.precursor_units(comp),
            Precursors.alarm_fraction(comp), failed > 0 ? 100*warned/failed : 0.0)
end

# --- ejemplo concreto: una balata, su lectura declinando hacia la alarma ---
println("\n[EJEMPLO] una balata: el espesor (mm) declina hacia la alarma (4 mm) y luego falla:")
ex = filter(l -> l.component == "brake_pad", lives)[1]
s = precursor_series(ex)
for r in s[1:min(12, length(s))]
    bar = repeat("█", round(Int, r.reading))
    @printf("  día %4d  f=%.2f  balata=%5.1f mm %s%s\n", r.day, r.f, r.reading, bar,
            r.alarmed ? "  ⚠ ALARMA" : (r.failed ? "  ✗ FALLA" : ""))
end

# --- escribir CSV ---
outdir = joinpath(ROOT, "out", "unified"); mkpath(outdir)
open(joinpath(outdir, "precursor_series.csv"), "w") do io
    println(io, "vehicle_id,component,day,damage_fraction,reading,alarmed,failed")
    for r in allrows
        @printf(io, "%s,%s,%d,%.4f,%.3f,%s,%s\n", r.vid, r.comp, r.day, r.f, r.reading, r.alarmed, r.failed)
    end
end
@printf("\nSerie del precursor (%d filas) → out/unified/precursor_series.csv\n", length(allrows))

# === TELEMETRÍA UNIFICADA: operativas (Powertrain) + precursor, del MISMO sustrato, con frames ===
println("\n", R); println("TELEMETRÍA UNIFICADA — operativas + precursor de un solo sustrato (frames J1939)"); println(R)
vl = vehlives[findfirst(v -> v.class == :heavy_truck, vehlives)]
dyn = Powertrain.dynspec_for(vl.class, vl.engine_kw)
bpl = lives[findfirst(l -> l.vehicle_id == vl.vehicle_id && l.component == "brake_pad", lives)]
bseries = Dict(r.day => r.reading for r in precursor_series(bpl; every=1))
eec1 = first(filter(p -> p.name == "EEC1", SignalRegistry.J1939_PGNS))
et1  = first(filter(p -> p.name == "ET1",  SignalRegistry.J1939_PGNS))
@printf("Vehículo %s (%s, %.0f kW) · corredor speed=%.0f grade=%.1f%%\n",
        vl.vehicle_id, vl.class, vl.engine_kw, vl.route_speed, vl.route_grade)
@printf("  %5s %6s %6s %6s %6s %7s %9s  %s\n", "día", "RPM", "%carga", "coolnt", "EGT", "balata", "round-trip", "")
rtok = true
for d in 30:90:min(vl.ndays, 600)
    vl.eng_h_day[d] == 0 && continue                       # no operó ese día
    s = Powertrain.instant_state(dyn, vl.mass_day[d], vl.route_speed, vl.route_grade,
                                 vl.alt_day[d], vl.ambient_day[d])
    bal = get(bseries, vl.onboard_day + d, NaN)
    # emitir frames operativos y verificar round-trip
    id1, dt1 = encode_pgn(eec1, Dict(190 => s.rpm, 513 => s.torque_pct, 512 => s.driver_demand))
    id2, dt2 = encode_pgn(et1, Dict(110 => s.coolant_set, 175 => s.oil_set))
    ok = isapprox(decode_pgn(eec1, dt1)[190], s.rpm; atol=0.5) &&
         isapprox(decode_pgn(et1, dt2)[110], s.coolant_set; atol=1.0)
    global rtok &= ok
    @printf("  %5d %6.0f %6.0f %6.0f %6.0f %6.1f mm %9s\n",
            d, s.rpm, s.load, s.coolant_set, s.egt_c, bal, ok ? "✓" : "✗")
end
println(rtok ? "\n✓ Frames J1939 round-trip OK. Operativas (Powertrain) Y precursor (Dcm/Θ) del MISMO vehículo/sustrato." :
               "\n⚠ round-trip falló")
println("→ Reloj UNIFICADO: el mismo estado de daño produce la telemetría (operativa+precursor) y las fallas.")
println("  Falta solo el orquestador run_unified.jl (eventos WS-A + telemetría + economía juntos) — ver docs/Arquitectura_Unificada_Merge.md")
