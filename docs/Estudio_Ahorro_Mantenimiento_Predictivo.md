# Estudio de Ahorro — Mantenimiento Predictivo vs Reactivo

**Cuánto se ahorra al adoptar mantenimiento basado en condición/predictivo, derivado desde renovación-recompensa, con números y literatura verificada.**
Versión 1.0 — Junio 2026

> Tesis honesta (postdoc): el ahorro **no es incondicional**. Es un teorema que el mantenimiento preventivo solo ahorra cuando hay **desgaste** ($\beta>1$) **y** la falla es mucho más cara que la intervención planeada ($\rho=c_f/c_p$ alto). Donde las fallas son aleatorias, el predictivo no ahorra nada. Este documento cuantifica cuándo y cuánto, separa lo establecido de lo gris, y da el procedimiento para estimarlo con sus propios datos.

---

## 0. Resumen ejecutivo

| Magnitud | Valor | Origen |
|---|---|---|
| Ahorro preventivo-óptimo vs reactivo, balata ($\beta{=}2.3$, $\rho{=}8.4$) | **~50%** | cálculo (§5) |
| Techo predictivo (predicción perfecta), mismo caso | **~88%** | $1-1/\rho$ (§2.4) |
| Ahorro si $\beta\le1$ (fallas aleatorias) | **0%** | teorema IFR (§2.3) |
| Fallas observadas para capturar ~95% del ahorro óptimo | **~5** | ramp-up (§6) |
| Reducción de costo de mantenimiento, predictivo vs reactivo (literatura) | **25–30%** (blended de flota) | DOE/FEMP 2010 (§9) |
| Reparación reactiva vs proactiva (razón de costo) | **4–5×** (más en flota por en-ruta) | industria (§4) |

La conclusión operativa: el dinero está en **componentes de desgaste con falla cara** (DPF, balatas, rodamientos), no en electrónica de falla aleatoria. El sistema debe enfocar ahí.

---

## 1. Marco: tres regímenes y su costo de largo plazo

Por **renovación-recompensa** (Barlow & Proschan 1965; Jardine & Tsang 2013), el costo de largo plazo por unidad de tiempo de una política cíclica es

$$C = \frac{E[\text{costo por ciclo}]}{E[\text{duración del ciclo}]}.$$

Tres políticas, tres costos:

- **Reactivo (run-to-failure):** cada ciclo termina en falla. Duración media $=$ MTTF $=\int_0^\infty R(t)\,dt$; costo $=c_f$.
  $$\boxed{C_{\text{rtf}} = \frac{c_f}{\text{MTTF}}}$$
- **Preventivo por edad:** se reemplaza al fallar o al alcanzar la edad $T$, lo que ocurra primero.
  $$\boxed{C_{\text{edad}}(T) = \frac{c_p\,R(T) + c_f\,[1-R(T)]}{\int_0^{T} R(t)\,dt}}, \qquad C^\star=\min_T C_{\text{edad}}(T)$$
- **Predictivo (condición):** usa la RUL condicional para reemplazar **justo antes** de la falla. En el límite de predicción perfecta paga solo $c_p$ por ciclo, sin desperdiciar vida ni pagar $c_f$:
  $$\boxed{C_{\text{pred}}^{\min} = \frac{c_p}{\text{MTTF}}}$$

Jerarquía garantizada: $\;C_{\text{rtf}} \ge C_{\text{edad}}^\star \ge C_{\text{cbm}} \ge C_{\text{pred}}^{\min}$. El ahorro vive entre el primero y el último.

---

## 2. El modelo de ahorro (matemática)

Usamos Weibull, $R(t)=\exp[-(t/\eta)^\beta]$, $\text{MTTF}=\eta\,\Gamma(1+1/\beta)$ (justificación de por qué Weibull: Fundamentos Parte II).

### 2.1 Ahorro preventivo
$$s_{\text{prev}} = 1 - \frac{C_{\text{edad}}^\star}{C_{\text{rtf}}}.$$

### 2.2 La condición óptima
Derivando $C_{\text{edad}}(T)=0$, el $T^\star$ óptimo satisface
$$h(T^\star)\!\int_0^{T^\star}\!R(t)\,dt \;-\; F(T^\star) \;=\; \frac{c_p}{c_f-c_p},$$
con $h$ la función de riesgo. El lado izquierdo crece solo si $h$ crece — de ahí el teorema:

### 2.3 Teorema (cuándo existe ahorro)
Si la distribución es **IFR** (riesgo creciente, $\beta>1$ en Weibull), existe un $T^\star$ **finito** y $s_{\text{prev}}>0$. Si es **DFR o de riesgo constante** ($\beta\le1$, exponencial), el óptimo es $T^\star\to\infty$: **run-to-failure es óptimo y el preventivo no ahorra nada** (Barlow & Proschan 1965). Intuición física: con falla sin memoria, una pieza usada es estadísticamente idéntica a una nueva; reemplazarla antes tira vida útil sin reducir el riesgo.

