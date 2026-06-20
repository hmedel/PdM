# El caso económico del mantenimiento predictivo de flota

### Por qué el retorno del mantenimiento predictivo no está en las refacciones, sino en el costo esperado de falla

*Whitepaper técnico — PhAIMaT · Tracker / Mantenimiento Predictivo (PdM)*

---

## Resumen ejecutivo

La discusión habitual sobre mantenimiento de flota gira en torno al gasto en refacciones y mano de
obra. Es la línea equivocada. El gasto en mantenimiento y reparación (M&R) ronda el **9 % del costo
operativo por milla** de un camión Clase 8 —es real, pero es de las pocas partidas *controlables* y
no es donde se decide el resultado económico.

El verdadero retorno del mantenimiento **predictivo** (PdM) está en reducir el **costo esperado de
falla**:

$$c_f = c_\text{repar} + c_\text{varado} + P(\text{accidente}\mid\text{falla})\cdot c_\text{accidente} + P(\text{OOS})\cdot c_\text{cumplimiento}$$

El término dominante no es la reparación: es **el producto de la probabilidad de accidente por su
costo**. Un choque fatal de camión grande está valuado por la FMCSA en **15.23 millones de dólares**,
y la mediana de los *nuclear verdicts* (veredictos > 10 M USD) contra transportistas llegó a **36
millones de dólares en 2022**. Frente a esas magnitudes, **basta evitar un evento catastrófico cada
varios años para pagar décadas de programa predictivo en toda la flota.**

Este documento construye el argumento de punta a punta con fuentes verificables, separando en todo
momento lo **autoritativo** (agencias federales, estudios revisados por pares) de lo **comercial**
(estimaciones de la industria aseguradora o de proveedores, útiles como ilustración pero interesadas).

**Las cinco cifras ancla del caso:**

| Cifra | Valor | Fuente |
|---|---|---|
| Costo de un choque **fatal** de camión grande | **$15.23 M** (USD 2023) | FMCSA, *Crash Costs Methodology 2025* — Tabla 3 |
| Mediana de *nuclear verdicts* contra transportistas | **$36 M** (2022), ~50 % sobre 2013 | ATRI |
| Sobre-riesgo de choque de un *carrier* con mal Vehicle Maintenance BASIC | **+65 %** (5.65 vs 3.43 choques / 100 unidades) | FMCSA SMS |
| Efectividad del PdM sobre PM tradicional | **+8–12 %** de ahorro; **−70–75 %** descomposturas; **ROI 10×** | DOE/FEMP O&M Best Practices Guide, Cap. 5 |
| Costo marginal de operación (base del día parado) | **$2.26/milla = $90.89/hora** (2024) | ATRI |

---

## 1. El problema: una fracción de dos dígitos de la flota circula con defectos

No es una hipótesis: cada año, las inspecciones coordinadas de la **CVSA** (Commercial Vehicle Safety
Alliance) sacan de circulación a un porcentaje de dos dígitos de los vehículos inspeccionados por
defectos *out-of-service* (OOS). Los sistemas de **frenos** concentran de forma recurrente la mayor
proporción de violaciones OOS de vehículo, y las **llantas/ruedas** aparecen sistemáticamente entre
las primeras causas. Una porción material de la flota está rodando, en cualquier momento dado, con un
defecto que una inspección habría marcado.

Esto importa porque define el espacio del problema: **el defecto no es un evento raro, es un estado
prevalente**. La pregunta económica no es "¿puede fallar un camión?" sino "¿cuánto cuesta, en
valor esperado, dejar que ese estado prevalente progrese hasta la falla en ruta?". El resto del
documento responde esa pregunta, término por término de $c_f$.

---

## 2. De la falla al accidente, cuantificado

### 2.1 El riesgo relativo publicado (autoritativo)

El **Large Truck Crash Causation Study (LTCCS)** de la FMCSA —el estudio de referencia, sobre una
muestra de 967 choques ponderada a ~141,000 eventos— establece el riesgo relativo (RR) de los
factores asociados al vehículo:

