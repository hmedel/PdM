"""
    SignalRegistry

Catálogo amplio de señales **J1939 (pesado)** y **OBD-II (ligero)** para la simulación de
telemetría, con **encode + decode round-trip consistente**. Es la capa de "contrato de bus":
la micro-simulación física produce valores; aquí se empaquetan en frames CAN reales y se pueden
decodificar de vuelta (round-trip exacto).

HONESTIDAD DE LAYOUT (Brief §1.4 — no inventar layouts como verdad): los SPN/PID y sus escalas/
offsets siguen J1939-71 / OBD-II estándar donde se conocen (`verified=true`), pero varios layouts
de byte son **internos a la simulación** (`verified=false`): hacen round-trip por construcción, pero
deben confirmarse contra un DBC/J1939-71 autoritativo antes de decodificar buses reales. El
postratamiento (DPF/SCR/NOx) lleva PGNs marcados a-confirmar a propósito.

Cobertura J1939: powertrain (RPM, par, carga, pedal, velocidad, marcha), térmicas/fluidos
(refrigerante, aceite, combustible, boost, EGT, filtro de aire), combustible/economía, eléctrico
(batería/alternador), ambiente (temp/baro), postratamiento (DPF ΔP/hollín, NOx in/out, DEF, derate),
chasis (TPMS presión/temp de llanta, carga por eje, presión de freno). OBD-II: el subconjunto que
expone un vehículo ligero (la brecha de menos señales es real).
"""
module SignalRegistry

export J1939Signal, PGNDef, J1939_PGNS, OBDSignal, OBD_PIDS,
       encode_pgn, decode_pgn, encode_obd, decode_obd, make_id, pgn_for_spn

# ---------------------------------------------------------------------------
# J1939
# ---------------------------------------------------------------------------

"Señal J1939 (SPN). `start_byte`/`len_bytes` 1-indexado (posición de byte J1939). LE; valor = scale·raw + offset."
struct J1939Signal
    spn::Int
    name::String
    start_byte::Int
    len_bytes::Int
    scale::Float64
    offset::Float64
    unit::String
    verified::Bool      # true solo si el layout sigue J1939-71 confirmado; false ⇒ confirmar vs DBC
end

struct PGNDef
    pgn::Int
    name::String
    priority::Int
    signals::Vector{J1939Signal}
end

