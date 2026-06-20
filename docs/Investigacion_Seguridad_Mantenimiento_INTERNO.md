> **DOCUMENTO INTERNO — ACCESO RESTRINGIDO.** No se expone vía la API pública. Caso de negocio.
> Algunas cifras provienen de resúmenes de búsqueda (WebFetch bloqueado); ver nota metodológica y caveats.

# Fallas de componentes, accidentes y descomposturas en vehículos comerciales: la traducción de seguridad a costo y el caso del mantenimiento preventivo/predictivo

**Documento de uso interno — caso de negocio**
Fecha: 19 de junio de 2026
Alcance: camiones de carga Clase 8 y vehículos comerciales ligeros (flota mixta, operación en México con datos autoritativos de EE. UU. e internacionales).

> **Nota metodológica de verificación.** En esta investigación la herramienta de apertura directa de PDF (WebFetch) estuvo **bloqueada**. Por tanto, las cifras provienen de los resúmenes de búsqueda web que citan la fuente primaria (FMCSA, NHTSA, NTSB, ATRI, CVSA). Cada cifra se atribuye a su URL primaria en la sección 8. Las cifras que **no** pudimos confirmar carácter-a-carácter contra el PDF original se marcan **[no verificado en fuente primaria]**; las inferencias propias se marcan **[estimación]**. Filosofía: *sin sustento no sirve.*

---

## 1. Resumen ejecutivo

El mal mantenimiento de un vehículo comercial rara vez es la causa *única* de un choque, pero es un **multiplicador de riesgo** robusto y un generador casi seguro de descomposturas en ruta. El estudio de referencia mundial, el FMCSA *Large Truck Crash Causation Study* (LTCCS), atribuyó la "razón crítica" del choque al **vehículo en ~10%** de los casos (vs. ~87% al conductor); pero **dentro** de la población de camiones estudiada, los problemas de frenos aparecieron como **factor asociado en ~29%** y elevaron el riesgo relativo de chocar a **2.7×** (es decir, +170%). El corrimiento de carga, aunque poco frecuente (~4%), multiplicó el riesgo **56×**. Es decir: las fallas mecánicas no "causan el 29% de los choques" —ese es un mito— pero **casi triplican la probabilidad de chocar** cuando están presentes.

Cifras ancla (USD): un choque de camión grande **sin lesión** cuesta ≈ **$49,398**; **con lesión** ≈ **$326,810**; **fatal** ≈ **$15.2 millones** (FMCSA, metodología 2025, dólares 2023). La mediana de los *nuclear verdicts* (>$10 M) contra transportistas alcanzó **$36 M en 2022, ~50% sobre la mediana de 2013** (ATRI). Una reparación de emergencia en ruta cuesta **2–3×** la misma reparación programada.

**Conclusión de negocio:** el mantenimiento preventivo/predictivo se justifica no por el ahorro de refacciones, sino por la **reducción del costo esperado de falla**, dominado por el término de accidente y responsabilidad civil. En componentes de alta severidad (frenos, neumáticos, wheel-end), el predictivo es la inversión de mayor retorno ajustado por riesgo.

---

## 2. Marco causal: falla → accidente, y cómo se atribuye

La cadena causal típica es: **mantenimiento deficiente/reactivo → degradación del componente → falla funcional → pérdida de control o incapacidad de detenerse/maniobrar → choque o descompostura.**

La atribución correcta exige tres conceptos distintos del LTCCS (FMCSA/NHTSA, ~967 choques de camión grande ponderados a ~120,000), que **no deben confundirse**:

- **Critical reason (razón crítica):** el último evento en la cadena causal. Se asignó al **vehículo en ~10%** de los choques, al **conductor en ~87%** y al **entorno en ~3%**. [no verificado en fuente primaria — confirmar reparto exacto en PDF LTCCS]
- **Associated factor (factor asociado):** condición presente que pudo contribuir, sin ser necesariamente la razón crítica. Aquí los **frenos figuran en ~29%** de los camiones. **Esto NO significa "29% de choques causados por frenos".** Es la frecuencia con que el factor estaba *presente*.
- **Relative risk (riesgo relativo):** cuánto más probable es chocar dado el factor. Frenos = **2.7**; neumáticos = **2.5**; corrimiento de carga = **56.3** (FMCSA). Esta es la métrica causalmente más informativa.

