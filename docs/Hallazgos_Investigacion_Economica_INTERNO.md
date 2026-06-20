> **INTERNO.** Hallazgos de la investigación económica exhaustiva (agenda en `Agenda_Investigacion_Economica_INTERNO.md`).
> Cada cifra marcada [AUTORITATIVO] (federal/peer-reviewed/agencia) o [COMERCIAL]. Las .gov bloquean WebFetch (403)
> ⇒ corroboración por búsqueda que cita el primario. Sesión 2026-06-19.

# Hallazgos — caso económico de mantenimiento (Clase 8)

## Bloque 1 — P(accidente | falla) por componente  ✅ (investigado)

**Relative Risk del LTCCS (associated factor):** frenos **RR 2.7** (~29% de camiones), llantas **RR 2.5** (~6%),
cargo-shift **RR 56.3** (~4%). Muestra: 967 choques ponderados a ~141,000. [AUTORITATIVO — FMCSA LTCCS]
- [ltccs report congress](https://ai.fmcsa.dot.gov/downloadFile.axd?file=LTCCS+reportcongress_11_05.pdf)

**Critical reason del camión: vehículo ~10% / humano ~87% / ambiente ~3%.** Frenos = associated factor #1 (29%).
Camión con problema de frenos: **+170% más probable** de recibir la causa crítica (= RR 2.7). [AUTORITATIVO]

**⚠ Distinción crítica para el doc (honestidad):** el RR es de *associated factor*, NO P(choque|falla).
- **AF puntual** = (RR−1)/RR aplica solo al subgrupo expuesto: frenos 0.63, llantas 0.60, cargo 0.98. **Es cálculo
  DERIVADO nuestro, no cifra FMCSA** — separarlo visualmente del RR publicado.
- **PAF poblacional correcta** = p(RR−1)/(1+p(RR−1)): frenos con p≈0.29 ⇒ **PAF ≈ 0.33** (~33% de choques de camión
  atribuibles a frenos a nivel poblacional). **Ésta es la cifra defendible**; la AF 0.63 sobreestima si se aplica a toda la flota.

**OOS/violaciones como predictor de siniestralidad (clave para el ROI):** [AUTORITATIVO]
- Carrier con alerta en cualquier BASIC: **+79%** tasa de choque futura (FMCSA SMS Effectiveness Test 2014).
- Carrier en **Vehicle Maintenance BASIC**: **5.65 vs 3.43 choques/100 power units = +65%** sobre el promedio nacional.
- ATRI 2012 (*CSA: Analyzing the Relationship of Scores to Crash Risk*): Vehicle Maintenance BASIC correlaciona
  positivamente con riesgo futuro (neg. binomial). Matiz honesto: NO todo BASIC predice (Driver Fitness/Substances no) —
  citar Vehicle Maintenance específicamente. [ATRI = brazo de investigación ATA, peer-cited, publicado por FMCSA]
- Paper peer-reviewed: *Insights into motor carrier crashes: …FMCSA inspection violations*, **Accident Analysis & Prevention**
  ([S0001457521001366](https://www.sciencedirect.com/science/article/abs/pii/S0001457521001366)) — citar (cifra exacta tras paywall).

## Bloque 3 — Daño secundario / cascada de "correr hasta fallar"  ✅ (investigado)

**El "reactivo 3–5× el planeado" SÍ es auditable — pero la fuente primaria es DOE/PNNL, NO camiones:** [AUTORITATIVO]
- US DOE / PNNL/FEMP *O&M Best Practices Guide* R3.0: reactivo **3–5×** planeado; preventivo ahorra **12–18%**,
  predictivo **25–30%** vs reactivo. [omguide PDF](https://www.energy.gov/sites/prod/files/2020/04/f74/omguide_complete_w-eo-disclaimer.pdf), [PNNL-14788](https://www.pnnl.gov/main/publications/external/technical_reports/pnnl-14788.pdf)
- **Caveat obligatorio**: es benchmark cross-industry de equipo (plantas/edificios federales), extrapolado a flota.
  NO hay (encontrado) un 3–5× con fuente primaria específica de Clase 8 — declarar la extrapolación. HUECO.

**Cascadas físicas (secuencia AUTORITATIVA vía TMC RP; montos $ COMERCIALES y mayormente auto ligero):**
- Sello rueda → balero → maza/spindle/ABS → wheel-off: **TMC RP 622B** (autoritativo de industria para la secuencia).
- Balata al metal → raya disco (resurface/reemplazo). Sobrecalentamiento → cabeza deformada → junta/bloque → motor.
- ⚠ Los **dólares** son comerciales/auto ligero; para Clase 8 (rotor, rebuild diésel $20–40k+) faltan cotizaciones OEM/TMC VMRS. HUECO.

## Recomendación de blindaje (de la investigación)
En el documento final: separar **RR (FMCSA, publicado)** de **AF/PAF (derivado nuestro, fórmula citada)**; usar **PAF≈0.33**
como cifra poblacional defendible; etiquetar el **3–5%** como "benchmark DOE/PNNL cross-industry, no específico de camión";
cascada física = TMC RP 622B (autoritativo), dólares = ilustrativos/comerciales.

---

## Bloque 4 — Uptime/disponibilidad como activo (lado ingreso)  ✅ (investigado)
- **"Costo de día parado" $448–760/día** = **SOTI (COMERCIAL)**, no ATRI/FMCSA — rastreado a su origen; usar solo como rango cualitativo.
- **Ancla AUTORITATIVA**: ATRI costo marginal **$90.89/hora (2024)** = **$2.26/milla**; de ahí se DERIVA el costo de oportunidad diario
  (~$1,000/día con ~11 h HOS) con fuente sólida. [ATRI *Operational Costs 2025 Update*](https://truckingresearch.org/about-atri/atri-research/operational-costs-of-trucking/)
- ATRI trackea **"mileage between breakdowns"** como KPI → puente conceptual directo con nuestro c_f/modelo de fallas. [AUTORITATIVO]
- ~8.7 días/año de downtime no planeado; PM reduce ~45% → [COMERCIAL, orden de magnitud, sin estudio primario].

## Bloque 8 — TCO y curva de trade-off  ✅ (investigado)
- **M&R = $0.202/milla (2023) ≈ 8.9% del costo operativo**; $0.198/mi (2024). LTL $0.222/mi. [AUTORITATIVO — ATRI]
  Desglose marginal 2023 ($2.270/mi): driver 0.779, fuel 0.553, pagos 0.360, **M&R 0.202**, seguro 0.099, llantas 0.046, peajes 0.034.
  Lectura clave: M&R ~9% pero **es de las pocas líneas CONTROLABLES por decisión de mantenimiento** (vs combustible/salarios/seguro);
  con llantas, el "taller/parts" controlable ~11%. [ATRI Dan Murray](https://protectiveinsurance.com/docs/librariesprovider3/2024-c-s/dan-murrary_atri.pdf)
- **TCO Clase 8**: NACFE (CapEx + OpEx[combustible + **M&R** + seguro + multas]÷millas); NREL/Argonne con desglose M&R. [AUTORITATIVO]
- **Frontera mantenimiento-vs-falla = teoría de confiabilidad peer-reviewed**: Age Replacement (Barlow-Hunter 1960; Barlow-Proschan 1965):
  C(T)=[c_p·R(T)+c_f·F(T)]/E[ciclo] tiene **mínimo interior T\* único bajo IFR** (deterioro) — es la justificación matemática del
  preventivo/predictivo como inversión óptima. Extensiones: repair-cost-limit, reparación imperfecta, multi-modo. [peer-reviewed]
  (Conecta con nuestro `optimal_interval.jl` / `Estudio_Convergencia_Economica.md`.)
- **3 cifras más defendibles**: M&R ~9% opex ($0.198–0.202/mi); costo marginal $2.26/mi=$90.89/h (base día parado); existencia de T\* bajo IFR.

---

## Bloque 5 — Efectividad PdM sobre COSTO, evidencia NO comercial  ✅ (HUECO #1 CUBIERTO)
**Fuente federal ancla: US DOE / FEMP *O&M Best Practices Guide* R3.0 (PNNL), Capítulo 5 (Predictive Maintenance).**
Reemplaza las cifras de proveedor (−35–62% / 75–85%) por la lista canónica FEMP [AUTORITATIVO — publicado por DOE]:
- **ROI del programa PdM: 10×** · costos de mantenimiento **−25–30%** · descomposturas **−70–75%** · downtime **−35–45%**
  · producción **+20–25%** · **PdM sobre PM: +8–12%** (hasta 30–40% donde domina lo reactivo).
- PDFs: [DOE omguide](https://www.energy.gov/sites/prod/files/2020/04/f74/omguide_complete_w-eo-disclaimer.pdf) · [PNNL-14788](https://www.pnnl.gov/main/publications/external/technical_reports/pnnl-14788.pdf)
- ⚠ Procedencia: el DOE las publica pero las atribuye a una fuente de industria de confiabilidad ⇒ citar **"según el DOE/FEMP O&M BPG Cap. 5"**
  (federal-publicado, no experimento federal). **Pendiente: verificar snippet literal contra el PDF (WebFetch daba 403).**
- Ancla peer-reviewed del ENFOQUE (no de un %): **Theissler et al. 2021, *RESS* 215:107864** ([S0951832021003835](https://www.sciencedirect.com/science/article/pii/S0951832021003835)).
  Triangulación de magnitud (otro sector): CBM eólico −~30% costo de ciclo de vida [peer-reviewed]. Review PdM transporte: *Sustainability* 14(21):14536.

## Bloque 2 — Economía del varado (c_varado)  ✅ (investigado)
Cadena defendible: (1) **valor del tiempo parado** = ATRI **$91.27/hora** (2023) [AUTORITATIVO]; (2) **costo del evento de reparación
en ruta** = **~$522/evento** (TMC/FleetNet, Q2 2020) + **frecuencia** vía MMBRR **~31,638 mi entre descomposturas** [AUTORITATIVO-INDUSTRIA,
[tmc.trucking.org/node/294](https://tmc.trucking.org/node/294)]; (3) **grúa pesada** $4–15/mi + enganche $250–600 [COMERCIAL — eslabón más débil,
sin fuente federal]; (4) **premium emergencia ≈ 2–3×** lo programado [COMERCIAL]; penalización por demora soportada por **dwell 1h38m** (ATRI).
Contexto regulatorio: equipo de emergencia **49 CFR §393.95** (FMCSA).

---

## ESTADO Y PENDIENTE
**8 de 8 bloques investigados** ✅. Bloques 1–5 y 8 arriba; **bloques 6 (CSA→seguro/contratos) y 7 (datos México) en
`docs/Hallazgos_Bloques_6_7_INTERNO.md`**. El hueco de credibilidad #1 (efectividad PdM) quedó cubierto con fuente federal DOE/FEMP.
- **B6 (resumen)**: Vehicle Maintenance BASIC → percentil SMS (underwriting + filtrado de shippers); primas +12.5% (2023) empujadas
  por costo/siniestro, no frecuencia; ahorro vía seguro = mover de cuartil de riesgo + elegibilidad de contrato. [castigos/descuentos = COMERCIAL]
- **B7 (resumen)**: flota MX ~19.3 años (68.8% >10 años, CANACAR/SICT); fallas mecánicas lideradas por neumáticos/frenos (IMT);
  siniestros ~1.4–3% del PIB. **HUECO: México NO publica costo por accidente de carga** ⇒ c_f local = extrapolación.
- **Verificación literal pendiente** (WebFetch daba 403): snippet PDF del FEMP Cap.5; tablas ATRI/TMC 2024.
**Próxima sesión**: verificación literal de los PDFs (o descargarlos a `References/`) + armar el **whitepaper citado final**
de los 8 bloques, separando [AUTORITATIVO] de [COMERCIAL]/derivado (RR vs AF/PAF→usar PAF≈0.33; 3–5% = benchmark DOE cross-industry).