> Implicación de diseño: el módulo debe estimar $\beta$ por componente y **no programar preventivo donde $\beta\le1$**. Hacerlo es quemar dinero.

### 2.4 El techo predictivo
$$s_{\text{pred}}^{\max} = 1 - \frac{C_{\text{pred}}^{\min}}{C_{\text{rtf}}} = 1 - \frac{c_p}{c_f} = \boxed{1 - \frac{1}{\rho}}, \qquad \rho=\frac{c_f}{c_p}.$$
Cota dura e independiente de $\beta$: $\rho=2\Rightarrow50\%$, $\rho=4\Rightarrow75\%$, $\rho=8\Rightarrow88\%$. Ningún algoritmo, por sofisticado, supera esto; la palanca es $\rho$, no el modelo.

---

## 3. Cuándo y cuánto se ahorra (el mapa $(\beta,\rho)$)

Cálculo de $s_{\text{prev}}$ (ahorro preventivo-óptimo vs reactivo) y del techo predictivo, normalizado $c_p=1$:

| $\beta$ | $\rho{=}2$: $T^\star/\eta$, $s_{\text{prev}}$, techo | $\rho{=}4$ | $\rho{=}8$ |
|---|---|---|---|
| 0.8 | $\infty$, **0%**, 50% | $\infty$, **0%**, 75% | $\infty$, **0%**, 88% |
| 1.0 | $\infty$, **0%**, 50% | $\infty$, **0%**, 75% | $\infty$, **0%**, 88% |
| 1.5 | 2.17, 0%, 50% | 0.84, 7%, 75% | 0.45, 20%, 88% |
| 2.0 | 1.09, 3%, 50% | 0.59, 21%, 75% | 0.38, 41%, 88% |
| 2.3 | 0.94, 6%, 50% | 0.56, 28%, 75% | 0.39, **48%**, 88% |
| 3.0 | 0.81, 12%, 50% | 0.55, 38%, 75% | 0.42, 59%, 88% |

Lecturas:
- **$\beta\le1$: ahorro 0%** en cualquier $\rho$. (Confirma el teorema.)
- El ahorro preventivo crece con $\beta$ (más desgaste → más predecible) **y** con $\rho$.
- Hay una **brecha grande entre el preventivo-óptimo (~48%) y el techo predictivo (~88%)** en el caso de desgaste con $\rho$ alto: esa brecha de ~40 puntos es exactamente **el valor que captura el predictivo/CBM** (RUL condicional) sobre un calendario óptimo. Es la justificación del sistema de modelado, no del calendario.

---

## 4. De dónde sale $\rho$: la estructura de costos

$\rho=c_f/c_p$ es la palanca, y en flota es alto porque la falla arrastra consecuencias que la intervención planeada no:

$$c_f = \underbrace{\text{piezas} + \text{mano de obra}}_{\approx\,c_p} + \text{grúa} + \text{downtime}\times\tfrac{\$}{\text{h}} + \text{daño secundario} + \text{penalización en-ruta (multas, carga)}$$

$$c_p = \text{piezas} + \text{mano de obra (programada, sin premium)}$$

La industria reporta que **la reparación reactiva cuesta 4–5× la proactiva** (estimaciones de campo); nuestra descomposición da $\rho\approx 8$–$10$ para fallas en ruta de camión pesado (grúa + downtime + daño secundario dominan). El **daño secundario** es clave: un rodamiento que falla destruye la maza/flecha; una balata al metal raya el disco — run-to-failure no solo paga la pieza, paga la cascada.

---

## 5. Ejemplos con dinero (camión pesado, MXN)

**Balata de freno** — $\beta=2.3$, $\eta=1500$ h, $c_p=2{,}700$, $c_f=22{,}700$ ($\rho=8.4$), MTTF $=1{,}329$ h:

| Política | Costo / 1000 h | vs reactivo |
|---|---|---|
| Reactivo | 17,082 MXN | — |
| Preventivo óptimo ($T^\star{=}564$ h, 38% de $\eta$) | 8,602 MXN | **−50%** |
| Techo predictivo | 2,032 MXN | −88% |

**DPF / aftertreatment** — $\beta=2.0$, $\eta=4000$ h, $c_p=9{,}000$, $c_f=80{,}000$ ($\rho=8.9$, derate deja varada la unidad), MTTF $=3{,}545$ h:

