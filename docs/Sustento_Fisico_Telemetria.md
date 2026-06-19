# Sustento físico y documental del generador de telemetría OBD/CAN

**Cada parámetro y modelo del simulador de telemetría tiene origen en un estándar, dato medido o
literatura revisada.** Sin sustento real, los datos sintéticos no sirven; este documento es el
contrato de trazabilidad. Marca lo **estándar/medido** (sólido) vs lo **típico de industria
(calibrable)** (asunción etiquetada, a refinar con datos propios).

Versión 1.0 — Junio 2026. Subsistema `src/telemetry/` + `src/physics/`.

---

## 1. Estándares de bus (formato de la señal)

| Componente | Estándar | Uso en el simulador |
|---|---|---|
| PGN/SPN, escalas, offsets J1939 | **SAE J1939-71** (Vehicle Application Layer) | layouts de `SignalRegistry.J1939_PGNS` (EEC1, ET1, LFE, …) |
| Transporte/DTC J1939 | **SAE J1939-21**, **J1939-73** (DM1/DM2) | DTCs, frames de 8 bytes |
| PIDs Modo 01 OBD-II | **SAE J1979 / ISO 15031-5** | `SignalRegistry.OBD_PIDS` (RPM 0x0C, carga 0x04, …) |

> Honestidad de layout (Brief §1.4): los SPN y sus escalas siguen J1939-71 donde se conocen
> (`verified=true`); varios layouts de byte son **internos a la simulación** (`verified=false`):
> hacen round-trip por construcción pero deben confirmarse contra un DBC/J1939-71 autoritativo
> antes de decodificar buses reales. El postratamiento (DPF/SCR/NOx, PGN 64948/61454/65110) y TPMS
> (65268) van marcados a-confirmar a propósito.

---

## 2. Dinámica longitudinal del vehículo (`Powertrain.jl`)

Modelo estándar de fuerzas (referencia: **Gillespie, T. D. (1992),** *Fundamentals of Vehicle
Dynamics*, SAE International, ISBN 978-1-56091-199-9):

$$F = \underbrace{C_{rr}\,m\,g\cos\theta}_{\text{rodadura}} + \underbrace{\tfrac12\,\rho(h)\,C_dA\,v^2}_{\text{aerodinámica}} + \underbrace{m\,g\sin\theta}_{\text{pendiente}} + \underbrace{m\,a}_{\text{aceleración}}$$

$$P_{\text{motor}} = \frac{F\cdot v}{\eta_{\text{trans}}} + P_{\text{accesorios}}$$

