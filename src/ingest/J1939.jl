"""
    J1939

Decodificador SAE J1939 para el edge/servidor del módulo de mantenimiento predictivo.

Alcance de esta versión (0.1):
  - Extracción de PGN y Source Address desde el identificador extendido de 29 bits (PDU1/PDU2).
  - Decodificación de señales (SPN) little-endian con escala/offset y manejo de
    valores "no disponible" (0xFF..) y "error" (0xFE..).
  - Unpacking de DTC en DM1/DM2 (método de conversión versión 4): SPN+FMI+OC+CM.

DISEÑO (honesto): el NÚCLEO de decodificación está verificado (ver test/test_J1939.jl,
vectores cross-validados). El DICCIONARIO de señales NO se hardcodea de memoria: se carga
desde una fuente autoritativa (J1939-71 o un DBC del OEM) vía `load_registry!`. La semilla
`SEED_SIGNALS` incluye solo unas pocas señales; las marcadas `verified=false` deben
confirmarse contra J1939-71/DBC antes de producción, y las de aftertreatment llevan `pgn=0`
(PGN a confirmar) a propósito, para no inventar layouts.

NO cubierto aún (TODO): reensamblado multipaquete (J1939-21 TP.CM/TP.DT y BAM) necesario
para DM1 con varios DTC; PGN destino-específicas con direccionamiento; PPID/PSID propietarios.
"""
module J1939

export Signal, DTC, pgn_and_sa, decode_signal, decode_dm1, decode_frame,
       SEED_SIGNALS, load_registry!

# ---------------------------------------------------------------------------
# Tipos
# ---------------------------------------------------------------------------

"""
    Signal

Definición de una señal J1939 (SPN) dentro de un PGN.

`start_byte` y `len_bytes` usan **posición de byte J1939 1-indexada** (byte 1..8),
que coincide con el indexado 1-based de Julia: "bytes 4-5" ⇒ `start_byte=4, len_bytes=2`.
`scale`/`offset`: valor_físico = scale * raw + offset.
`verified`: true solo si el layout está probado por test; false ⇒ confirmar contra J1939-71/DBC.
"""
struct Signal
    spn::Int
    name::String
    pgn::Int            # 0 ⇒ PGN a confirmar (no se decodifica hasta poblarlo)
    start_byte::Int     # 1-indexado (J1939 byte position)
    len_bytes::Int
    scale::Float64
    offset::Float64
    unit::String
    verified::Bool
end

"Diagnostic Trouble Code decodificado de DM1/DM2."
struct DTC
    spn::Int
    fmi::Int    # Failure Mode Identifier (0..31)
    oc::Int     # Occurrence Count (0..127)
    cm::Int     # SPN Conversion Method bit
end

# PGNs de diagnóstico
const PGN_DM1 = 65226   # 0xFECA  Active DTCs
const PGN_DM2 = 65227   # 0xFECB  Previously Active DTCs

# ---------------------------------------------------------------------------
# Núcleo de decodificación (verificado por test)
# ---------------------------------------------------------------------------

"""
    pgn_and_sa(idext::UInt32) -> (pgn::Int, sa::Int)

Extrae PGN y Source Address del identificador extendido de 29 bits.
PDU1 (PF < 240): destino-específico, PS (destino) NO entra al PGN.
PDU2 (PF ≥ 240): broadcast, PS es la extensión de grupo (entra al PGN).
"""
function pgn_and_sa(idext::UInt32)
    sa  = Int(idext & 0xFF)
    ps  = Int((idext >> 8)  & 0xFF)
    pf  = Int((idext >> 16) & 0xFF)
    dp  = Int((idext >> 24) & 0x01)
    edp = Int((idext >> 25) & 0x01)
    pgn = if pf < 240
        (edp << 17) | (dp << 16) | (pf << 8)
    else
        (edp << 17) | (dp << 16) | (pf << 8) | ps
    end
    return (pgn, sa)
end

"Extrae un entero sin signo little-endian (Intel) de `len_bytes` desde `start_byte` (1-indexado)."
function extract_le(data::AbstractVector{UInt8}, start_byte::Int, len_bytes::Int)
    raw = UInt64(0)
    @inbounds for i in 0:(len_bytes - 1)
        raw |= UInt64(data[start_byte + i]) << (8 * i)
    end
    return raw
end

"true si el valor crudo es 'no disponible' (0xFF..) o 'error' (0xFE.. en el último byte)."
function is_na_or_error(raw::UInt64, len_bytes::Int)
    allff = (UInt64(1) << (8 * len_bytes)) - 1
    return raw == allff || raw == allff - 1
end

"""
    decode_signal(data, sig::Signal) -> Union{Float64,Missing}

Decodifica una señal. Devuelve `missing` si el valor es no-disponible/error o si `sig.pgn==0`.
"""
function decode_signal(data::AbstractVector{UInt8}, sig::Signal)
    sig.pgn == 0 && return missing
    raw = extract_le(data, sig.start_byte, sig.len_bytes)
    is_na_or_error(raw, sig.len_bytes) && return missing
    return sig.scale * Float64(raw) + sig.offset
end