| Factor asociado | Riesgo relativo (RR) | Prevalencia en camiones del estudio |
|---|---|---|
| Frenos | **2.7** | ~29 % |
| Llantas | **2.5** | ~6 % |
| Desplazamiento de carga | **56.3** | ~4 % |

Lectura directa: un camión con un problema de frenos tiene **+170 % más probabilidad** de recibir la
causa crítica del choque (RR 2.7). En la asignación de la *critical reason* del LTCCS, el vehículo
explica ~10 %, el conductor ~87 % y el ambiente ~3 %; **dentro de la porción del vehículo, los frenos
son el factor asociado número uno.**

### 2.2 De RR a fracción atribuible: la cifra defendible es PAF ≈ 0.33

Aquí conviene una distinción honesta que muchos análisis omiten. El RR del LTCCS es de *factor
asociado*, **no** es directamente $P(\text{choque}\mid\text{falla})$. Para traducirlo a una fracción
atribuible hay dos cálculos, y solo uno es defendible a nivel de flota:

- **Fracción atribuible en el expuesto**, $AF = (RR-1)/RR$: para frenos da 0.63. Pero esto aplica
  *solo* al subgrupo que ya tiene la falla; usarla sobre toda la flota **sobreestima** el efecto.
- **Fracción atribuible poblacional (PAF)**, $\text{PAF} = \dfrac{p(RR-1)}{1+p(RR-1)}$: con
  prevalencia $p \approx 0.29$ para frenos, da **PAF ≈ 0.33**. Es decir, **alrededor de un tercio de
  los choques de camión son atribuibles, a nivel poblacional, al factor frenos.** Ésta es la cifra
  que sostiene el caso.

> *Nota metodológica:* el RR (2.7 / 2.5 / 56.3) es dato publicado por la FMCSA; la PAF es un cálculo
> derivado a partir de ese RR con la fórmula epidemiológica estándar. Mantenemos la distinción a la
> vista deliberadamente.

### 2.3 El predictor que cierra el círculo: el historial de mantenimiento predice el choque

La conexión mantenimiento → siniestralidad no es teórica. Los datos del propio sistema de la FMCSA lo
muestran:

- Un *carrier* con alerta en **cualquier** BASIC tiene **+79 %** de tasa de choque futura (FMCSA SMS
  Effectiveness Test, 2014).
- Un *carrier* señalado en el **Vehicle Maintenance BASIC** específicamente promedia **5.65 choques
  por cada 100 unidades de potencia, frente a 3.43 del promedio nacional: +65 %.**

Esto está respaldado por investigación revisada por pares (*Accident Analysis & Prevention*) y por el
análisis de ATRI sobre la relación entre puntajes CSA y riesgo de choque. Matiz honesto: **no todos
los BASIC predicen** (Driver Fitness o Controlled Substances no muestran la misma relación); es el
**Vehicle Maintenance BASIC** el que correlaciona positivamente con el riesgo futuro. Justamente el
que un programa de mantenimiento predictivo mueve.

---

## 3. El costo del accidente

Aquí está el término que domina $c_f$. La FMCSA publica costos de choque de vehículo grande por
severidad (metodología 2025, dólares de 2023):

| Severidad | Costo por choque (USD 2023) |
|---|---|
| Sin lesión (solo daño a la propiedad) | **$49,398** |
| Con lesión | **$326,810** |
| **Fatal** | **$15,230,414** |

A esto se suma el frente de responsabilidad civil, donde la tendencia es la que cambia el cálculo de
riesgo: la mediana de los *nuclear verdicts* (veredictos superiores a 10 M USD) contra transportistas
alcanzó **$36 millones en 2022, ~50 % por encima de la mediana de 2013**; las demandas a
transportistas crecen **+5.7 % anual (2014–2023)** y la participación de veredictos superiores a 50 M
USD subió 6.4 puntos. Estas cifras están confirmadas contra el informe primario de ATRI.