| Política | Costo / 1000 h | vs reactivo |
|---|---|---|
| Reactivo | 22,568 MXN | — |
| Preventivo óptimo ($T^\star{=}1{,}439$ h, 36% de $\eta$) | 12,774 MXN | **−43%** |
| Techo predictivo | 2,539 MXN | −89% |

Estos son **por componente y por unidad**; el ahorro de flota es la suma sobre componentes y unidades, ponderada por la mezcla (§9).

---

## 6. El régimen de streaming: cómo se realiza el ahorro en el tiempo

La preocupación es legítima: las distribuciones se recalculan continuamente conforme llegan fallas, y durante un buen periodo la solución opera con parámetros mal estimados. Dos resultados:

**(a) El ahorro se captura rápido en número de fallas.** Política plug-in (estimar $(\beta,\eta)$ de $n$ fallas, aplicar $\hat T^\star$, medir su costo real) vs el óptimo oráculo:

| $n$ fallas observadas | Ahorro realizado | % del óptimo capturado |
|---|---|---|
| 5 | 47.2% | **95%** |
| 10 | 48.5% | 98% |
| 20 | 49.1% | 99% |
| 50 | 49.5% | 100% |

La razón es matemática: $C_{\text{edad}}(T)$ es **plana cerca de su mínimo**, así que un $\hat T^\star$ con error moderado cuesta casi lo mismo que el óptimo. La política es **robusta al error de estimación**. No se necesitan cientos de fallas.

**(b) El cuello de botella es calendario, no muestra.** "5 fallas" es poco, pero acumularlas toma tiempo proporcional a la tasa de falla. Mientras tanto, la mayoría de las instancias están **censuradas**, y la incertidumbre de parámetros es mayor con censura pesada. Manejo correcto: un **prior bayesiano informado por física** (Archard, $L_{10}$) da un $\hat T^\star$ razonable desde el día 1, y el posterior se contrae conforme llegan datos (Fundamentos Parte VIII). El buffer conservador temprano (reemplazar un poco antes) cuesta algo de piezas pero evita fallas mientras el modelo madura. Conclusión: el ramp-up del *ahorro* es rápido; el del *aprendizaje* lo acelera el prior físico.

---

## 7. Predictivo sobre preventivo: el valor de la condición

El preventivo-óptimo (§3) usa solo la distribución poblacional. El predictivo/CBM usa la **RUL condicional** (estado de degradación + covariables) para reemplazar más cerca de la falla real, capturando parte de la brecha hacia el techo. La literatura federal lo cuantifica: **8–12% adicional del predictivo sobre el preventivo solo** (DOE/FEMP 2010), y más donde había alta dependencia de reactivo. En nuestro marco, el predictivo realiza una fracción $\phi$ (efectividad de predicción) de la brecha $C_{\text{edad}}^\star - C_{\text{pred}}^{\min}$; $\phi$ depende de la calidad de la RUL (error, lead time, falsos positivos).

---

## 8. Ahorro neto, costo de programa y break-even

El ahorro **bruto** no es el neto. Hay que restar el costo del programa:

$$\text{Ahorro neto} = \underbrace{\sum_{c,u}\big[C_{\text{rtf}}^{(c,u)} - C_{\text{política}}^{(c,u)}\big]\,\tau}_{\text{bruto sobre componentes }c\text{ y unidades }u} \;-\; \underbrace{(\text{hardware} + \text{plataforma} + \text{análisis} + \text{falsos positivos})}_{\text{costo de programa}}$$

El propio FEMP advierte que **arrancar un programa predictivo "no es barato"** (instrumentación de >$50,000 USD en planta). En nuestro caso el costo marginal de hardware por unidad es bajo (el edge ya existe, ~$110 USD/unidad, Bridge §9), así que el costo dominante es plataforma + análisis + el costo de **falsos positivos** (reemplazos innecesarios que erosionan el ahorro y la confianza del taller). Break-even típico reportado por la industria: 6–18 meses; debe validarse con datos propios.

---

## 9. Reconciliación con la literatura (y calidad de evidencia)

| Fuente | Afirmación | Grado |
|---|---|---|
| **US DOE / FEMP, O&M Best Practices Guide R3.0 (2010)** | PdM vs reactivo: ROI 10×; costo −25–30%; paros −70–75%; downtime −35–45%; productividad +20–25% | Guía de programa federal + encuestas de industria. **No** son ensayos controlados; usar como orden de magnitud. |
| **FEMP/PNNL** | PdM sobre PM solo: 8–12% adicional; >30–40% donde domina reactivo | Igual. |
| **EPRI (citado en surveys)** | PdM: −30% vs periódico, −50% vs reactivo | Investigación de industria. |
| **Industria (campo)** | reparación reactiva 4–5× la proactiva ($\rho$) | Estimación; corroborada por nuestra descomposición ($\rho\approx8$–10 en-ruta). |
| **Theissler et al. 2021 (RESS)** | Revisión de PdM automotriz con ML; casos y retos de ROI | Peer-reviewed. |

