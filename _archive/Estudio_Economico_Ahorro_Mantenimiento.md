# Estudio económico — Ahorro por adopción de mantenimiento predictivo bajo estimación en streaming

**Modelo de costos desde teoría de renovación-recompensa, con el ahorro como función de la calidad de predicción y de la curva de aprendizaje de la flota.**
Versión 1.0 — Junio 2026

> Postura: este documento separa explícitamente (a) lo **establecido** (matemática de renovación-recompensa; cifras reportadas por DOE/FEMP), (b) lo **derivado del modelo** (curvas de ahorro, ilustrativas con parámetros a sustituir por datos reales) y (c) los **caveats** que pueden anular el ahorro. Las cifras monetarias son ilustrativas hasta instanciar con costos reales (§10).

---

## 1. Resumen ejecutivo

1. El ahorro del esquema **no** proviene de comprar menos piezas. Contra un régimen reactivo (run-to-failure), el predictivo típicamente compra **más** piezas (reemplaza antes de la falla). El ahorro proviene de **evitar el costo consecuencial y catastrófico de la falla** (downtime, grúa, daño secundario, falla en ruta, pérdida de unidad/carga), que domina porque $c_f \gg c_p$.
2. El ahorro **escala con la calidad de predicción** y por tanto **crece conforme la flota acumula datos** (régimen streaming): de modesto al inicio a cercano al límite ideal $1-c_p/c_f^{\text{eff}}$ cuando la predicción madura.
3. Hay un **piso y un techo**: el piso es el mantenimiento preventivo por edad (que ya ahorra ~40% vs reactivo en el ejemplo); el techo es la predicción perfecta. El predictivo es la rampa entre ambos. Con muy pocos datos, el predictivo **ingenuo puede ser peor que reactivo** — por eso se cae a PM como piso hasta que la predicción lo supere.
4. Evidencia externa (DOE/FEMP): preventivo sobre reactivo **12–18%**; predictivo sobre preventivo **8–12%**; reactivo→predictivo **>30–40%**. Son cifras de encuestas/estudios de caso, no de ensayos controlados — se usan como anclas de plausibilidad, no como ley.

---

## 2. El régimen de streaming (recálculo continuo)

El sistema mantiene, por componente, una **posterior** sobre el estado de degradación y los parámetros de vida, que se **actualiza continuamente** con cada lectura de telemetría y, sobre todo, con cada **reparación observada** (las etiquetas). Formalmente, la incertidumbre de la predicción de vida remanente, $\sigma_{\text{RUL}}$, se contrae conforme se acumulan fallas observadas $N$:

$$\sigma_{\text{RUL}}(N) \;\approx\; \sigma_\infty \;+\; \frac{A}{\sqrt{N}},$$

donde $\sigma_\infty$ es el ruido irreducible (variabilidad intrínseca del proceso) y el término $A/\sqrt{N}$ es la contracción estadística estándar de la posterior. El **modelo jerárquico** (clase→marca→modelo→unidad) aumenta el $N$ efectivo de los grupos data-pobres vía partial pooling, acelerando esta contracción. El umbral de decisión (cuándo intervenir) se recalcula al vuelo con la posterior vigente: es lo que hace que el ahorro sea **dinámico**, no fijo.

---

## 3. Marco económico: costo por política (renovación-recompensa)

Para un componente que se desgasta (Weibull con forma $\beta>1$, escala $\eta$), con MTTF $\mu = \eta\,\Gamma(1+1/\beta)$ y confiabilidad $R(t)=e^{-(t/\eta)^\beta}$. Costos: $c_p$ = intervención planeada (pieza + mano de obra); $c_f$ = costo de falla (incluye consecuencial); fracción $\phi$ de fallas escala a catastrófica con costo $c_{\text{cat}}\gg c_f$ (daño mayor / pérdida de unidad). Costo esperado de una falla:

$$c_f^{\text{eff}} = (1-\phi)\,c_f + \phi\,c_{\text{cat}}.$$

Por el **teorema de renovación-recompensa**, la tasa de costo de largo plazo es $\dfrac{\mathbb{E}[\text{costo por ciclo}]}{\mathbb{E}[\text{duración del ciclo}]}$.