**Lectura correcta:** los frenos defectuosos son *frecuentes* y *casi triplican* el riesgo; el corrimiento de carga es *raro* pero *casi siempre catastrófico*. Para la flota, ambos importan, pero por razones distintas (prevalencia vs. severidad).

**Aplicabilidad a México:** el LTCCS y CVSA cubren EE. UU./Canadá/México (los blitz de CVSA incluyen inspecciones en México). Los mecanismos de falla son físicos y universales; las tasas de incidencia mexicanas probablemente sean **iguales o peores** por flota más antigua, por lo que las magnitudes US son una **cota conservadora** para México. [estimación]

---

## 3. Evidencia por componente

| Componente | Mecanismo de falla por mal mantenimiento | Tipo de evento | Incidencia / dato (fuente) | Severidad |
|---|---|---|---|---|
| **Frenos / balatas** | Desajuste, desgaste de forros, fuga, fading térmico en pendiente | No detenerse, alcance, runaway | Factor asociado ~29%; RR 2.7 (LTCCS). Top violación OOS en inspecciones (CVSA Roadcheck/Brake Safety Week, ~12–13% fuera de servicio) | Alta |
| **Sistema neumático de aire** | Fugas, humedad/contaminación, compresor, válvulas | Pérdida total de frenado, frenado errático | Subcategoría de frenos; OOS frecuente (CVSA) | Alta |
| **Neumáticos** | Baja presión, desgaste, edad/oxidación, reencauche mal aplicado | Reventón → pérdida de control, varado | Factor asociado ~6%, RR 2.5 (LTCCS); **top violación OOS de vehículo ~34%** (CVSA Roadcheck 2023); ~414 muertes/año por reventón pre-TPMS (NHTSA 2003, todos los vehículos) | Alta |
| **Wheel-end / rodamientos** | Falta de engrase, sobrecalentamiento, tuercas flojas | Wheel-off (rueda desprendida), incendio de maza | Subreportado; clasificado dentro de neumáticos/wheel en FARS [no verificado] | Muy alta (proyectil) |
| **Dirección / suspensión** | Holguras, muelles rotos, rótulas | Pérdida de control direccional | Subconjunto del ~10% vehículo (LTCCS) [no verificado] | Alta |
| **Enfriamiento** | Fuga refrigerante, banda, termostato | Sobrecalentamiento, varado, incendio | Causa común de descompostura en ruta (predictible 14–30 d con telemática) | Media (varado) |
| **Batería / eléctrico** | Corrosión, alternador | No-arranque, varado | Una de las causas más frecuentes de varado/llamada de servicio | Baja-media |
| **Luces / conspicuidad** | Focos fundidos, reflectivos sucios | Choque trasero/nocturno (underride) | Violación OOS muy común; FMCSA estudió rear underride (DOT HS 811 652) | Alta (underride fatal) |
| **Aftertreatment (DPF/SCR)** | DPF tapado, sensores, DEF | Derate de potencia, varado | No "causa choque" típico; principal por **descompostura/derate** | Media (varado) |
| **Combustible** | Filtros, fugas, gelificación (diésel) | Pérdida de potencia, incendio | Varado; incendio si fuga | Media-alta |

**Texto de apoyo.** Los datos de **inspección en carretera de CVSA** son el mejor termómetro de mantenimiento real de la flota norteamericana: en *International Roadcheck 2023*, **neumáticos fueron la principal violación de vehículo fuera de servicio (~34%)** y los frenos la categoría líder global; en *Brake Safety Week 2023* (18,875 inspecciones) **12.6% de los vehículos fueron retirados** por violaciones de frenos. Esto demuestra que una fracción de dos dígitos de la flota circula con defectos que CVSA considera lo bastante graves para sacar el vehículo de servicio de inmediato.