**Reconciliación del 25–30% vs nuestros 43–50%:** nuestros números son **por componente favorable** (desgaste, $\rho$ alto), sin fricción de implementación. El 25–30% de FEMP es un **promedio de flota** que mezcla componentes de desgaste (ahorro alto) con electrónica de falla aleatoria (ahorro ~0, §2.3) y descuenta fricción real (datos imperfectos, falsos positivos, costo de programa). Ambos son consistentes: el blended baja hacia 25–30%; los componentes objetivo individuales ahorran 40–50%. **No hay magia ni contradicción.**

> Advertencia de evidencia: los porcentajes célebres provienen de literatura gris/programa federal y encuestas, no de RCTs. Los blogs de proveedores (excluidos como evidencia) inflan a "$280 mil millones globales" y similares; eso es marketing. La cifra defendible es: **órdenes de magnitud del DOE/EPRI + la teoría de §2–3 + validación con datos propios.**

---

## 10. Caveats críticos

1. **$\beta\le1$ no ahorra.** Electrónica, sensores y fallas aleatorias: el preventivo es desperdicio. Clasificar por $\beta$ antes de prometer ahorro.
2. **Falsos positivos erosionan el ahorro.** Cada reemplazo innecesario es un $c_p$ tirado y confianza perdida; calibrar umbrales (costo-sensible, Fundamentos VI.2).
3. **$\rho$ es un supuesto, no un dato, hasta medir $c_f$.** El daño secundario y el downtime real deben capturarse (esquema WS-A, campos `cost_*`, `in_route`).
4. **Ramp-up calendario.** El ahorro tarda en realizarse en el tiempo aunque pocas fallas basten; el prior físico lo acelera.
5. **Proxies sin calibrar** (Archard, rainflow) sesgan la estimación de $\eta,\beta$ si se toman como medición; son ordinales hasta calibrar.
6. **Mezcla de flota.** El ahorro agregado depende de la proporción de componentes de desgaste con $\rho$ alto; no extrapolar el caso balata a toda la unidad.

---

## 11. Cómo estimar el ahorro con SUS datos (procedimiento)

Esto convierte el estudio en una calculadora operativa sobre el sistema que estamos construyendo:

1. **Estimar $(\beta,\eta)$ por componente** desde los eventos WS-A (supervivencia con censura/truncamiento, Fundamentos II–III). Filtrar componentes con $\beta\le1$ (no preventivos).
2. **Medir $c_p$ y $c_f$** de los campos `cost_*`/`in_route` del esquema → $\rho$ real por componente.
3. **Calcular** $C_{\text{rtf}}$, $C_{\text{edad}}^\star$, techo $c_p/\text{MTTF}$ por componente (las fórmulas de §2).
4. **Estimar $\phi$** (efectividad de predicción) de la calibración de la RUL (cobertura del IC, lead time) → $C_{\text{cbm}}$.
5. **Agregar** sobre componentes y unidades; **restar** costo de programa → ahorro neto y ROI.
6. **Recalcular en streaming** conforme llegan fallas (Parte VIII); reportar el ahorro realizado vs el techo.

El código del §0–§6 (modelo de costo, óptimo, ramp-up) está en `savings_model.py` y es directamente portable a Julia para el módulo `decision/optimal_interval.jl`.

---

## 12. Referencias

- **US DOE / FEMP (2010).** *Operations & Maintenance Best Practices Guide, Release 3.0.* (cifras 25–30% / 70–75% / 35–45%; PdM sobre PM 8–12%). https://www.energy.gov/femp
- **EPRI** — Predictive maintenance cost reduction (−30% vs periódico, −50% vs reactivo), citado en surveys de PdM.
- **Barlow, R. E. & Proschan, F. (1965).** *Mathematical Theory of Reliability.* Wiley. (Teorema IFR / políticas de reemplazo óptimo.)
- **Jardine, A. K. S. & Tsang, A. H. C. (2013).** *Maintenance, Replacement, and Reliability*, 2nd ed. CRC Press. (Intervalo óptimo de costo.)
- **Wang, H. (2002).** *A survey of maintenance policies of deteriorating systems.* EJOR 139(3), 469–489.
- **Theissler, A. et al. (2021).** *Predictive maintenance enabled by machine learning: use cases and challenges in the automotive industry.* RESS 215, 107864.

*(Referencias cruzadas con la bibliografía maestra del proyecto, secciones I–J. Las cifras de DOE/EPRI son de programa federal/industria, no RCTs; validar con datos propios.)*
