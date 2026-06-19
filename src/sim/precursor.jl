"""
    Precursors

**Fuente ÚNICA de verdad del mapeo degradación → señal observable.** Cierra la congruencia entre
los dos relojes: la MISMA fracción de daño `f ∈ [0,1]` (f=0 pieza nueva, f=1 falla) que cruza el
umbral Weibull en `LifeProcess` produce — por este mapa — la señal física que (a) ve la telemetría
(`TelemetrySim`/`Diagnostics`) y (b) dispara el CBM (`Policy`). Antes había dos relojes paralelos;
ahora el precursor que el CBM observa ES el observable de la degradación que causa la falla.

Cada componente: el precursor es un mapa monótono de `f` a una lectura física, con un umbral de
**alarma físico**; de ahí se deriva la fracción de daño de alarma `f* = (alarma−nuevo)/(falla−nuevo)`,
que es lo que el CBM usa (con ruido de sensor). Así `alarm_frac` deja de ser un número abstracto:
es "balata < 4 mm", "ΔP DPF > 15 kPa", "derate SCR > 0.92".
"""
module Precursors

export PInfo, PRECURSOR_INFO, reading, alarm_fraction, sensor_cv, precursor_units

"Mapa físico del precursor de un componente (lineal en la fracción de daño f)."
struct PInfo
    component::String
    signal::String       # nombre/unidad de la señal (telemetría)
    new_val::Float64     # lectura a f=0 (pieza nueva)
    fail_val::Float64    # lectura a f=1 (falla)
    alarm_val::Float64   # umbral físico de alarma (entre nuevo y falla)
    cv::Float64          # ruido relativo del sensor (detectabilidad)
end

# Calibrado a señales reales (ver Sustento_Fisico_Telemetria.md): balata FMCSA, ΔP DPF, derate SCR.
const PRECURSOR_INFO = Dict{String,PInfo}(
    "brake_pad" => PInfo("brake_pad", "espesor de balata (mm)",        18.0,  1.6,  4.0,  0.6),
    "dpf"       => PInfo("dpf",       "ΔP DPF (kPa)",                    3.0, 22.0, 15.0,  1.0),
    "scr"       => PInfo("scr",       "índice de derate SCR (0–1)",      0.0,  1.0,  0.92, 1.4),
    "battery"   => PInfo("battery",   "voltaje de arranque (V)",        12.6,  8.5,  9.6,  1.0),
    # --- señales NO-lifed (sin componente de falla en LifeProcess; mapa f→señal para telemetría) ---
    # Rangos alineados a Diagnostics.diagnostic_signals para que ambas capas (decisión vs generador
    # standalone) coincidan en magnitudes; NO es un paso de migración — son capas separadas a propósito.
    "oil_filter"  => PInfo("oil_filter",  "ΔP filtro de aceite (kPa)",      45.0, 320.0, 200.0, 1.0),
    "fuel_filter" => PInfo("fuel_filter", "ΔP filtro de combustible (kPa)", 18.0, 220.0, 150.0, 1.0),
    "air_filter"  => PInfo("air_filter",  "ΔP filtro de aire (kPa)",         1.0,   8.0,   6.0, 1.0),
    "crankcase"   => PInfo("crankcase",   "presión de cárter / blowby (kPa)",0.3,  12.0,   8.0, 1.2),
    "turbo"       => PInfo("turbo",       "déficit de boost del turbo (%)",  0.0,  30.0,  20.0, 1.2),
    # --- componentes lifeados añadidos 2026-06-18 (umbrales [reconfirmar] contra PDF OEM/J1939-71) ---
    # cooling: temp refrigerante SUBE; alarma 110°C [reconfirmar Cummins >230°F]. SPN 110.
    "cooling"     => PInfo("cooling",     "temp refrigerante (°C)",         88.0, 118.0, 110.0, 0.5),
    # egr: temp EGR SUBE con cooler degradado; alarma 293°C [reconfirmar Cummins ISX15 >560°F]. SPN 412.
    "egr"         => PInfo("egr",         "temp EGR (°C)",                 250.0, 340.0, 293.0, 1.0),
    # fuel_system: presión BAJA con filtro tapado/bomba débil; alarma 280 kPa [reconfirmar]. SPN 94.
    "fuel_system" => PInfo("fuel_system", "presión de combustible (kPa)",  450.0, 180.0, 280.0, 1.0),
    # oil: presión de aceite BAJA; alarma 110 kPa (~16 psi) [reconfirmar Cummins]. SPN 100 (+ lab off-board).
    "oil"         => PInfo("oil",         "presión de aceite (kPa)",       350.0,  90.0, 110.0, 0.8),
    # air_system: presión de depósito BAJA; alarma 414 kPa (~60 psi) [reconfirmar FMVSS 121]. SPN 117/118.
    "air_system"  => PInfo("air_system",  "presión de depósito (kPa)",     830.0, 380.0, 414.0, 1.0),
)

"Lectura física del precursor a fracción de daño `f` (sin ruido)."
function reading(comp::AbstractString, f::Real)
    p = PRECURSOR_INFO[comp]
    return p.new_val + clamp(f, 0.0, 1.0) * (p.fail_val - p.new_val)
end

"Fracción de daño `f*` a la que la lectura cruza el umbral de alarma físico."
function alarm_fraction(comp::AbstractString)
    p = PRECURSOR_INFO[comp]
    return clamp((p.alarm_val - p.new_val) / (p.fail_val - p.new_val), 0.0, 1.0)
end

sensor_cv(comp::AbstractString) = PRECURSOR_INFO[comp].cv
precursor_units(comp::AbstractString) = PRECURSOR_INFO[comp].signal

end # module