# Catálogo de PGNs. Layouts estándar marcados verified=true; el resto interno-a-simulación.
const J1939_PGNS = PGNDef[
    PGNDef(61444, "EEC1", 3, [
        J1939Signal(190, "Engine Speed",              4, 2, 0.125,   0.0,   "rpm",  true),
        J1939Signal(513, "Actual Engine Torque",      3, 1, 1.0,   -125.0,  "%",    true),
        J1939Signal(512, "Driver Demand Torque",      2, 1, 1.0,   -125.0,  "%",    true),
    ]),
    PGNDef(61443, "EEC2", 3, [
        J1939Signal(91,  "Accelerator Pedal Pos",     2, 1, 0.4,     0.0,   "%",    true),
        J1939Signal(92,  "Engine Percent Load",       3, 1, 1.0,     0.0,   "%",    true),
    ]),
    PGNDef(65265, "CCVS", 6, [
        J1939Signal(84,  "Wheel-Based Vehicle Speed", 2, 2, 1/256,   0.0,   "km/h", true),
    ]),
    PGNDef(65262, "ET1", 6, [
        J1939Signal(110, "Engine Coolant Temp",       1, 1, 1.0,    -40.0,  "degC", true),
        J1939Signal(174, "Fuel Temperature",          2, 1, 1.0,    -40.0,  "degC", true),
        J1939Signal(175, "Engine Oil Temp",           3, 2, 0.03125,-273.0, "degC", true),
    ]),
    PGNDef(65263, "EFL/P1", 6, [
        J1939Signal(100, "Engine Oil Pressure",       4, 1, 4.0,     0.0,   "kPa",  true),
        J1939Signal(98,  "Engine Oil Level",          3, 1, 0.4,     0.0,   "%",    false),
        J1939Signal(111, "Coolant Level",             8, 1, 0.4,     0.0,   "%",    false),
    ]),
    PGNDef(65266, "LFE", 6, [
        J1939Signal(183, "Engine Fuel Rate",          1, 2, 0.05,    0.0,   "L/h",  true),
        J1939Signal(184, "Instantaneous Fuel Economy",3, 2, 1/512,   0.0,   "km/L", true),
        J1939Signal(51,  "Throttle Position",         8, 1, 0.4,     0.0,   "%",    false),
    ]),
    PGNDef(65270, "IC1", 6, [
        J1939Signal(107, "Air Filter Diff Pressure",  1, 1, 0.05,    0.0,   "kPa",  false),
        J1939Signal(102, "Boost (Intake Manif) Press",2, 1, 2.0,     0.0,   "kPa",  true),
        J1939Signal(105, "Intake Manifold Temp",      3, 1, 1.0,    -40.0,  "degC", true),
        J1939Signal(173, "Exhaust Gas Temp",          5, 2, 0.03125,-273.0, "degC", true),
    ]),
    PGNDef(65253, "HOURS", 6, [
        J1939Signal(247, "Engine Total Hours",        1, 4, 0.05,    0.0,   "h",    true),
        J1939Signal(249, "Engine Total Revolutions",  5, 4, 1000.0,  0.0,   "r",    false),
    ]),
    PGNDef(65248, "VD", 6, [
        J1939Signal(245, "Total Vehicle Distance",    1, 4, 0.125,   0.0,   "km",   true),
    ]),
    PGNDef(65271, "VEP1", 6, [
        J1939Signal(167, "Charging System Potential", 3, 2, 0.05,    0.0,   "V",    false),
        J1939Signal(168, "Battery Potential",         5, 2, 0.05,    0.0,   "V",    true),
    ]),
    PGNDef(65269, "AMB", 6, [
        J1939Signal(108, "Barometric Pressure",       1, 1, 0.5,     0.0,   "kPa",  true),
        J1939Signal(171, "Ambient Air Temperature",   4, 2, 0.03125,-273.0, "degC", true),
    ]),
    PGNDef(65267, "VW", 6, [   # carga por eje (peso) — SPN 178/179 (decisión abierta Brief §8.6)
        J1939Signal(180, "Axle Weight (front)",       1, 2, 0.5,     0.0,   "kg",   false),
        J1939Signal(181, "Axle Weight (drive)",       3, 2, 0.5,     0.0,   "kg",   false),
    ]),
    # ---- Postratamiento: SPN verificados, PGN/layout A CONFIRMAR (verified=false) ----
    PGNDef(64948, "DPFC1", 6, [
        J1939Signal(3251, "DPF Differential Pressure", 1, 2, 0.0078125, 0.0, "kPa", false),
        J1939Signal(3719, "DPF Soot Load",             3, 1, 0.4,     0.0,   "%",   false),
    ]),
    PGNDef(61454, "AT1 NOx", 6, [
        J1939Signal(3216, "NOx Inlet",                 1, 2, 0.05,  -200.0,  "ppm", false),
        J1939Signal(3226, "NOx Outlet",                3, 2, 0.05,  -200.0,  "ppm", false),
    ]),
    PGNDef(65110, "AT1 DEF", 6, [
        J1939Signal(1761, "DEF Tank Level",            1, 1, 0.4,     0.0,   "%",   false),
        J1939Signal(5246, "SCR Operator Inducement",   2, 1, 1.0,     0.0,   "-",   false),
    ]),
    PGNDef(65268, "TIRE", 6, [   # TPMS: una llanta por mensaje (location en byte 1)
        J1939Signal(929, "Tire Location",              1, 1, 1.0,     0.0,   "-",   false),
        J1939Signal(241, "Tire Pressure",              2, 1, 4.0,     0.0,   "kPa", false),
        J1939Signal(242, "Tire Temperature",           4, 2, 0.03125,-273.0, "degC", false),
    ]),
    # ---- Precursores de falla (PdM): escalas J1939-71 donde se conocen; layout interno a confirmar ----
    PGNDef(65251, "CCP", 6, [                 # presión de cárter (blowby — desgaste de anillos)
        J1939Signal(101, "Crankcase Pressure",         1, 1, 0.05,    0.0,   "kPa", false),
    ]),
    PGNDef(65243, "FLTR", 6, [                # ΔP de filtros (obstrucción → servicio)
        J1939Signal(99,  "Engine Oil Filter Diff Press", 1, 1, 1.0,   0.0,   "kPa", false),
        J1939Signal(95,  "Fuel Filter Diff Pressure",    2, 1, 1.0,   0.0,   "kPa", false),
        J1939Signal(107, "Air Filter 1 Diff Pressure",   3, 1, 0.05,  0.0,   "kPa", false),
    ]),
    PGNDef(65176, "TC1", 6, [                 # turbocompresor
        J1939Signal(103, "Turbocharger 1 Speed",       1, 2, 4.0,     0.0,   "rpm", false),
        J1939Signal(52,  "Intercooler (CAC) Temp",     3, 1, 1.0,    -40.0,  "degC", false),
    ]),
    PGNDef(65198, "AIR1", 6, [                # presión de aire de frenos (reservorios)
        J1939Signal(117, "Brake Circuit 1 Air Press",  1, 1, 8.0,     0.0,   "kPa", false),
        J1939Signal(118, "Brake Circuit 2 Air Press",  2, 1, 8.0,     0.0,   "kPa", false),
    ]),
    PGNDef(65272, "TF1", 6, [                 # transmisión
        J1939Signal(177, "Transmission Oil Temp",      5, 2, 0.03125,-273.0, "degC", false),
    ]),
    PGNDef(64892, "DPF2", 6, [                # ceniza DPF (permanente — limita vida del DPF)
        J1939Signal(3720, "DPF Ash Load",              1, 1, 0.4,     0.0,   "%",   false),
    ]),
    PGNDef(65257, "LFC", 6, [                 # combustible total y horas/combustible de ralentí
        J1939Signal(250, "Total Fuel Used",            5, 4, 0.5,     0.0,   "L",   false),
    ]),
    PGNDef(65244, "IO", 6, [
        J1939Signal(235, "Total Idle Hours",           1, 4, 0.05,    0.0,   "h",   false),
        J1939Signal(236, "Total Idle Fuel Used",       5, 4, 0.5,     0.0,   "L",   false),
    ]),
]

