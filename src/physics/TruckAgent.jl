"""
    TruckAgent

Tipos de camión (agentes) con su física básica: masa en vacío, carga útil máxima, ejes, potencia,
protocolo de diagnóstico. La **carga por viaje** es variable (cargado de ida, a menudo vacío de
regreso) — un driver real de variabilidad en el daño (más masa ⇒ más energía de frenado y fatiga).
"""
module TruckAgent

using Random

export TruckType, TRUCK_TYPES, sample_payload, mass_factor

struct TruckType
    name::String
    class::Symbol            # :heavy_truck | :light_vehicle
    brands::Vector{String}
    curb_kg::Float64
    payload_max_kg::Float64
    n_axles::Int
    engine_kw::Float64
    protocol::Symbol         # :j1939 | :obd2
    brake_positions::Vector{String}
end

const TRUCK_TYPES = TruckType[
    TruckType("Class8_Sleeper", :heavy_truck, ["Freightliner", "Kenworth", "Volvo"],
              8500.0, 19000.0, 5, 360.0, :j1939,
              ["steer_left", "steer_right", "drive_axle_left", "drive_axle_right"]),
    TruckType("Class8_DayCab", :heavy_truck, ["Freightliner", "Kenworth", "Volvo"],
              8000.0, 17000.0, 5, 330.0, :j1939,
              ["steer_left", "steer_right", "drive_axle_left", "drive_axle_right"]),
    TruckType("Class67_Medium", :heavy_truck, ["Freightliner", "Volvo"],
              5200.0, 8000.0, 3, 210.0, :j1939,
              ["front_left", "front_right", "rear_left", "rear_right"]),
    TruckType("LightVan", :light_vehicle, ["Nissan", "Toyota"],
              2200.0, 1300.0, 2, 110.0, :obd2,
              ["front_left", "front_right"]),
]

"""
    sample_payload(rng, t; loaded) -> kg

Carga útil del viaje. Si `loaded`, fracción alta de la capacidad (con dispersión); si no,
deadhead casi vacío. La probabilidad de ir cargado modela el patrón ida-cargado/vuelta-vacío.
"""
function sample_payload(rng::AbstractRNG, t::TruckType; loaded::Bool=true)
    if loaded
        return t.payload_max_kg * clamp(0.55 + 0.45 * rand(rng), 0.0, 1.0)
    else
        return t.payload_max_kg * 0.10 * rand(rng)
    end
end

"Factor de masa del viaje (masa total / masa de referencia a media carga). Mean ~1, >1 cargado."
function mass_factor(t::TruckType, payload_kg::Float64)
    ref = t.curb_kg + 0.5 * t.payload_max_kg
    return (t.curb_kg + payload_kg) / ref
end

end # module