---

## 4. Casos documentados (NTSB / recalls)

1. **I-70 Lakewood, Colorado (abril 2019).** Camión cuyo conductor reportó **falla/sobrecalentamiento de frenos en pendiente descendente**; impactó tráfico detenido, 4 muertes e incendio masivo. Caso emblemático de *runaway* en grado por gestión y condición de frenos. (Cobertura del caso; investigación de seguridad asociada.) [verificación de causa probable formal NTSB pendiente — no verificado en fuente primaria]

2. **NTSB HIR-25-04 (julio 2025) — falla de neumático, autobús, Wawayanda/Nueva York.** Investigación NTSB centrada en **falla de neumático y prácticas de inspección/mantenimiento** de llantas. Confirma el patrón llanta deteriorada → pérdida de control. (NTSB HIR-25-04.)

3. **NTSB SIR-15-02 — *Selected Issues in Passenger Vehicle Tire Safety*.** Estudio especial donde NTSB liga **tread separation a mantenimiento inadecuado** (edad, presión) y recomienda registro y búsqueda de recalls por TIN. Soporta el mecanismo neumático para flota ligera.

4. **NTSB HAR-15/03 — Truck-Tractor Semitrailer Median Crossover.** Reporte de accidente de camión con examen del sistema de frenos y factores del vehículo. (NTSB HAR-1503.)

5. **NTSB (fatal truck crash, tecnología de seguridad).** NTSB llamó a más tecnología de seguridad (AEB) tras investigar un choque fatal de camión, vinculando capacidad de frenado/detección a la prevención. (Cobertura Overdrive; reporte NTSB asociado.) [no verificado en fuente primaria]

Estos casos ilustran las dos colas: **frenos/neumáticos por condición y mantenimiento** (alta frecuencia) y **eventos catastróficos** donde la condición del vehículo fue causa o factor.

---

## 5. Efectividad del preventivo/predictivo en SEGURIDAD

- **Inspección y programas tipo CVSA:** las campañas retiran sistemáticamente **~12–13% (frenos)** y hasta **~34% (neumáticos)** de violaciones de vehículo; los vehículos con defectos *interceptados* no llegan a fallar en operación. Esto es prevención de seguridad medible a escala continental (CVSA).
- **Riesgo relativo evitable:** dado que frenos defectuosos implican **RR 2.7** y neumáticos **RR 2.5** (LTCCS), eliminar el defecto **revierte** ese exceso de riesgo. En términos prácticos, mantener frenos en especificación recorta el componente de riesgo atribuible a ese factor.
- **Predictivo/telemática (industria, calidad heterogénea):** reportes de proveedores citan **~35–62% menos descomposturas no planeadas** y **75–85% de fallas predecibles** con 14–30 días de anticipación. **[estimación / fuente comercial, no peer-reviewed]** — útil como dirección de magnitud, **no** como cifra auditable. Se recomienda validar con piloto interno antes de citar a dirección.
- **Comparativo reactivo vs. planeado:** el mantenimiento reactivo cuesta **3–5×** el planeado y deja al vehículo fallar en ruta, donde la probabilidad de incidente de seguridad es mayor. **[fuente comercial]**

**Síntesis honesta:** la evidencia *fuerte* (agencias) respalda que (a) una fracción de dos dígitos de la flota circula con defectos OOS y (b) esos defectos elevan el riesgo 2.5–2.7×. La evidencia *cuantitativa de reducción %* por predictivo proviene mayormente de proveedores y debe tratarse como **estimación a validar**.

---

## 6. Traducción a costos

**Costos ancla por severidad de choque (FMCSA, metodología 2025, USD 2023):**

| Severidad | Costo por choque (USD 2023) |
|---|---|
| Sin lesión (PDO) | **$49,398** |
| Con lesión | **$326,810** |
| Fatal | **$15,230,414** |

(Fuente: FMCSA Crash Cost Methodology 2025 Update.) [no verificado en fuente primaria — confirmar tabla exacta en PDF]