### 3.1 Reactiva (run-to-failure)
Cada ciclo termina en falla, dura en promedio $\mu$:
$$\boxed{\,C_R = \dfrac{c_f^{\text{eff}}}{\mu}\,}$$

### 3.2 Preventiva por edad (reemplazo a edad $T_p$ o a la falla)
$$C_{PM}(T_p) = \frac{c_p\,R(T_p) + c_f^{\text{eff}}\,[1-R(T_p)]}{\displaystyle\int_0^{T_p} R(t)\,dt}, \qquad T_p^\* = \arg\min_{T_p} C_{PM}(T_p).$$
Con $\beta>1$ y $c_f^{\text{eff}}\gg c_p$, el óptimo $T_p^\*$ se adelanta respecto a $\mu$.

### 3.3 Predictiva (condición, con predicción imperfecta)
El predictivo intenta reemplazar **justo antes** de la falla. Con predicción imperfecta, modelamos dos cantidades: $\kappa\in(0,1]$ = fracción de vida capturada (qué tan cerca de la falla logras reemplazar) y $q$ = probabilidad de fallar antes de intervenir. La tasa de costo:

$$\boxed{\,C_{PdM}(\kappa,q) = \frac{c_p\,(1-q) + c_f^{\text{eff}}\,q}{\mu\,[\,(1-q)\,\kappa + q\,]}\,}$$

**Límite ideal** (predicción perfecta, $\kappa\to1$, $q\to0$): $C_{PdM}\to c_p/\mu$, de donde el **ahorro máximo** vs reactiva es

$$\boxed{\,\text{ahorro}_{\max} = 1 - \frac{c_p}{c_f^{\text{eff}}} = 1 - \frac{1}{\rho^{\text{eff}}}\,}, \qquad \rho^{\text{eff}}=\frac{c_f^{\text{eff}}}{c_p}.$$

Esto dice algo importante y exacto: **el ahorro tope lo fija la razón costo-de-falla / costo-planeado.** Si una falla cuesta 5× una intervención planeada, el tope es 80%. Si cuesta 1.5×, el tope es 33%. La economía vive y muere por $\rho^{\text{eff}}$.

---

## 4. Ahorro como función de la calidad de predicción

La calidad de predicción se resume en $CV_{\text{RUL}}=\sigma_{\text{RUL}}/\mu$. Fijando un objetivo de riesgo $q=\alpha$ (p. ej. 5%), el buffer de seguridad cuesta $z_{1-\alpha}\,\sigma_{\text{RUL}}$ de vida sacrificada, de modo que $\kappa = 1 - CV_{\text{RUL}}\,z_{1-\alpha}$.

Ejemplo (Weibull $\beta=2.5,\ \eta=1800$ h, MTTF $\mu=1597$ h; $c_p=2500$, $c_f=10000$, $\phi=5\%$, $c_{\text{cat}}=80000$ MXN $\Rightarrow c_f^{\text{eff}}=13500$, $\rho^{\text{eff}}=5.4$):

| $CV_{\text{RUL}}$ | $\kappa$ | tasa (MXN/h) | ahorro vs reactiva | ahorro vs preventiva |
|---|---|---|---|---|
| 0.40 | 0.34 | 5.09 | 39.7% | −2.1% |
| 0.30 | 0.51 | 3.60 | 57.5% | 27.9% |
| 0.20 | 0.67 | 2.78 | 67.1% | 44.3% |
| 0.10 | 0.84 | 2.26 | 73.2% | 54.6% |
| 0.05 | 0.92 | 2.07 | 75.5% | 58.5% |
| **ideal** | 1.00 | 1.57 | **81.5%** | 68.6% |

Referencias del ejemplo: reactiva $C_R=8.45$ MXN/h; preventiva óptima $T_p^\*=854$ h ($0.53\,\mu$) con $C_{PM}^\*=4.99$ MXN/h (**41% vs reactiva**). El predictivo solo **supera** al preventivo cuando $CV_{\text{RUL}}\lesssim 0.35$; por debajo de esa calidad conviene quedarse en preventivo.

---

## 5. La curva de aprendizaje (el ahorro es dinámico)