La implicación es aritmética, no retórica. Con la cola de la distribución de costo tan pesada —un solo
evento fatal o un solo veredicto nuclear— **el valor esperado del accidente domina cualquier ahorro
concebible en refacciones.** El mantenimiento predictivo es, antes que una herramienta de eficiencia,
un instrumento de gestión de cola de riesgo.

---

## 4. De la falla a la descompostura: el costo del varado ($c_\text{varado}$)

No toda falla es un accidente; la mayoría son descomposturas en ruta. Su costo se arma con una cadena
de eslabones, del más sólido al más débil:

1. **Valor del tiempo parado (autoritativo):** ATRI cifra el costo del tiempo de inactividad del
   conductor en **$91.27/hora** (2023).
2. **Costo del evento de reparación en ruta (industria):** los datos de benchmarking de TMC/FleetNet
   sitúan el evento típico en **~$522** (Q2 2020), con una frecuencia de **~31,638 millas entre
   descomposturas** (MMBRR, *mean miles between road calls*).
3. **Grúa pesada (comercial — eslabón más débil):** $4–15/milla más enganche de $250–600; sin fuente
   federal, tómese como estimación de industria.
4. **Premium de emergencia:** una reparación no programada en carretera cuesta del orden de **2 a 3×**
   la misma reparación hecha en taller de forma planeada.

A esto se añade el contexto regulatorio (equipo de emergencia obligatorio, 49 CFR §393.95) y la
penalización por demora que soporta el *dwell* promedio documentado por ATRI (1 h 38 min). El punto
económico: **cada descompostura traslada trabajo del cuadrante barato y planeado al cuadrante caro y
en ruta**, y lo hace con una frecuencia medible.

---

## 5. El daño secundario: el costo de "correr hasta que falle"

Dejar progresar un defecto no cuesta linealmente. Cuesta en **cascada**.

La secuencia física es autoritativa y está codificada por la industria. La práctica recomendada **TMC
RP 622B** documenta, por ejemplo, la cadena *sello de rueda → balero → maza/husillo/ABS → wheel-off*:
un sello de $50 que se ignora termina en pérdida de rueda. Análogamente, balata al metal → disco
rayado → reemplazo de rotor; o sobrecalentamiento → cabeza deformada → junta/bloque → motor. La
secuencia es real y conocida.

Sobre la magnitud económica de "reactivo vs planeado", la mejor fuente disponible es federal pero
**no es de camiones**: el *O&M Best Practices Guide* del DOE/PNNL establece que **el mantenimiento
reactivo cuesta de 3 a 5× el planeado**, que el preventivo ahorra 12–18 % y el predictivo 25–30 %
frente al reactivo. Lo declaramos con honestidad: es un **benchmark cross-industry** (plantas y
edificios federales) extrapolado a flota; no encontramos un "3–5×" con fuente primaria específica de
Clase 8. El orden de magnitud, sin embargo, es consistente con el premium de emergencia 2–3× de la
sección anterior.

> Los montos en dólares de las cascadas físicas que circulan en la literatura suelen ser de vehículo
> ligero; para Clase 8 (un rotor, un *rebuild* diésel de $20–40 k) hacen falta cotizaciones OEM/VMRS
> reales. La **secuencia** es autoritativa (TMC); los **dólares puntuales** son ilustrativos.

---

## 6. El uptime es ingreso, no solo costo evitado

Un camino frecuente subestima el caso al contabilizar solo la reparación evitada y olvidar el ingreso
no generado. El ancla autoritativa para valuar la disponibilidad es el **costo marginal de operación
de ATRI: $90.89/hora = $2.26/milla (2024)**. De ahí se deriva, con una jornada de ~11 horas de
servicio (HOS), un costo de oportunidad del orden de **~$1,000 por día parado** con fundamento sólido.