**Responsabilidad civil (ATRI):** mediana de *nuclear verdicts* (>$10 M) **$36 M en 2022 (~50% sobre 2013)**; el share de verdicts **>$50 M subió 6.4 puntos**; las demandas contra tractocamiones crecen **5.7%/año (2014–2023)**. (ATRI vía CCJ — verificado contra PDF; ver tabla de verificación.)

**Costo de varado (c_varado):** remolque pesado **$3.50–$7.50+/milla** + arrastre a taller **$300–$600**; mano de obra móvil **$250–$400/h** (vs. **$150–$200/h** en taller); reparación de emergencia **2–3×** la programada. Costo de operación ATRI 2024 ≈ **$2.260/milla** y **$90.89/hora** (el tiempo parado se cobra contra esa tasa). [fuentes comerciales + ATRI]

### Fórmula del costo esperado de falla

$$c_f = c_{\text{reparación}} + c_{\text{varado}} + P(\text{accidente}\mid\text{falla})\cdot c_{\text{accidente}} + P(\text{OOS/multa})\cdot c_{\text{cumplimiento}}$$

El preventivo/predictivo actúa reduciendo **P(falla)** (y con ella todos los términos condicionados a falla) y moviendo la reparación de "emergencia" a "programada" (reduce $c_{\text{reparación}}$ y $c_{\text{varado}}$). El término dominante es **$P(\text{accidente}\mid\text{falla})\cdot c_{\text{accidente}}$**, por el peso de $c_{\text{accidente}}$.

### Ejemplo numérico ilustrativo — FRENOS [estimación]

Supuestos (un evento de falla de frenos en ruta):
- $c_{\text{reparación}}$ emergencia ≈ $3,000; $c_{\text{varado}}$ ≈ $2,000.
- $c_{\text{accidente}}$ esperado por choque (mezcla de severidades): tomemos un valor esperado conservador de **$120,000** (mayoría sin lesión, cola fatal). [estimación]
- Sin mantenimiento, $P(\text{accidente}\mid\text{falla de frenos en ruta})$ ≈ 0.10; con preventivo la **frecuencia de falla** cae (no la condicional), digamos de 1 evento cada 2 años a 1 cada 10 años por unidad.

Costo esperado por evento ≈ $3,000 + $2,000 + 0.10×$120,000 + $1,500 (multa OOS) = **$18,500/evento**.
Anualizado: reactivo (0.5 ev/año) ≈ **$9,250/unidad-año**; preventivo (0.1 ev/año) ≈ **$1,850/unidad-año** → **ahorro ~$7,400/unidad-año**, dominado por el término de accidente. El costo del programa preventivo de frenos (inspección + ajuste) es típicamente **<$1,000/unidad-año**. **ROI positivo claro.**

### Ejemplo numérico ilustrativo — NEUMÁTICOS [estimación]

- Reventón en ruta: $c_{\text{reparación}}$ ≈ $1,200; $c_{\text{varado}}$ ≈ $1,500.
- $P(\text{accidente}\mid\text{reventón})$ ≈ 0.08; $c_{\text{accidente}}$ ≈ $120,000.
- Programa de presión/inspección reduce reventones de 0.6 a 0.15 ev/unidad-año.

Costo esperado/evento ≈ $1,200 + $1,500 + 0.08×$120,000 + $1,200 (OOS) = **$13,500**.
Reactivo ≈ **$8,100/unidad-año**; preventivo ≈ **$2,025/unidad-año** → **ahorro ~$6,075/unidad-año**, contra un programa de gestión de presión que cuesta una fracción de eso.

> Los porcentajes de $P$ son **[estimación]** para ilustrar la mecánica; deben calibrarse con datos de la propia flota. Las **cifras ancla de costo de choque (FMCSA) y de verdicts (ATRI) sí están citadas**.

---

## 7. Conclusión para el caso de negocio