Sustituyendo $CV_{\text{RUL}}(N)=CV_\infty + A/\sqrt{N}$ (con $CV_\infty=0.06$, $A=1.2$ ilustrativos) en el modelo:

| $N$ (fallas observadas) | $CV_{\text{RUL}}$ | ahorro vs reactiva |
|---|---|---|
| 5 | 0.60 | **−234%** (peor que reactiva) |
| 20 | 0.33 | 53.6% |
| 50 | 0.23 | 64.8% |
| 100 | 0.18 | 68.6% |
| 300 | 0.13 | 71.7% |
| 1000 | 0.10 | 73.3% |

Dos lecturas críticas:
- **Con muy pocos datos el predictivo ingenuo destruye valor** (reemplaza demasiado pronto y aun así falla). La regla operativa es tomar $\min$ sobre políticas: nunca hacer peor que el preventivo. El predictivo es **upside sobre el piso del 41%**, que se materializa conforme $N$ crece.
- **Hay rezago de ROI.** El valor no es instantáneo; arranca cuando se acumulan ~20–50 fallas observadas por grupo de componente. El pooling jerárquico acorta este rezago al compartir $N$ entre marcas.

---

## 6. Descomposición piezas vs unidades (corrección honesta)

Pregunta natural: "¿ahorramos en piezas?" La respuesta exacta depende del baseline:

| Comparación | Piezas | Fallas / catastróficas |
|---|---|---|
| Predictivo **vs reactivo (su baseline actual)** | **+33%** (más piezas: reemplaza antes de la falla) | evita ~351 de 376 fallas/año; ahorro catastrófico ≈ **1.23 M MXN/año** |
| Predictivo **vs preventivo conservador** | **menos** piezas (captura más vida que un calendario fijo) | similar |

Es decir: **el ahorro en "piezas" es real solo contra un programa preventivo de calendario** (el predictivo desperdicia menos vida). Contra el reactivo actual, las piezas **suben** modestamente y el ahorro viene de **unidades**: fallas consecuenciales y catastróficas evitadas. Esto coincide con FEMP: el predictivo "prácticamente elimina las fallas catastróficas" y permite "minimizar inventario y pedir piezas con anticipación" (suaviza el flujo de compras, no necesariamente lo reduce).

El ahorro neto vs reactivo es:
$$\text{Ahorro}_{\text{neto}} = \underbrace{(\text{costo de fallas/catástrofes evitadas})}_{\text{grande, } \sim\text{unidades}} - \underbrace{(\text{costo de piezas extra por reemplazo temprano})}_{\text{pequeño cuando }\kappa\to1}.$$

---

## 7. Agregado de flota (dinero anual)

Por tipo de componente $k$, con $n_k$ unidades y $H_k$ horas-motor/año:
$$\text{Ahorro anual} = \sum_k n_k\,H_k\,\big(C_{R,k} - C_{PdM,k}\big).$$

Ejemplo ilustrativo (200 unidades, 3000 h/año, $CV_{\text{RUL}}=0.15$ maduro, una posición de balata):
- Costo anual reactiva: **5.07 M MXN**
- Costo anual predictiva: **1.50 M MXN**
- **Ahorro anual: 3.58 M MXN (70.5%)**, de los cuales ≈1.23 M provienen de catástrofes evitadas.

Esto es **una** posición de **un** componente. La flota tiene múltiples componentes por unidad; el agregado escala con la suma. (Números ilustrativos hasta instanciar §10.)

---

## 8. Evidencia empírica (fuente primaria + escepticismo)

**DOE/FEMP, O&M Best Practices Guide, Release 3.0, Cap. 5** (Sullivan et al., PNNL) — fuente primaria, citada verbatim:
- Preventivo sobre reactivo: **12–18%** de ahorro promedio.
- Predictivo sobre preventivo: **8–12%**.
- Reactivo→predictivo: **>30–40%**, según la dependencia previa del reactivo.
- "Encuestas independientes" (industrial average): ROI **10×**, reducción de costo de mantenimiento **25–30%**, eliminación de averías **70–75%**, reducción de downtime **35–45%**, aumento de producción **20–25%**.
- Cualitativo clave: un programa predictivo bien orquestado "prácticamente elimina las fallas catastróficas" y permite "minimizar inventario".

