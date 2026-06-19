"""
    WSAWriter — aterriza un `SimOutput` a CSVs alineados con el esquema WS-A (migración 001),
    listos para `\\copy` desde psql, más artefactos de validación (ground truth, supervivencia).

NULLs: se escriben como cadena vacía (compatibles con `COPY ... NULL ''`). `mode_id`, `dtc_*`,
`onset_*` y `removal_time` se emiten como faltantes cuando no aplican (0 / nothing).
"""
module WSAWriter

using DataFrames
using CSV
using Dates

export write_wsa

_nz(x::Int) = x == 0 ? missing : x                       # 0 -> NULL (mode_id, dtc_*)
_od(x) = x === nothing ? missing : x                     # nothing -> NULL (fechas opcionales)

function write_wsa(out, dir::AbstractString)
    mkpath(dir)

    # --- vehicle ---
    veh = DataFrame(
        vehicle_id = [v.vehicle_id for v in out.vehicles],
        class = [String(v.class) for v in out.vehicles],
        brand = [v.brand for v in out.vehicles],
        model = [v.model for v in out.vehicles],
        model_year = [v.model_year for v in out.vehicles],
        gvwr_kg = [v.gvwr_kg for v in out.vehicles],
        diagnostic_protocol = [String(v.protocol) for v in out.vehicles],
        onboarded_at = [v.onboarded_at for v in out.vehicles],
        route_severity = [round(v.route_severity, digits=4) for v in out.vehicles],
        hours_per_day = [round(v.hours_per_day, digits=3) for v in out.vehicles],
    )
    CSV.write(joinpath(dir, "vehicle.csv"), veh)

    # --- position ---
    pos = DataFrame(
        position_id = [p.position_id for p in out.positions],
        vehicle_id = [p.vehicle_id for p in out.positions],
        component_type = [p.component_type for p in out.positions],
        location = [p.location for p in out.positions],
    )
    CSV.write(joinpath(dir, "position.csv"), pos)

    # --- component_instance ---
    inst = DataFrame(
        instance_id = [i.instance_id for i in out.instances],
        position_id = [i.position_id for i in out.instances],
        part_number = [i.part_number for i in out.instances],
        supplier = [i.supplier for i in out.instances],
        install_time = [i.install_time for i in out.instances],
        install_known = [i.install_known for i in out.instances],
        install_engine_h = [round(i.install_engine_h, digits=2) for i in out.instances],
        removal_time = [_od(i.removal_time) for i in out.instances],
    )
    CSV.write(joinpath(dir, "component_instance.csv"), inst)

    # --- event ---
    ev = DataFrame(
        event_id = [e.event_id for e in out.events],
        instance_id = [e.instance_id for e in out.events],
        type = [String(e.type) for e in out.events],
        event_time = [e.event_time for e in out.events],
        onset_lower = [_od(e.onset_lower) for e in out.events],
        onset_upper = [_od(e.onset_upper) for e in out.events],
        engine_h = [round(e.engine_h, digits=2) for e in out.events],
        odo_km = [round(e.odo_km, digits=1) for e in out.events],
        mode_id = [_nz(e.mode_id) for e in out.events],
        restoration_q = [e.restoration_q for e in out.events],
        cost_parts = [round(e.cost_parts, digits=2) for e in out.events],
        cost_labor = [round(e.cost_labor, digits=2) for e in out.events],
        cost_towing = [round(e.cost_towing, digits=2) for e in out.events],
        downtime_h = [round(e.downtime_h, digits=2) for e in out.events],
        in_route = [e.in_route for e in out.events],
        cost_fine = [round(e.cost_fine, digits=2) for e in out.events],
        source = [String(e.source) for e in out.events],
        dtc_spn = [_nz(e.dtc_spn) for e in out.events],
        dtc_fmi = [e.dtc_spn == 0 ? missing : e.dtc_fmi for e in out.events],
    )
    CSV.write(joinpath(dir, "event.csv"), ev)

    # --- usage_snapshot ---
    snap = DataFrame(
        vehicle_id = [s.vehicle_id for s in out.snapshots],
        ts = [s.ts for s in out.snapshots],
        engine_h = [round(s.engine_h, digits=2) for s in out.snapshots],
        odo_km = [round(s.odo_km, digits=1) for s in out.snapshots],
        brake_energy_cum = [round(s.brake_energy_cum, digits=4) for s in out.snapshots],
        rainflow_miner_cum = [round(s.rainflow_miner_cum, digits=4) for s in out.snapshots],
        route_severity = [round(s.route_severity, digits=4) for s in out.snapshots],
    )
    CSV.write(joinpath(dir, "usage_snapshot.csv"), snap)

    # --- telemetría J1939 cruda (muestra; round-trip verificado en test) ---
    fr = DataFrame(
        vehicle_id = [f.vehicle_id for f in out.frames],
        ts = [f.ts for f in out.frames],
        can_id_hex = [string("0x", uppercase(string(f.can_id, base=16))) for f in out.frames],
        data_hex = [join([uppercase(string(b, base=16, pad=2)) for b in f.data], " ") for f in out.frames],
    )
    CSV.write(joinpath(dir, "telemetry_frames.csv"), fr)

    # --- tripleta de supervivencia derivada (la que consume el ajustador) ---
    sv = DataFrame(
        instance_id = [r.instance_id for r in out.survival],
        component_type = [r.component_type for r in out.survival],
        class = [String(r.class) for r in out.survival],
        brand = [r.brand for r in out.survival],
        model = [r.model for r in out.survival],
        route_severity = [round(r.route_severity, digits=4) for r in out.survival],
        entry_age = [round(r.entry_age, digits=3) for r in out.survival],
        exit_age = [round(r.exit_age, digits=3) for r in out.survival],
        status = [r.status for r in out.survival],
        entry_imputed = [r.entry_imputed for r in out.survival],
    )
    CSV.write(joinpath(dir, "survival_records.csv"), sv)

    # --- ground truth (la verdad a recuperar) ---
    rows = NamedTuple[]
    for (k, v) in out.truth.eta0
        cls, brand, comp = k
        c = out.truth.comp[comp]
        push!(rows, (class=String(cls), brand=brand, component=comp,
                     beta=c.beta, gamma=c.gamma, eta0=round(v, digits=2), cp=c.cp, cf=c.cf))
    end
    gt = sort(DataFrame(rows), [:component, :class, :brand])
    CSV.write(joinpath(dir, "ground_truth.csv"), gt)

    return dir
end

end # module