ATRI, además, rastrea como KPI las **"millas entre descomposturas"** (*mileage between breakdowns*),
que es el puente conceptual directo con nuestro modelo de fallas: cada milla adicional entre eventos
es uptime que el predictivo convierte en ingreso. (Las cifras de "costo de día parado de $448–760"
que circulan provienen de proveedores —SOTI— y se usan aquí solo como rango cualitativo, no como
ancla.)

---

## 7. El preventivo/predictivo sí ahorra: evidencia federal, no de proveedor

El contraargumento más común —"esas cifras de ahorro las pone el vendedor"— se responde con una fuente
que no vende nada. El **O&M Best Practices Guide del DOE/FEMP (PNNL), Capítulo 5 (Predictive
Maintenance)** establece, para un programa de mantenimiento predictivo:

- **ROI de 10×**
- Costos de mantenimiento **−25 a −30 %**
- Descomposturas **−70 a −75 %**
- Downtime **−35 a −45 %**
- Producción **+20 a +25 %**
- **Predictivo sobre preventivo tradicional: +8 a +12 %** de mejora adicional (hasta 30–40 % donde
  domina lo reactivo)

Una precisión de procedencia, por rigor: el DOE *publica* estas cifras pero las atribuye a una fuente
de la industria de confiabilidad; por eso las citamos como **"según el DOE/FEMP O&M Best Practices
Guide, Cap. 5"** (federal-publicado), no como resultado de un experimento federal. El **enfoque**
—que el mantenimiento basado en condición reduce costo de ciclo de vida— está además anclado en
literatura revisada por pares (Theissler et al., 2021, *Reliability Engineering & System Safety*).

---

## 8. La matemática del óptimo: por qué existe un punto de inversión correcto

El caso no descansa solo en cifras: descansa en un resultado de la **teoría de confiabilidad**
revisada por pares. El modelo de *Age Replacement* (Barlow–Hunter, 1960; Barlow–Proschan, 1965)
expresa el costo por unidad de tiempo de una política de reemplazo a la edad $T$:

$$C(T) = \frac{c_p\,R(T) + c_f\,F(T)}{\displaystyle\int_0^T R(t)\,dt}$$

donde $c_p$ es el costo de la intervención **planeada**, $c_f$ el costo de la **falla** (el de la
ecuación del resumen), y $R(T)=1-F(T)$ la confiabilidad. El resultado clave: **cuando la tasa de
falla es creciente (IFR, *increasing failure rate* — es decir, hay deterioro real), existe un mínimo
interior $T^\star$ único.** No es "mantener más" ni "mantener menos": es mantener **en el punto
óptimo**, y ese punto existe y es calculable.

Esta es la justificación matemática de que el predictivo es una inversión con óptimo bien definido, no
un acto de fe. El motor de PhAIMaT calcula precisamente este $T^\star$ por componente: en los
componentes con precursor a bordo (frenos, DPF, batería, turbo…) a partir de la **señal de degradación
observada**, y en los que no lo tienen (llanta, wheel-end) a partir de la **estadística de vida** del
componente. En ambos casos el intervalo se desplaza dinámicamente conforme cambia la condición real del
activo —que es lo que distingue al predictivo del preventivo de calendario fijo.

---

## 9. Cumplimiento → seguro y contratos: el costo que no aparece en la factura del taller

Hay un término de $c_f$ que no es ni reparación ni accidente: la **degradación del perfil de
cumplimiento** —el $P(\text{OOS})\cdot c_\text{cumplimiento}$ de la ecuación—, que se paga en primas y
en contratos perdidos. Conviene leerlo en sentido amplio: no es solo la probabilidad de un evento
*out-of-service* puntual, sino el efecto acumulado de las violaciones sobre el **percentil SMS**, que
penaliza durante 24 meses.

- El **Vehicle Maintenance BASIC penaliza durante 24 meses**: cada violación de mantenimiento
  (frenos, luces, llantas, sujeción de carga) afecta el percentil SMS del transportista por dos años;
  el tiempo sin nuevas violaciones lo mejora. *(Autoritativo — FMCSA SMS.)*
