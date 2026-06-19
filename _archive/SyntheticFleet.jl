"""
    SyntheticFleet

Generador de flota SINTÉTICA que mimetiza la realidad, para validar el pipeline de
mantenimiento predictivo contra **verdad conocida** antes de tener datos reales.

Produce:
  - Flota heterogénea (clase → marca → modelo) con parámetros de vida ground-truth.
  - Perfiles de operación (severidad de ruta, horas/día, protocolo j1939/obd2).
  - Telemetría como **frames J1939 reales** (id + 8 bytes) que hacen round-trip exacto
    por el decoder verificado `J1939.jl` (el encoder de aquí es su inverso, round-trip probado).
  - Vidas de componente por un **modelo forward independiente** (Weibull-AFT con covariable
    de ruta), con censura por la derecha, truncamiento por la izquierda y recurrencia (renovación).
  - Eventos conformes al esquema WS-A (entry_age, exit_age, status) y DTCs (DM1) para el
    camino `auto_dtc` del aftertreatment.
  - Ground truth exportable para el loop de recuperación de parámetros.

ANTI-CIRCULARIDAD: el modelo forward de aquí y el ajustador (models/survival.jl) deben ser
implementaciones independientes. El éxito es **recuperar** los parámetros, no que coincidan
por construcción. La lógica estadística está cross-validada en Python (synth_pipeline_demo.py).

Versión 0.1 — esqueleto extensible (ver TODOs). Claude Code lo amplía según el brief, §3–4.
"""
module SyntheticFleet

using Random

export VehicleSpec, EventRec, FleetData, GroundTruth, generate_fleet,
       encode_le, make_frame, make_id, frame_hours, frame_eec1, frame_et1,
       negloglik_aft, negloglik_aft_grouped

# ---------------------------------------------------------------------------
# Encoder J1939 (inverso EXACTO del decoder; round-trip verificado HOURS/EEC1/ET1)
# ---------------------------------------------------------------------------

"Bytes little-endian (Intel) de `raw` (≥0), longitud `n`."
encode_le(raw::Integer, n::Int) = digits(UInt8, raw; base=256, pad=n)

"""
    make_frame(sigs) -> Vector{UInt8}(8)

Construye un frame de 8 bytes. Bytes no usados quedan en 0xFF (no disponible).
`sigs`: vector de tuplas `(start_byte1, n_bytes, scale, offset, phys)` (byte 1-indexado).
"""
function make_frame(sigs::Vector{<:Tuple})
    frame = fill(0xFF, 8)
    for (sb1, n, scale, offset, phys) in sigs
        raw = round(Int, (phys - offset) / scale)
        raw = clamp(raw, 0, (1 << (8n)) - 3)        # evita colisionar con 0xFE/0xFF
        bytes = encode_le(raw, n)
        @inbounds for i in 0:(n - 1)
            frame[sb1 + i] = bytes[i + 1]
        end
    end
    return frame
end

"Identificador extendido de 29 bits para PGN broadcast (PDU2, PF≥240, DP=0)."
make_id(prio::Int, pgn::Int, sa::Int) = UInt32((prio << 26) | ((pgn & 0xFFFF) << 8) | sa)

# Frames de telemetría usados por el generador (round-trip por J1939.jl)
frame_hours(h::Real)     = (make_id(6, 65253, 0), make_frame([(1, 4, 0.05,   0.0,   Float64(h))]))   # SPN 247
frame_eec1(rpm::Real)    = (make_id(3, 61444, 0), make_frame([(4, 2, 0.125,  0.0,   Float64(rpm))])) # SPN 190
frame_et1(coolant::Real) = (make_id(6, 65262, 0), make_frame([(1, 1, 1.0,   -40.0,  Float64(coolant))])) # SPN 110

# ---------------------------------------------------------------------------
# Tipos
# ---------------------------------------------------------------------------

struct VehicleSpec
    vehicle_id::String
    class::Symbol          # :heavy_truck, :light_vehicle, :motorcycle
    brand::String
    model::String
    protocol::Symbol       # :j1939, :obd2
    route_severity::Float64  # covariable x ∈ [0,1]
    hours_per_day::Float64