"""
    decode_dm1(data) -> Vector{DTC}

Decodifica DTCs de un payload DM1/DM2 (ya reensamblado): 2 bytes de lámparas y luego
DTCs de 4 bytes (método de conversión v4). Ignora relleno (0x0000.. / 0xFFFF..).
"""
function decode_dm1(data::AbstractVector{UInt8})
    dtcs = DTC[]
    length(data) < 6 && return dtcs        # 2 lámparas + al menos 1 DTC
    k = 3                                   # primer byte de DTC (1-indexado)
    while k + 3 <= length(data)
        b0, b1, b2, b3 = data[k], data[k+1], data[k+2], data[k+3]
        if !((b0 == 0x00 && b1 == 0x00 && b2 == 0x00 && b3 == 0x00) ||
             (b0 == 0xFF && b1 == 0xFF && b2 == 0xFF && b3 == 0xFF))
            spn = Int(b0) | (Int(b1) << 8) | (((Int(b2) >> 5) & 7) << 16)
            fmi = Int(b2) & 31
            cm  = (Int(b3) >> 7) & 1
            oc  = Int(b3) & 127
            push!(dtcs, DTC(spn, fmi, oc, cm))
        end
        k += 4
    end
    return dtcs
end

# ---------------------------------------------------------------------------
# Registro de señales + decodificación de frame completo
# ---------------------------------------------------------------------------

# Semilla mínima. verified=true solo donde está probado por test.
# Aftertreatment con pgn=0 a propósito (PGN a confirmar contra J1939-71/DBC, NO inventar).
const SEED_SIGNALS = Dict{Int,Signal}(
    # EEC1 — PGN 61444 (0xF004)
    190 => Signal(190, "Engine Speed",              61444, 4, 2, 0.125,   0.0,   "rpm",  true),
    91  => Signal(91,  "Accelerator Pedal Pos 1",   61444, 2, 1, 0.4,     0.0,   "%",    false),
    92  => Signal(92,  "Engine Percent Load",       61444, 3, 1, 1.0,     0.0,   "%",    false),
    # ET1 — PGN 65262 (0xFEEE)
    110 => Signal(110, "Engine Coolant Temp",       65262, 1, 1, 1.0,    -40.0,  "degC", true),
    175 => Signal(175, "Engine Oil Temp 1",         65262, 3, 2, 0.03125,-273.0, "degC", false),
    # LFE — PGN 65266 (0xFEF2)
    183 => Signal(183, "Engine Fuel Rate",          65266, 1, 2, 0.05,    0.0,   "L/h",  false),
    # EFL/P1 — PGN 65263 (0xFEEF)
    100 => Signal(100, "Engine Oil Pressure",       65263, 4, 1, 4.0,     0.0,   "kPa",  false),
    98  => Signal(98,  "Engine Oil Level",          65263, 3, 1, 0.4,     0.0,   "%",    false),
    # HOURS — PGN 65253 (0xFEE5)
    247 => Signal(247, "Engine Total Hours",        65253, 1, 4, 0.05,    0.0,   "h",    false),
    # VD — PGN 65248 (0xFEE0)
    245 => Signal(245, "Total Vehicle Distance",    65248, 5, 4, 0.125,   0.0,   "km",   false),
    # VEP1 — PGN 65271 (0xFEF7)
    168 => Signal(168, "Battery Potential",         65271, 5, 2, 0.05,    0.0,   "V",    false),
    # ---- Aftertreatment: SPN verificados, PGN/layout A CONFIRMAR (pgn=0) ----
    3251 => Signal(3251, "DPF Differential Pressure", 0, 0, 0, 1.0, 0.0, "kPa", false),
    1761 => Signal(1761, "DEF Tank Level",            0, 0, 0, 0.4, 0.0, "%",   false),
    5246 => Signal(5246, "SCR Operator Inducement",   0, 0, 0, 1.0, 0.0, "-",   false),
)

"""
    load_registry!(reg, rows)

Puebla/actualiza un registro de señales desde filas autoritativas (DBC/J1939-71).
Cada fila es una `Signal`. Pensado para cargar desde CSV/DBC en el arranque del servicio.
"""
function load_registry!(reg::Dict{Int,Signal}, rows)
    for s in rows
        reg[s.spn] = s
    end
    return reg
end

"""
    decode_frame(idext, data; registry=SEED_SIGNALS)
        -> (pgn, sa, signals::Dict{Int,Union{Float64,Missing}}, dtcs::Vector{DTC})

Decodifica un frame completo: si el PGN es DM1/DM2 devuelve los DTCs; en otro caso
decodifica todas las señales del registro cuyo PGN coincide.
"""
function decode_frame(idext::UInt32, data::AbstractVector{UInt8}; registry=SEED_SIGNALS)
    pgn, sa = pgn_and_sa(idext)
    sigs = Dict{Int,Union{Float64,Missing}}()
    dtcs = DTC[]
    if pgn == PGN_DM1 || pgn == PGN_DM2
        dtcs = decode_dm1(data)
    else
        for (spn, sig) in registry
            sig.pgn == pgn || continue
            sigs[spn] = decode_signal(data, sig)
        end
    end
    return (pgn=pgn, sa=sa, signals=sigs, dtcs=dtcs)
end

end # module