- Las **aseguradoras usan el puntaje CSA en el *underwriting***: un percentil limpio (<50 %) da poder
  de negociación; cerca de 80 % encarece o cierra la cobertura. *(El uso del dato es autoritativo; la
  cuantía del castigo —incrementos de prima de 15–30 %— es estimación de la industria aseguradora.)*
- **Shippers y brokers filtran por puntaje**: es práctica común exigir percentiles por debajo de
  60–70 % en todos los BASIC como condición para contratar; los datos SMS son públicos por número
  DOT. *(La publicidad del dato es autoritativa; los umbrales 60–70 % son de la industria.)*

Y la tendencia del mercado de seguros confirma de dónde viene el riesgo: en **2023 las primas
subieron 12.5 %, a 9.9 ¢/milla** (ATRI, *Operational Costs of Trucking 2024* — el mayor incremento de
categoría ese año), con coberturas posteriores citando un récord cercano a 10.2 ¢/milla en 2024. Lo
decisivo: **el alza la empuja el costo por siniestro —los nuclear verdicts— no la frecuencia de
choques, que de hecho ha bajado.** Esto cambia la naturaleza del ahorro: no proviene de "tener menos
choques" (la frecuencia ya es baja), sino de **moverse de cuartil de riesgo** —un Vehicle Maintenance
BASIC limpio, respaldado por telemática verificable— lo que mejora el *underwriting* y mantiene la
elegibilidad para contratos. ATRI documenta, además, correlación estadísticamente significativa entre
seis tecnologías de seguridad y menor pérdida de responsabilidad por milla.

---

## 10. Contexto México: una cota, y por qué la flota envejecida agrava el caso

El argumento anterior se construye sobre datos de Estados Unidos, donde existen las series públicas.
Para México hay que ser explícito sobre qué se puede y qué no se puede afirmar.

**Lo que agrava el problema localmente:** la flota de carga mexicana promedia **~19.3 años de edad**
(cierre 2024 ~19.27 años, según CANACAR sobre el registro SICT), frente a ~6 años en Estados Unidos;
**el 68.8 % —522,517 unidades— tiene más de 10 años.** Una flota estructuralmente más vieja está, por
construcción, más arriba en la curva de tasa de falla creciente (IFR) de la sección 8: el deterioro
es mayor y el $T^\star$ óptimo es más apretado. El caso del predictivo es *más* fuerte, no menos, en
este parque.

**Lo que los datos mexicanos sí permiten afirmar:** en 2023, el INEGI (ATUS) registró **27,594
vehículos pesados de carga involucrados en accidentes** en zonas urbanas y suburbanas (10,907
tractores + 16,687 camiones; −1.8 % interanual). El IMT documenta, en la red carretera federal, que
las fallas por estado físico del vehículo están **lideradas por neumáticos y frenos** —el mismo perfil
que en Estados Unidos.

**El hueco honesto:** el factor humano domina la *frecuencia* (del orden de 88–94 % según fuente y
denominador), por lo que en México **la falla mecánica es minoritaria en frecuencia**; el caso del
predictivo aquí debe argumentarse por **severidad/costo y por el efecto de la flota envejecida**, no
por porcentaje de participación. Y, sobre todo: **México no publica un costo por accidente de camión
de carga** análogo al de la FMCSA. Solo existe la cota macro del IMT —los siniestros viales cuestan
del orden de **1.4 a 3 % del PIB** (estimación IMT ~887,000 millones de pesos al cierre de 2022, del
orden de 2,400 millones de pesos diarios)— que mezcla todos los modos de transporte. Por tanto,
**cualquier $c_f$ por evento para México es una extrapolación de las cifras estadounidenses, que
usamos como cota conservadora.**

---

## 11. El marco TCO: dónde encaja el mantenimiento en el costo por milla

Para ubicar la magnitud, conviene el desglose del costo marginal de operación de un Clase 8 (ATRI,
2023: $2.270/milla):