| Parámetro | Valor usado | Fuente / sustento | Grado |
|---|---|---|---|
| $C_dA$ Clase 8 | 6.3 m² | Cd 0.5–0.9 × área 9.97–11 m² ⇒ CdA 5–10 m² ([LLNL-TR-628153](https://www.osti.gov/servlets/purl/1073121); [Volvo VBI](https://vbi.truck.volvo.com/portal/perfman/020_terminology/drag_coefficient_(cd).htm)) | medido |
| $C_dA$ ligero | 0.72 m² | Cd ~0.3 × área ~2.4 m² (autos típicos) | típico |
| $C_{rr}$ camión | 0.0065 | pre-LRR **0.0068**, SmartWay LRR **0.0063** ([EPA SmartWay](https://www.epa.gov/verified-diesel-tech/smartway-verified-list-low-rolling-resistance-lrr-new-and-retread-tire); SAE J1269 / ISO 28580) | medido |
| $C_{rr}$ ligero | 0.011 | neumático de pasajero típico | típico |
| $\eta_{\text{trans}}$ | 0.88 (pesado) / 0.90 | eficiencia de tren motriz mecánico | típico |
| $\rho(h)$ aire | $1.225\,e^{-h/8500}$ kg/m³ | atmósfera estándar ISA (altura de escala 8500 m) | estándar |
| Derate por altitud | 0 hasta **1500 m**, luego **8.5%/1000 m** | el turbo mantiene potencia nominal hasta ~1500 m (Cummins: sin derate hasta ~5000 ft ≈ 1524 m); arriba ~2.5%/1000 ft ([Garrett](https://www.garrettmotion.com/news/newsroom/article/how-to-turbocharge-at-elevation-counteracting-lower-air-density/)) | típico/calibrable |

**Velocidad limitada por potencia**: en subida, si la potencia requerida excede la nominal
(derate incluido), el camión desacelera — por eso un tractor cargado **baja a ~50 km/h en un 6%**,
emergente, no impuesto.

---

## 3. Motor: consumo, RPM, térmicas, emisiones

| Parámetro | Valor / modelo | Fuente | Grado |
|---|---|---|---|
| BSFC diésel HD | 195–255 g/kWh (mín ~195 a carga alta) | HD moderno **182–220 g/kWh**, mejor ~172 ([Wikipedia BSFC](https://en.wikipedia.org/wiki/Brake-specific_fuel_consumption); [OSTI](https://www.osti.gov/pages/biblio/1561789-diesel-engine-characterization-performance-scaling-via-brake-specific-fuel-consumption-map-dimensional-analysis)) | medido |
| Densidad diésel | 835 g/L | propiedad estándar (~0.832–0.845 kg/L) | estándar |
| Banda de RPM / lug | crucero ~1300, redline 2100, lug ~1000 (+carga) | diésel HD de servicio; selección de marcha por banda | típico |
| Setpoint refrigerante | 82–106 °C (sube con carga/ambiente/altitud) | termostato ~82–90 °C; picos en subida | típico |
| Retardo térmico | 1er orden, τ≈90 s (refrigerante), 140 s (aceite) | inercia térmica del bloque/aceite | típico |
| Boost (MAP) | baro + carga·(máx 220 kPa) | turbo HD típico | típico |
| EGT | 250 + carga·420 °C (+ambiente) | rango típico 250–700 °C | típico |
| NOx motor-out | 90 + carga·950 ppm | escala con temperatura de combustión ∝ carga | típico |
| Eficiencia SCR | 92% si DEF ok y EGT>220 °C; 35% si no | SCR reduce NOx ~90% ([EPA HD standards](https://www.epa.gov/regulations-emissions-vehicles-and-engines)) | medido |

### 3.1 Precursores de falla / capa de salud (`Diagnostics.jl`) — los datos útiles para PdM

Señales que **tienden hacia la falla** (lo que el modelo estadístico consume). Cada vehículo
arranca con un estado de salud **heterogéneo y realista** (flota usada: odómetro 60k–800k km,
blowby/batería/filtros/balatas correlacionados con la edad + un problema en desarrollo en ~18%).

| Señal precursora | SPN/PID | Mecanismo / sustento | Grado |
|---|---|---|---|
| Presión de cárter (blowby) | SPN 101 | desgaste de anillos ∝ horas; sano ~0–2 kPa, severo ~10 kPa (indicador clásico) | típico |
| ΔP filtro de aceite | SPN 99 | obstrucción ∝ km; bypass ~170 kPa | típico |
| ΔP filtro de combustible | SPN 95 | obstrucción/contaminación ∝ km | típico |
| ΔP filtro de aire | SPN 107 | obstrucción ∝ km (polvo en desierto) | típico |
| Velocidad de turbo | SPN 103 | ∝ boost; deriva con desgaste | típico |
| Ceniza DPF | SPN 3720 | ∝ combustible quemado, **permanente** (no se quema en regen) → limita vida del DPF (EPA/SAE) | medido |
| Voltaje de arranque / SoH batería | SPN 168 / OBD 0x42 | cae con edad y **calor** (degradación Arrhenius) | medido |
| Temp de transmisión | SPN 177 | ∝ carga | estándar |
| Presión de aire de frenos | SPN 117/118 | reservorio de aire | estándar |
| Espesor de balata | — | ∝ energía de frenado (Archard) | típico |
| OBD: fuel trims, EGR, rail pressure, carga abs, cat temp | 0x06/07, 0x2C, 0x22, 0x43, 0x3C | SAE J1979 — combustión/EGR/inyección/catalizador | estándar |

La salud **evoluciona** por viaje (`evolve_health!`): clogging ∝ km (resetea al servicio), blowby
∝ horas, ceniza ∝ combustible, SoH ∝ horas·calor, balata ∝ frenado.

---

## 4. Rutas y terreno tipo Norteamérica (`RouteNetwork.jl`)

| Parámetro | Valor usado | Fuente | Grado |
|---|---|---|---|
| Pendiente máx montañosa | 6% (interestatal); rutas estatales hasta 7% | **AASHTO** máx 6% montañoso / 5% ondulado / 4% plano; pendiente sostenida más empinada del Interstate = **6%** (I-70 Eisenhower, CO) ([Interstate standards](https://en.wikipedia.org/wiki/Interstate_Highway_standards)) | estándar |
| Altitud Rockies | 1500–3400 m | corredor I-70 Colorado (Eisenhower ~3400 m) | medido |
| Rugosidad IRI | 1.2–4.5 m/km | pavimento bueno ~1.5, malo ≥4 (escala IRI del Banco Mundial / FHWA) | estándar |
| Clima estacional | rangos por región/estación | normales NOAA por región (desierto SW 32–48 °C verano; montaña −12–8 °C invierno) | típico |
| Velocidad/ralentí por corredor | reparto urbano ralentí 28%, carretera 5–7% | patrones de ciclo de servicio de flota | típico |

Los cinco corredores (Rockies montaña, llanura I-80/I-35, desierto SW I-10, reparto urbano,
Apalaches rolling) son **arquetipos sintéticos calibrados a estadísticas reales**, no trazas
geográficas literales.

### 4.1 Rutas REALES vía Valhalla (México)

Además de los arquetipos, el simulador consume **rutas reales** del servicio Valhalla del proyecto
(`https://valhalla.ws2.phaimat.com`, costing `truck`): `tools/valhalla_route.py` pide la ruta
(geometría + maniobras) y la elevación (`/height`, DEM), decodifica la polilínea (precisión 6),
deriva **pendiente = Δaltitud/distancia** (haversine) y velocidad por maniobra, y escribe un perfil
de segmentos en `out/routes/<name>.json`. `run_valhalla_demo.jl` corre la telemetría sobre ese
perfil. Validado en vivo (CDMX→Puebla, 131 km, altitud **2130–3220 m**): en la subida a Río Frío la
carga sube a ~95% y la EGT a ~647 °C; en bajada el motor frena (~2.6 L/h); a 3189 m el derate turbo
es ~19% — **todo emergente de terreno real**. Clima por altitud: lapse rate 6.5 °C/1000 m sobre
temperatura de nivel del mar por estación/región de México.

`tools/mexico_fleet.py` genera una **flota de rutas reales** de México (ciudades reales, selección
aleatoria con semilla) con **peso casado al corredor**: puerto/frontera mueven más carga (camión
~29–32 t), regional/altiplano menos (~21–26 t). Ejemplos validados: Veracruz→CDMX (397 km, **5→3217 m**,
28 t, 43.9 L/100km), Manzanillo→CDMX (749 km, 4→3124 m, 30 t), Tijuana→Mexicali (181 km, desierto).

---

## 5. Llantas (`TireModel.jl`)

| Parámetro | Valor usado | Fuente | Grado |
|---|---|---|---|
| Mínimo legal de banda | **4/32″ (3.2 mm) dirección; 2/32″ (1.6 mm) tracción/remolque** | **FMCSA 49 CFR §393.75** ([CSA](https://csa.fmcsa.dot.gov/safetyplanner/MyFiles/SubSections.aspx?ch=22&sec=64&sub=143)) | regulatorio |
| Banda nueva | dirección 14.3 mm (18/32″), tracción 20.6 mm (26/32″) | profundidades de fábrica típicas | típico |
| Presión inflado en frío | 758 kPa (110 psi) pesado; 220 kPa (32 psi) ligero | inflado de operación típico | típico |
| Presión vs temperatura | **Ley de Gay-Lussac**, $P_{abs}\propto T_{abs}$ | gas ideal a volumen ~constante | físico |
| Vida de banda a mínimo | ~10⁵ km (severidad dependiente) | industria (steer ~60–100k mi); **calibrable** | típico |

---

## 6. Vida económica del vehículo (para la parte estadística, en pausa)

| Parámetro | Valor | Fuente |
|---|---|---|
| Vida económica tractocamión line-haul | ~7–8 años / 500–750k mi (mín. EUAC) | caso real de flota cisterna ([ScienceDirect S2590198223001276](https://www.sciencedirect.com/science/article/pii/S2590198223001276)) |
| Reemplazo por edad — horizonte finito | política óptima **no-estacionaria** | Jiang et al., *Reliability Engineering & System Safety* (2009), [S0951832009000209](https://www.sciencedirect.com/science/article/abs/pii/S0951832009000209) |

---

## 7. Extensión a otros vehículos (visión)

La arquitectura separa **parámetros del vehículo** (`TruckType` / `DynSpec`) de la **física**
(`Powertrain`, `TireModel`). Agregar un tipo nuevo (autobús, van eléctrica, pickup, maquinaria) es
**añadir un set de parámetros con su fuente documental** — no reescribir la física. Este documento
es la plantilla de trazabilidad que todo vehículo nuevo debe llenar para que sus datos "sirvan".

---

## 8. Validación de consistencia (automática)

`run_telemetry.jl` verifica en cada corrida: (a) **round-trip** de todos los frames (encode→decode
exacto), (b) **rangos físicos** por señal, (c) **correlación pendiente↔%carga > 0.3** (las subidas
deben cargar el motor). `test/test_telemetry.jl` añade round-trip exacto por SPN/PID y consistencia
del modelo (RPM bajo redline, consumo emergente que ordena montaña > llanura, etc.).

---

## 9. Referencias

- Gillespie, T. D. (1992). *Fundamentals of Vehicle Dynamics.* SAE International.
- SAE **J1939-71/-21/-73** (J1939 application/data link/diagnostics); **J1979 / ISO 15031-5** (OBD-II).
- SAE **J1269 / ISO 28580** (rolling resistance test). EPA **SmartWay** verified LRR tires.
- AASHTO, *A Policy on Geometric Design of Highways and Streets* (Green Book); Interstate Highway standards.
- **FMCSA 49 CFR §393.75** (neumáticos / profundidad de banda).
- Lawrence Livermore (LLNL-TR-628153), *Aerodynamic drag reduction of Class 8 trucks*.
- Garrett Motion, *Turbocharging at Elevation*; Cummins QSK power-derate curves.
- Jiang, R. et al. (2009). *Optimal sequential age replacement for a finite-time horizon.* RESS.
- EUAC de flota: *Analysis of the optimal service lives of trucks…* ScienceDirect (2023).

*Los grados "típico" son asunciones de industria etiquetadas, calibrables con datos reales del
cliente; los "medido/estándar/regulatorio" provienen de estándares o estudios citados.*