**Escepticismo obligatorio:** estas cifras son de **encuestas y estudios de caso**, no de ensayos controlados con grupo de comparación. Tienen sesgo de selección (quien reporta es quien tuvo éxito) y de publicación. La estructura (preventivo<predictivo, ahorro mayor cuando se parte de reactivo, eliminación de catástrofes) es robusta y coincide con el modelo de §3–4; las **magnitudes puntuales** deben validarse con datos propios, no adoptarse como objetivo.

Coincidencia con nuestro modelo: el rango FEMP de 30–40% (reactivo→predictivo) corresponde, en nuestro modelo, a calidad de predicción **moderada** ($CV_{\text{RUL}}\approx0.3$–$0.4$); el 70–75% de "eliminación de averías" corresponde a $q=\alpha$ pequeño (objetivo de riesgo bajo). El modelo no contradice la evidencia; la **explica mecánicamente**.

---

## 9. Caveats críticos (lo que puede anular el ahorro)

1. **Requiere desgaste ($\beta>1$).** Si el componente falla aleatoriamente ($\beta=1$, vida útil de la bañera) o por mortalidad infantil ($\beta<1$), el reemplazo preventivo/predictivo **no ahorra** — solo el monitoreo de condición real de la degradación ayuda, no la edad. Verificar $\beta$ por componente antes de prometer ahorro.
2. **Todo depende de $\rho^{\text{eff}}=c_f^{\text{eff}}/c_p$.** Si las fallas son baratas (componente no crítico, sin consecuencias), el tope de ahorro es chico y el predictivo no se paga. El predictivo se justifica en componentes con **falla cara** (aftertreatment, frenos, transmisión), no en todo.
3. **$c_f^{\text{eff}}$ es lo más difícil de estimar y domina el resultado.** Downtime, falla en ruta, daño secundario, pérdida de carga: estos números mandan y son los más inciertos. La calidad del estudio = la calidad de la estimación de $c_f$.
4. **Falsos positivos erosionan el ahorro y la confianza.** Reemplazos innecesarios (predicción que alarma de más) suman costo de pieza y minan la confianza del taller. El objetivo no es solo recall alto, sino **costo esperado mínimo** (calibración + explicabilidad).
5. **Rezago de ROI y capex inicial.** FEMP: arrancar predictivo "no es barato" (equipo, capacitación). El valor llega tras acumular datos (§5). Presupuestar el rezago.
6. **No toda falla es predecible.** Modos súbitos sin precursor medible no se ganan con este esquema; el ahorro aplica a los modos con degradación observable.

---

## 10. Cómo instanciar con datos reales

Para convertir este modelo de ilustrativo a operativo, medir (todo capturable con el esquema WS-A y la telemetría):
- $\beta, \eta$ **por componente** (del ajuste de supervivencia sobre las etiquetas WS-A).
- $c_p$: costo de intervención planeada (pieza + mano de obra) — campo `cost_*` de WS-A.
- $c_f$ y sus componentes (downtime $\times$ tarifa, grúa, daño secundario, multa) — campos `cost_towing`, `downtime_h`, `in_route`, `cost_fine`.
- $\phi, c_{\text{cat}}$: fracción y costo de escalamiento catastrófico — del histórico de fallas mayores / pérdidas de unidad.
- $\sigma_{\text{RUL}}$: de la posterior del modelo ajustado (es un *output* del sistema, se mide directamente).
- $n_k, H_k$: tamaño de flota y uso anual por componente.

Con esos seis grupos de números, las ecuaciones de §3–7 dan el ahorro **específico de su flota**, con intervalos de confianza propagados desde la incertidumbre de cada entrada.

---

*Estudio económico. Matemática de renovación-recompensa: establecida (Barlow–Proschan; Jardine–Tsang). Cifras FEMP: reportadas (encuestas, no ensayos). Curvas de ahorro: derivadas del modelo, ilustrativas hasta instanciar §10. El ahorro real depende críticamente de $\rho^{\text{eff}}$ y de $\beta>1$; verificar ambos por componente antes de comprometer cifras.*