| Partida | $/milla | Comentario |
|---|---|---|
| Salario del conductor | 0.779 | No controlable por mantenimiento |
| Combustible | 0.553 | No controlable por mantenimiento |
| Pagos del equipo | 0.360 | Capital |
| **Mantenimiento y reparación (M&R)** | **0.202** | **Controlable** |
| Seguro | 0.099 | Controlable *indirectamente* (vía CSA) |
| Llantas | 0.046 | **Controlable** |
| Peajes | 0.034 | No controlable |

El M&R representa **~9 % del costo operativo** ($0.198–0.202/milla según el año; LTL ~$0.222/milla).
La lectura no es "el mantenimiento es barato, ignórenlo". Es la opuesta: **es de las poquísimas líneas
que una decisión de mantenimiento puede mover** —junto con llantas, el bloque "taller/partes"
controlable ronda el 11 %— y, vía el cumplimiento CSA, también influye **indirectamente sobre la prima
de seguro**. El predictivo no busca *minimizar* esta línea; busca **recomponer su contenido**:
trasladar dólares del cuadrante reactivo (caro, en ruta, con cola de accidente) al cuadrante
programado (barato, en taller, planeable). Marcos de TCO de Clase 8 como los de NACFE y NREL/Argonne
desglosan M&R precisamente para permitir este análisis.

---

## 12. Conclusión

El caso económico del mantenimiento predictivo de flota no se gana en la factura de refacciones. Se
gana en la cola de la distribución de costo de falla:

- **El término dominante de $c_f$ es $P(\text{accidente}\mid\text{falla})\cdot c_\text{accidente}$**,
  con un choque fatal valuado en $15.23 M y veredictos con mediana de $36 M.
- **La cadena causal está cuantificada**: el mal mantenimiento eleva la tasa de choque +65 % (Vehicle
  Maintenance BASIC), y alrededor de un tercio de los choques de camión son atribuibles al factor
  frenos a nivel poblacional (PAF ≈ 0.33).
- **El predictivo sí reduce el costo**, con evidencia federal: −70–75 % de descomposturas y +8–12 %
  sobre el preventivo tradicional (DOE/FEMP).
- **Existe un punto de inversión óptimo, calculable** ($T^\star$ bajo IFR), no un acto de fe.
- **El M&R es ~9 % del costo por milla pero es controlable**, y el predictivo recompone su contenido
  de reactivo-caro a programado-barato, además de proteger primas y elegibilidad de contratos.

La conclusión operativa es simple y robusta a la incertidumbre de los parámetros: **basta evitar un
solo evento catastrófico cada varios años —un fatal de $15.23 M o un veredicto de $36 M— para pagar
décadas de programa predictivo en toda la flota.** Y en una flota envejecida como la mexicana
(~19.3 años de edad media), el deterioro acumulado hace el argumento más fuerte, no más débil.

La recomendación de despliegue se desprende del análisis: **priorizar el mantenimiento basado en
condición (CBM) en los componentes de alta severidad —frenos, llantas, wheel-end—**, donde la
combinación de prevalencia del defecto y costo de cola es máxima, y **calibrar los parámetros de
probabilidad $P$ con datos de la propia flota** mediante un piloto interno que convierta las cotas
conservadoras de este documento en cifras propias.

---

## Fuentes y notas

Las cifras se marcan **[A]** autoritativas (agencia federal / revisado por pares / organismo oficial)
o **[C]** comerciales/de industria (interesadas; ilustrativas).

1. **[A]** FMCSA — *Crash Costs Methodology, 2025 Update*, Tabla 3 (costos por severidad, USD 2023).
2. **[A]** FMCSA — *Large Truck Crash Causation Study (LTCCS)*, Report to Congress (RR por factor
   asociado; *critical reason*). https://ai.fmcsa.dot.gov/downloadFile.axd?file=LTCCS+reportcongress_11_05.pdf
