#=
test_J1939.jl — Pruebas del decodificador J1939.

Correr:  julia test_J1939.jl     (o)   julia -e 'include("test_J1939.jl")'

Los vectores son los mismos que se cross-validaron en Python durante el desarrollo
(extracción de PGN PDU1/PDU2, señal little-endian con escala/offset, no-disponible/error,
y unpack de DM1 v4). Si estos pasan, el núcleo de decodificación es correcto; el diccionario
de señales es responsabilidad del DBC/J1939-71 (ver J1939.jl).
=#

isdefined(Main, :MaintenanceSim) || include(joinpath(@__DIR__, "..", "src", "MaintenanceSim.jl"))
using .MaintenanceSim
using .MaintenanceSim.J1939
using Test

@testset "J1939 core decode" begin

    @testset "PGN / Source Address" begin
        # PDU2 broadcast: EEC1 = 61444 (0xF004), PF=0xF0≥240, PS=0x04, SA=0x00
        idA = UInt32(3) << 26 | UInt32(0xF0) << 16 | UInt32(0x04) << 8 | UInt32(0x00)
        @test pgn_and_sa(idA) == (61444, 0x00)

        # PDU1 destino-específico: Request PGN = 59904 (0xEA00), PF=0xEA(234)<240, PS=destino=0x21
        idB = UInt32(6) << 26 | UInt32(0xEA) << 16 | UInt32(0x21) << 8 | UInt32(0x00)
        @test pgn_and_sa(idB) == (59904, 0x00)
    end

    @testset "Signal decode (scale/offset, NA/error)" begin
        # SPN 190 engine speed, EEC1 bytes 4-5, 0.125 rpm/bit → 0x2000=8192 → 1024 rpm
        d_eec1 = UInt8[0xFF,0xFF,0xFF,0x00,0x20,0xFF,0xFF,0xFF]
        @test decode_signal(d_eec1, SEED_SIGNALS[190]) == 1024.0

        # SPN 110 coolant temp, ET1 byte 1, scale 1 offset -40 → 100 → 60 °C
        d_et1 = UInt8[0x64,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF,0xFF]
        @test decode_signal(d_et1, SEED_SIGNALS[110]) == 60.0

        # No disponible (0xFF) → missing
        @test decode_signal(UInt8[0xFF for _ in 1:8], SEED_SIGNALS[110]) === missing

        # Error de 2 bytes (0xFFFE) → missing  (usando layout de SPN 190: bytes 4-5)
        d_err = UInt8[0,0,0,0xFE,0xFF,0,0,0]
        @test decode_signal(d_err, SEED_SIGNALS[190]) === missing

        # Aftertreatment con pgn=0 (a confirmar) → missing por diseño
        @test decode_signal(UInt8[0 for _ in 1:8], SEED_SIGNALS[3251]) === missing
    end

    @testset "DM1 DTC unpack (v4)" begin
        # lamps=2 bytes; DTC1: SPN110/FMI3/OC1 ; DTC2: SPN3251/FMI16/OC5
        dm1 = UInt8[0x00,0xFF, 0x6E,0x00,0x03,0x01, 0xB3,0x0C,0x10,0x05]
        got = decode_dm1(dm1)
        @test got == [DTC(110,3,1,0), DTC(3251,16,5,0)]
    end

    @testset "decode_frame dispatch" begin
        # Frame EEC1 → señales
        idA = UInt32(3) << 26 | UInt32(0xF0) << 16 | UInt32(0x04) << 8 | UInt32(0x00)
        d_eec1 = UInt8[0xFF,0xFF,0xFF,0x00,0x20,0xFF,0xFF,0xFF]
        r = decode_frame(idA, d_eec1)
        @test r.pgn == 61444
        @test r.signals[190] == 1024.0

        # Frame DM1 (PGN 65226 = 0xFECA → PF=0xFE, PS=0xCA, PDU2) → DTCs
        idDM1 = UInt32(6) << 26 | UInt32(0xFE) << 16 | UInt32(0xCA) << 8 | UInt32(0x00)
        @test pgn_and_sa(idDM1)[1] == 65226
        dm1 = UInt8[0x00,0xFF, 0x6E,0x00,0x03,0x01, 0xB3,0x0C,0x10,0x05]
        r2 = decode_frame(idDM1, dm1)
        @test r2.dtcs == [DTC(110,3,1,0), DTC(3251,16,5,0)]
    end

end