const _SPN_PGN = Dict(s.spn => p.pgn for p in J1939_PGNS for s in p.signals)
pgn_for_spn(spn::Int) = get(_SPN_PGN, spn, 0)

"Identificador extendido de 29 bits para PGN broadcast (PDU2)."
make_id(prio::Int, pgn::Int, sa::Int=0) = UInt32((prio << 26) | ((pgn & 0xFFFF) << 8) | sa)

_encode_le(raw::Integer, n::Int) = digits(UInt8, raw; base=256, pad=n)

"""
    encode_pgn(pgndef, values; sa=0) -> (can_id, data::Vector{UInt8})

Empaqueta los SPN presentes en `values` (spn => valor físico) en un frame de 8 bytes (LE).
Bytes no usados = 0xFF (no disponible).
"""
function encode_pgn(pgndef::PGNDef, values::Dict{Int,<:Real}; sa::Int=0)
    data = fill(0xFF, 8)
    for s in pgndef.signals
        haskey(values, s.spn) || continue
        raw = round(Int, (values[s.spn] - s.offset) / s.scale)
        raw = clamp(raw, 0, (1 << (8 * s.len_bytes)) - 3)   # evita 0xFE/0xFF (error/NA)
        bytes = _encode_le(raw, s.len_bytes)
        @inbounds for i in 0:(s.len_bytes - 1)
            data[s.start_byte + i] = bytes[i + 1]
        end
    end
    return make_id(pgndef.priority, pgndef.pgn, sa), data
end

_extract_le(data, sb, n) = (raw = UInt64(0); for i in 0:(n-1); raw |= UInt64(data[sb+i]) << (8i); end; raw)
_is_na(raw, n) = (allff = (UInt64(1) << (8n)) - 1; raw == allff || raw == allff - 1)

"""
    decode_pgn(pgndef, data) -> Dict{Int,Union{Float64,Missing}}

Decodifica todos los SPN del PGN. `missing` si el valor es no-disponible/error.
"""
function decode_pgn(pgndef::PGNDef, data::AbstractVector{UInt8})
    out = Dict{Int,Union{Float64,Missing}}()
    for s in pgndef.signals
        raw = _extract_le(data, s.start_byte, s.len_bytes)
        out[s.spn] = _is_na(raw, s.len_bytes) ? missing : s.scale * Float64(raw) + s.offset
    end
    return out
end

# ---------------------------------------------------------------------------
# OBD-II (Modo 01 — datos en tiempo real). Fórmulas SAE J1979 estándar.
# ---------------------------------------------------------------------------

"Señal OBD-II (PID Modo 01). `enc`/`dec` mapean valor físico ↔ bytes de dato."
struct OBDSignal
    pid::UInt8
    name::String
    n_bytes::Int
    enc::Function       # phys -> Vector{UInt8}
    dec::Function       # Vector{UInt8} -> phys
    unit::String
end