end

"Evento conforme a la tripleta de supervivencia WS-A."
struct EventRec
    vehicle_id::String
    position::String       # 'component_type@location'
    instance::Int          # n-ésima instancia en la posición (recurrencia)
    entry_age::Float64     # truncamiento por la izquierda (horas-motor)
    exit_age::Float64      # evento o censura
    status::Int            # 0 = censurado ; mode_id (>0) = falla causa-específica
    dtc_spn::Int           # 0 si ninguno (auto_dtc)
    dtc_fmi::Int
end

struct GroundTruth
    beta::Float64
    eta0::Dict{Tuple{Symbol,String},Float64}   # (clase, marca) -> vida característica base
    gamma::Float64                              # efecto AFT de route_severity
end

struct FleetData
    vehicles::Vector{VehicleSpec}
    frames::Vector{Tuple{UInt32,Vector{UInt8}}}
    events::Vector{EventRec}
    truth::GroundTruth
end

# Muestreo Weibull por CDF inversa: L = η·(-ln U)^(1/β), U~U(0,1). Sin dependencias.
@inline weibull(rng, β, η) = η * (-log(rand(rng)))^(1 / β)

# ---------------------------------------------------------------------------
# Generación
# ---------------------------------------------------------------------------

"""
    generate_fleet(; n_vehicles, seed, beta, gamma, window_hours, f_trunc) -> FleetData

Genera la flota sintética. `beta`,`gamma` y los `eta0` por (clase,marca) son la verdad
a recuperar. `f_trunc` = fracción de posiciones con truncamiento por la izquierda.
"""
function generate_fleet(; n_vehicles::Int=80, seed::Int=20260615,
                          beta::Float64=2.3, gamma::Float64=-0.5,
                          window_hours::Float64=2500.0, f_trunc::Float64=0.30)
    rng = MersenneTwister(seed)
    classes = [(:heavy_truck,  ["Freightliner", "Kenworth", "Volvo"], :j1939),
               (:light_vehicle, ["Nissan", "Toyota"],                 :obd2)]

    # Ground truth: vida característica por (clase, marca), con dispersión entre marcas.
    eta0 = Dict{Tuple{Symbol,String},Float64}()
    for (cls, brands, _) in classes, b in brands
        base = cls == :heavy_truck ? 1500.0 : 900.0
        eta0[(cls, b)] = base * (0.85 + 0.30 * rand(rng))
    end
    truth = GroundTruth(beta, eta0, gamma)

    vehicles = VehicleSpec[]
    frames   = Tuple{UInt32,Vector{UInt8}}[]
    events   = EventRec[]

    for k in 1:n_vehicles
        (cls, brands, proto) = classes[rand(rng, 1:length(classes))]
        brand = brands[rand(rng, 1:length(brands))]
        model = string(brand, "-", rand(rng, 100:999))
        x     = rand(rng)                       # severidad de ruta
        hpd   = 4.0 + 6.0 * rand(rng)           # horas-motor/día
        vid   = string("VEH-", lpad(k, 4, '0'))
        push!(vehicles, VehicleSpec(vid, cls, brand, model, proto, x, hpd))

        # --- Telemetría J1939/OBD (con ruido); el ligero entrega MENOS señales ---
        total_hours = window_hours * (0.4 + 0.6 * rand(rng))
        push!(frames, frame_hours(total_hours))
        push!(frames, frame_eec1(clamp(1200 + 400 * randn(rng), 600, 2100)))
        if proto == :j1939                       # mímica de la brecha OBD vs J1939
            push!(frames, frame_et1(clamp(85 + 8 * randn(rng), 60, 110)))
        end

        # --- Vidas de balata (front_left) por modelo forward independiente ---
        eta_i = eta0[(cls, brand)] * exp(gamma * x)       # AFT
        pos   = "brake_pad@front_left"
        W     = window_hours * (0.5 + 0.8 * rand(rng))     # ventana de observación
        a0    = (rand(rng) < f_trunc) ? 0.6 * eta_i * rand(rng) : 0.0   # truncamiento izq.

        L = weibull(rng, beta, eta_i)
        if a0 > 0                                          # condicionar: viva al entrar
            while L <= a0
                L = weibull(rng, beta, eta_i)
            end
        end
        if (L - a0) <= W                                   # 1a instancia falla en ventana
            push!(events, EventRec(vid, pos, 1, a0, L, 1, 0, 0))
            obs  = L - a0
            inst = 2
            while obs < W                                  # renovación (entry=0)
                rem = W - obs
                L = weibull(rng, beta, eta_i)
                if L <= rem
                    push!(events, EventRec(vid, pos, inst, 0.0, L, 1, 0, 0))
                    obs += L
                    inst += 1
                else
                    push!(events, EventRec(vid, pos, inst, 0.0, rem, 0, 0, 0))
                    obs = W
                end
            end
        else                                               # 1a instancia censurada
            push!(events, EventRec(vid, pos, 1, a0, a0 + W, 0, 0, 0))
        end

        # --- Aftertreatment (solo J1939): DM1 antes de la falla (camino auto_dtc) ---
        if cls == :heavy_truck
            eta_dpf = eta0[(cls, brand)]                   # TODO: vida DPF propia (placeholder)
            Ld = weibull(rng, beta, eta_dpf)
            if Ld <= W
                spn, fmi = rand(rng) < 0.5 ? (3251, 16) : (5246, 4)  # ΔP DPF / derate SCR
                push!(events, EventRec(vid, "dpf@exhaust", 1, 0.0, Ld, 2, spn, fmi))
            else
                push!(events, EventRec(vid, "dpf@exhaust", 1, 0.0, W, 0, 0, 0))
            end
        end
    end

    return FleetData(vehicles, frames, events, truth)