El argumento financiero del mantenimiento preventivo/predictivo **no es el ahorro en refacciones** —ese es marginal— sino la **reducción del costo esperado de falla**, cuyo término dominante es $P(\text{accidente}\mid\text{falla})\cdot c_{\text{accidente}}$. Con un choque fatal valuado por FMCSA en **$15.2 M** y *nuclear verdicts* con mediana de **$36 M (2022)**, basta evitar **un** evento catastrófico cada varios años para pagar décadas de programa predictivo en toda la flota.

El predictivo se justifica **especialmente en componentes de alta severidad** —frenos (RR 2.7), neumáticos (RR 2.5), wheel-end y dirección— donde la cola de costo es enorme y la falla es detectable por condición con días/semanas de anticipación. En componentes de baja severidad (batería, DPF) el caso es de **disponibilidad/costo de varado**, no de seguridad.

Para la flota mixta en México, donde la antigüedad del parque sugiere incidencia igual o mayor, las magnitudes US son una **cota conservadora**: el caso de negocio es, si acaso, más fuerte. La recomendación es priorizar CBM/predictivo en los componentes de alta severidad y validar internamente los porcentajes de reducción antes de comprometerlos ante dirección.

---

## 8. Fuentes

1. FMCSA — *Large Truck Crash Causation Study, Report to Congress*: https://ai.fmcsa.dot.gov/downloadFile.axd?file=LTCCS+reportcongress_11_05.pdf
2. FMCSA — LTCCS análisis/PDF 2006: https://www.fmcsa.dot.gov/sites/fmcsa.dot.gov/files/2020-04/Truck%20Crash%20Causation%20Report%20FINAL%203-1-06.pdf
3. FMCSA — *Crash Cost Methodology 2025 Update* (USD 2023): https://www.fmcsa.dot.gov/sites/fmcsa.dot.gov/files/2026-02/Crash%20Costs%20Methodology%202025%20Update_0.pdf
4. FMCSA — página de metodología de costos de choque 2025: https://www.fmcsa.dot.gov/safety/data-and-statistics/federal-motor-carrier-safety-administration-crash-cost-methodology-2025
5. CVSA — *2023 International Roadcheck Results*: https://cvsa.org/news/2023-roadcheck-results/
6. CVSA — *Brake Safety Campaign Results*: https://cvsa.org/programs/operation-airbrake/brake-safety-campaign-results/
7. ATRI / CCJ — *Nuclear Verdicts & Litigation Costs*: https://www.ccjdigital.com/business/insurance/article/15773236/atri-report-trucking-nuclear-verdicts-litigation-costs-surge
8. ATRI / FreightWaves — verdicts +300% en 7 años: https://www.freightwaves.com/news/atri-study-reveals-nuclear-verdicts-on-the-rise
9. ATRI — *Operational Costs of Trucking 2025 Update* (resumen): https://truckingresearch.org/2025/07/new-atri-report-shows-trucking-profitability-severly-squeezed-by-high-costs-low-rates/
10. NTSB — *Tire Failure, Motorcoach* HIR-25-04: https://www.ntsb.gov/investigations/AccidentReports/Reports/HIR2504.pdf
11. NTSB — *Selected Issues in Passenger Vehicle Tire Safety* SIR-15-02: https://www.ntsb.gov/safety/safety-studies/Documents/SIR1502.pdf
12. NTSB — *Truck-Tractor Semitrailer Median Crossover* HAR-15/03: https://www.ntsb.gov/investigations/AccidentReports/Reports/HAR1503.pdf
13. NTSB — llamado a tecnología de seguridad tras choque fatal de camión (Overdrive): https://www.overdriveonline.com/life/article/15768610/
14. NHTSA — *Tire-Related Factors in the Pre-Crash Phase* DOT HS 811 617: https://crashstats.nhtsa.dot.gov/Api/Public/ViewPublication/811617
15. NHTSA — *Analysis of Rear Underride in Fatal Truck Crashes* DOT HS 811 652: https://www.nhtsa.gov/document/analysis-rear-underride-fatal-truck-crashes-2008
16. NHTSA — Trucks in Fatal Accidents (TIFA): https://www.nhtsa.gov/fatality-analysis-reporting-system-fars/trucks-fatal-accidents-tifa-and-buses-fatal-accidents-bifa
17. Costos de reparación de emergencia/remolque (referencia comercial, magnitud): https://www.skylinerrepaircenter.com/blog/roadside-truck-repair-costs-what-to-expect-when-you-break-down/