# helpers para fórmulas estándar A, B (256A+B)
_one(f_dec, f_enc) = (OBDSignal) # placeholder (no usado)
_A(v) = UInt8[clamp(round(Int, v), 0, 255)]
_AB(v) = (r = clamp(round(Int, v), 0, 65535); UInt8[r >> 8, r & 0xFF])

const OBD_PIDS = Dict{UInt8,OBDSignal}(
    0x04 => OBDSignal(0x04, "Calculated Engine Load", 1, v->_A(v*255/100),        b->b[1]*100/255,        "%"),
    0x05 => OBDSignal(0x05, "Engine Coolant Temp",    1, v->_A(v+40),             b->Float64(b[1])-40,    "degC"),
    0x0C => OBDSignal(0x0C, "Engine RPM",             2, v->_AB(v*4),             b->(256*b[1]+b[2])/4,   "rpm"),
    0x0D => OBDSignal(0x0D, "Vehicle Speed",          1, v->_A(v),                b->Float64(b[1]),       "km/h"),
    0x0E => OBDSignal(0x0E, "Timing Advance",         1, v->_A((v+64)*2),         b->b[1]/2-64,           "deg"),
    0x0F => OBDSignal(0x0F, "Intake Air Temp",        1, v->_A(v+40),             b->Float64(b[1])-40,    "degC"),
    0x10 => OBDSignal(0x10, "MAF Air Flow Rate",      2, v->_AB(v*100),           b->(256*b[1]+b[2])/100, "g/s"),
    0x11 => OBDSignal(0x11, "Throttle Position",      1, v->_A(v*255/100),        b->b[1]*100/255,        "%"),
    0x1F => OBDSignal(0x1F, "Run Time Since Start",   2, v->_AB(v),               b->Float64(256*b[1]+b[2]), "s"),
    0x2F => OBDSignal(0x2F, "Fuel Tank Level",        1, v->_A(v*255/100),        b->b[1]*100/255,        "%"),
    0x33 => OBDSignal(0x33, "Barometric Pressure",    1, v->_A(v),                b->Float64(b[1]),       "kPa"),
    0x42 => OBDSignal(0x42, "Control Module Voltage", 2, v->_AB(v*1000),          b->(256*b[1]+b[2])/1000,"V"),
    0x46 => OBDSignal(0x46, "Ambient Air Temp",       1, v->_A(v+40),             b->Float64(b[1])-40,    "degC"),
    0x5C => OBDSignal(0x5C, "Engine Oil Temp",        1, v->_A(v+40),             b->Float64(b[1])-40,    "degC"),
    0x5E => OBDSignal(0x5E, "Engine Fuel Rate",       2, v->_AB(v*20),            b->(256*b[1]+b[2])/20,  "L/h"),
    # ---- Precursores PdM (OBD-II) ----
    0x0B => OBDSignal(0x0B, "Intake Manifold Abs Press",1, v->_A(v),             b->Float64(b[1]),        "kPa"),
    0x06 => OBDSignal(0x06, "Short Term Fuel Trim B1", 1, v->_A((v+100)*1.28),    b->b[1]/1.28-100,       "%"),
    0x07 => OBDSignal(0x07, "Long Term Fuel Trim B1",  1, v->_A((v+100)*1.28),    b->b[1]/1.28-100,       "%"),
    0x22 => OBDSignal(0x22, "Fuel Rail Pressure",      2, v->_AB(v/0.079),        b->(256*b[1]+b[2])*0.079,"kPa"),
    0x2C => OBDSignal(0x2C, "Commanded EGR",           1, v->_A(v*255/100),       b->b[1]*100/255,        "%"),
    0x43 => OBDSignal(0x43, "Absolute Load Value",     2, v->_AB(v*255/100),      b->(256*b[1]+b[2])*100/255,"%"),
    0x3C => OBDSignal(0x3C, "Catalyst Temp B1S1",      2, v->_AB((v+40)*10),      b->(256*b[1]+b[2])/10-40,"degC"),
    0x31 => OBDSignal(0x31, "Dist Since Codes Cleared",2, v->_AB(v),              b->Float64(256*b[1]+b[2]),"km"),
)

"Codifica un PID a sus bytes de dato (respuesta Modo 01)."
encode_obd(sig::OBDSignal, phys::Real) = sig.enc(Float64(phys))
"Decodifica los bytes de dato de un PID."
decode_obd(sig::OBDSignal, data::AbstractVector{UInt8}) = sig.dec(data)

end # module