end

# ---------------------------------------------------------------------------
# Verosimilitud para el loop de recuperación (Weibull-AFT, censura + truncamiento)
# Espejo exacto del prototipo Python validado. Optimizar con Optim.jl/Survival.jl.
# theta = [log β, log η0, γ];  x = covariable;  t = exit_age;  d = status>0;  a = entry_age.
# ---------------------------------------------------------------------------
function negloglik_aft(theta, x, t, d, a)
    b  = exp(theta[1]); e0 = exp(theta[2]); g = theta[3]
    ll = 0.0
    @inbounds for i in eachindex(t)
        eta = e0 * exp(g * x[i])
        zt  = (t[i] / eta)^b
        za  = a[i] > 0 ? (a[i] / eta)^b : 0.0
        ll += d[i] * (log(b) - b * log(eta) + (b - 1) * log(t[i])) - zt + za
    end
    return -ll
end

"""
    negloglik_aft_grouped(theta, gi, x, t, d, a, G)

Verosimilitud Weibull-AFT **bien especificada**: un `η0` por grupo (clase,marca) + `β,γ`
compartidos. `theta = [log β, γ, log η0_1, …, log η0_G]`; `gi[i] ∈ 1:G` es el grupo de i.

Es el estimador con el que el generador RECUPERA la verdad (validado: β,γ y los η0 por grupo
dentro de ±5–6%). El ajuste de un solo η0 (`negloglik_aft`) está mal especificado cuando η0
varía por grupo y sesga β y γ — esa es la motivación empírica del modelo jerárquico (F4).
"""
function negloglik_aft_grouped(theta, gi, x, t, d, a, G::Int)
    b = exp(theta[1]); g = theta[2]
    ll = 0.0
    @inbounds for i in eachindex(t)
        eta = exp(theta[2 + gi[i]]) * exp(g * x[i])
        zt  = (t[i] / eta)^b
        za  = a[i] > 0 ? (a[i] / eta)^b : 0.0
        ll += d[i] * (log(b) - b * log(eta) + (b - 1) * log(t[i])) - zt + za
    end
    return -ll
end

end # module