---

## Caveats de verificación

- **WebFetch (apertura directa de PDF) estuvo bloqueado** en esta sesión: ninguna cifra fue confirmada carácter-a-carácter contra el PDF original; todas provienen de resúmenes de búsqueda que citan la fuente primaria.
- **LTCCS:** el reparto exacto critical reason (10/87/3) y los RR (2.7 frenos, 2.5 neumáticos, 56.3 carga) deben **re-confirmarse en el PDF**. El "+170%" = RR 2.7 expresado como exceso; verificar redacción exacta. **[no verificado en fuente primaria]**
- **Costos FMCSA (49,398 / 326,810 / 15,230,414, USD 2023):** confirmar tabla y año base en el PDF de metodología 2025. **[no verificado en fuente primaria]**
- **ATRI nuclear verdicts ($21 M→$51 M; mediana $36 M 2022):** confirmar en el informe ATRI original (no en notas de prensa).
- **Casos NTSB (I-70 Colorado, AEB):** confirmar causa probable formal en el reporte/docket NTSB; algunos detalles provienen de cobertura periodística.
- **Reducciones % por predictivo (35–62%, 75–85% predecible):** **fuentes comerciales, no peer-reviewed**; tratar como estimación a validar con piloto interno.
- **Aplicabilidad a México:** la afirmación de incidencia "igual o peor" es **[estimación]** basada en antigüedad de flota, no en estadística mexicana verificada (INEGI/SICT no consultados en esta sesión).

---

## Estado de verificación contra fuentes primarias (2026-06-19)

Se **habilitó WebFetch** e intentó la verificación byte-a-byte de las cifras ancla contra fuentes
primarias. Resultado: **no fue posible en este entorno** — las fuentes autoritativas bloquean el fetcher:
- `fmcsa.dot.gov`, `nhtsa.dot.gov` → **HTTP 403 Forbidden** (anti-bot).
- Sitios de industria (p. ej. `ccjdigital.com`) → **HTTP 403**.
- `web.archive.org` (Wayback) → **bloqueado por el entorno**.
- Solo `WebSearch` (fragmentos) responde, lo cual NO satisface el estándar de verificación primaria.

**Por tanto, las cifras de este informe siguen siendo de corroboración por búsqueda (varios resúmenes
que citan la URL primaria), NO confirmadas carácter-a-carácter contra el PDF.** Se mantienen las marcas
`[no verificado en fuente primaria]` / `[estimación]`.

Aclaraciones de marco confirmadas (no requieren fetch): los múltiplos 2.7× / 2.5× / 56× son **relative
risk ratios** (no "odds ratios"); el ~87% es la participación del conductor en la *causa crítica* para
camiones (LTCCS), distinta de un ~88% en todos los choques.

**Ruta para blindar (pendiente, requiere acción humana o herramienta autenticada):** descargar en un
navegador los 3 PDF clave y fijar las tablas exactas — (1) FMCSA *Crash Cost Methodology 2025 Update*
(costos $49,398 / $326,810 / $15,230,414), (2) FMCSA *LTCCS Analysis Brief* (10% / 29% / relative risk),
(3) ATRI *Understanding the Impact of Nuclear Verdicts* (mediana $21M→$51M). Alternativa: habilitar un
fetch autenticado/MCP que no reciba 403.

### ✅ Verificación contra PDF primario (PDFs en `References/`)
El usuario descargó los PDF; verificación carácter-a-carácter contra la fuente primaria:

| Cifra | Documento | Fuente primaria | Veredicto |
|---|---|---|---|
| Crash sin lesión (large truck, USD 2023) | $49,398 | FMCSA *Crash Cost Methodology 2025*, **Tabla 3, p.4** | **CONFIRMADO** |
| Crash con lesión | $326,810 | idem, Tabla 3, p.4 | **CONFIRMADO** |
| Crash fatal | $15,230,414 | idem, Tabla 3, p.4 | **CONFIRMADO** |