3. **[A]** FMCSA — *SMS Effectiveness Test* (2014) y *Vehicle Maintenance BASIC* (5.65 vs 3.43
   choques/100 unidades; +79 % con alerta en cualquier BASIC).
   https://csa.fmcsa.dot.gov/documents/fmc_csa_12_009_basics_vehmaint.pdf
4. **[A]** ATRI — *Nuclear Verdicts & Litigation Costs* (mediana $36 M en 2022; +5.7 %/año; share
   >$50 M +6.4 pts). Vía CCJ:
   https://www.ccjdigital.com/business/insurance/article/15773236/atri-report-trucking-nuclear-verdicts-litigation-costs-surge
5. **[A]** ATRI — *An Analysis of the Operational Costs of Trucking* (2024 / 2025 Update): costo
   marginal $2.26/mi = $90.89/h; M&R $0.198–0.202/mi; primas +12.5 % a 9.9 ¢/mi (2023); MMBRR; dwell.
   https://truckingresearch.org/about-atri/atri-research/operational-costs-of-trucking/
6. **[A]** DOE / FEMP (PNNL) — *Operations & Maintenance Best Practices Guide*, R3.0, Cap. 5
   (Predictive Maintenance): ROI 10×; −25–30 % costo; −70–75 % descomposturas; −35–45 % downtime;
   reactivo 3–5× planeado. https://www.energy.gov/sites/prod/files/2020/04/f74/omguide_complete_w-eo-disclaimer.pdf
   · PNNL-14788: https://www.pnnl.gov/main/publications/external/technical_reports/pnnl-14788.pdf
7. **[A]** TMC (ATA) — *Recommended Practice RP 622B* (secuencia de cascada de falla de extremo de
   rueda) y benchmarking TMC/FleetNet (~$522/evento). https://tmc.trucking.org/node/294
8. **[A]** Barlow, R. & Proschan, F. (1965), *Mathematical Theory of Reliability*; Barlow & Hunter
   (1960), *Optimum Preventive Maintenance Policies* — modelo de Age Replacement, $T^\star$ bajo IFR.
9. **[A]** Theissler, A. *et al.* (2021), "Predictive maintenance enabled by machine learning…",
   *Reliability Engineering & System Safety* 215:107864.
   https://www.sciencedirect.com/science/article/pii/S0951832021003835
10. **[A]** *Insights into motor carrier crashes… FMCSA inspection violations*, *Accident Analysis &
    Prevention* (revisado por pares). https://www.sciencedirect.com/science/article/abs/pii/S0001457521001366
11. **[A]** CVSA — *International Roadcheck* (datos OOS anuales, frenos/llantas).
12. **[A]** INEGI — *Estadística de Accidentes de Tránsito Terrestre en Zonas Urbanas y Suburbanas
    (ATUS), 2023* (27,594 pesados de carga). https://www.inegi.org.mx/rnm/index.php/catalog/903/
13. **[A]** CANACAR / SICT — antigüedad de la flota de autotransporte de carga (~19.3 años; 68.8 %
    >10 años). https://canacar.com.mx/stat/antiguedad-la-flota-vehicular-del-autotransporte-carga/
14. **[A]** IMT — *Anuario Estadístico de Accidentes en Carreteras Federales* (fallas por estado
    físico; cota macro % del PIB). https://imt.mx/
15. **[A]** 49 CFR §393.95 — equipo de emergencia obligatorio (FMCSA).
16. **[C]** Estimaciones de la industria aseguradora y de proveedores (castigo de prima 15–30 % por
    CSA pobre; umbrales de filtrado de shippers 60–70 %; descuentos UBI/telemática 15–40 %; grúa
    pesada $4–15/mi + enganche; "costo de día parado" $448–760). Útiles como ilustración; no
    sustituyen a una cotización propia.

---

*Documento de PhAIMaT. Las probabilidades $P(\cdot)$ de la ecuación de $c_f$ deben calibrarse con
datos de la flota del cliente; las cifras de este whitepaper son cotas y anclas de referencia, no
sustituyen un piloto de calibración.*