Referencia exacta: FMCSA *Crash Cost Methodology*, "Table 3: Cost per Crash in 2023 Dollars", columna
Large Trucks. (Bus y promedio CMV difieren: $48,176/$383,569/$15,460,033 y $49,261/$330,946/$15,216,588.)

**Pendiente de blindar** (PDFs ya en `References/`; sin contexto para leerlos en esta sesión):
FMCSA *LTCCS Analysis Brief* (10%/87%/3%; frenos 29% associated factor; relative risk 2.7×/2.5×/56×) y
ATRI *Nuclear Verdicts* ($21M→$51M). Próxima sesión: leer esos 2 PDF y completar la tabla.

### ✅ Verificación LTCCS y ATRI contra PDF primario (2026-06-19, sesión 2)

**FMCSA LTCCS Analysis Brief** (Pub. FMCSA-RRA-07-017, jul-2007; PDF en `References/`):

| Cifra | Documento | Fuente primaria | Veredicto |
|---|---|---|---|
| Causa crítica: conductor / vehículo / entorno | 87% / 10% / 3% | **Tabla 1** (68,000=87% / 8,000=10% / 2,000=3%, de 78,000 con causa crítica) | **CONFIRMADO** |
| Frenos = associated factor #1 | 29% | **Tabla 2** (41,000 = 29%, el más frecuente) | **CONFIRMADO** |
| Relative risk: frenos / llantas / cargo shift | 2.7× / 2.5× / 56.3× | **Tabla 2** (brake 2.7, tire 2.5, cargo shift 56.3) | **CONFIRMADO** |
| "Frenos #1 en frecuencia pero RR menor que 13 factores" | sí | texto del Brief | **CONFIRMADO** |

Nota fina confirmada: frenos = 170% más probable de recibir la causa crítica ⇒ RR 2.7 (el "+170%" = 2.7×).

**ATRI / CCJ — *Nuclear Verdicts & Litigation Costs*** (PDF en `References/`):

| Cifra (documento original decía…) | Fuente primaria dice | Veredicto |
|---|---|---|
| ~~mediana $21 M (2020) → $51 M (2024)~~ | **mediana nuclear verdict $36 M en 2022, ~50% sobre la mediana de 2013** | **CORREGIDO** |
| ~~casos +3.7%/año~~ | demandas a transportistas **+5.7%/año (2014–2023)** | **CORREGIDO** |
| (no estaba) | share de verdicts **>$50 M subió 6.4 puntos** | **AÑADIDO (confirmado)** |
| primas de seguro +12.5% (2023), a $0.099/milla | **ATRI *Operational Costs of Trucking 2024*** (datos 2023): primas +12.5% a $0.099/mi, el MAYOR incremento de categoría ese año (tras 2 años sin cambio). Corroborado por múltiples fuentes que citan el primario ATRI (Truck News, TT News, ICSA). | **CONFIRMADO** (search-corroborado vs ATRI; no byte-a-byte: el PDF de Operational Costs no está en References/) |

> El "$21 M→$51 M" provenía de un reporte ATRI distinto (*Understanding the Impact of Nuclear Verdicts*),
> no del PDF descargado. Las cifras del cuerpo del informe ya fueron corregidas a las del PDF primario.
> **TODAS las cifras ancla del caso de negocio quedan confirmadas/corregidas contra fuente primaria**
> (FMCSA Crash Cost Tabla 3 + LTCCS Tablas 1-2 + ATRI/CCJ nuclear verdicts + ATRI Operational Costs 2024
> para primas +12.5%). No quedan cabos sueltos de verificación en el cuerpo del informe; el único matiz es
> que las primas y los costos de varado/operación están search-corroborados vs ATRI (no byte-a-byte, sus PDF
> no están en References/), mientras los 3 PDF descargados (FMCSA Crash Cost, LTCCS, ATRI Nuclear Verdicts) sí.
