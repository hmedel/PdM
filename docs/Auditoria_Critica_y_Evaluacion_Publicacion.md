# Auditoría crítica y evaluación de publicación

**Revisión ultra-crítica de corrección + evaluación honesta del gap de publicación.**
Versión 1.0 — Junio 2026

> Propósito: dejar de producir y **auditar**. Este documento busca errores, no valida. Y responde sin vanidad si hay una contribución publicable (en *Operations Research* u otro venue) o no.

---

## Parte 1 — Auditoría de corrección

### 1.1 Verificado correcto (spot-checks ejecutados)

| Resultado | Verificación | Estado |
|---|---|---|
| **RUL condicional Weibull** (Fund. II.2.4): $\mathbb{E}[T\mid T{>}t]=\eta e^{w}\Gamma(1{+}\tfrac1\beta,w)$ | La recurrencia $\Gamma(1{+}\tfrac1\beta,x)=\tfrac1\beta\Gamma(\tfrac1\beta,x)+x^{1/\beta}e^{-x}$ absorbe exactamente el $+t$: $\eta e^{w}\Gamma(1{+}\tfrac1\beta,w)=\tfrac\eta\beta e^{w}\Gamma(\tfrac1\beta,w)+t=\mathrm{MRL}(t)+t$ | **Correcto** |
| **Tasa de costo reactivo** $C_{\text{rtf}}=c_f/\text{MTTF}$ | Renovación-recompensa: ciclo = vida completa, costo $c_f$, duración media MTTF | **Correcto** |
| **Techo predictivo** $1-1/\rho$ | $c_p/\text{MTTF}$ dividido por $c_f/\text{MTTF}$; perfecto reemplazo justo antes de fallar | **Correcto** |
| **Teorema IFR** ($\beta\le1\Rightarrow$ ahorro 0) | Para exponencial, $C(T)\downarrow C_{\text{rtf}}$ monótono cuando $T\to\infty$; cualquier $T$ finito es peor | **Correcto** (confirmado numéricamente) |
| **Decoder J1939** (PGN/PDU1-2, señal LE, DM1 v4) | 7 vectores de prueba (Python) | **Correcto** |
| **Encoder** (inverso) | round-trip encode→decode exacto | **Correcto** |
| **Recuperación del generador** ($\beta,\gamma,\eta_0$ por grupo) | dentro de ±5.4% con estimador bien especificado | **Correcto** |
| L10 = $(C/P)^p$, Archard, AFT-Weibull (Gumbel), umbral de Bayes $p^\*$ | resultados estándar, revisados | **Correcto** |

### 1.2 Error encontrado y corregido

- **Fund. IV.2 (proceso Gamma):** $R(t)=P(X(t){<}a)$ estaba escrita con la gamma incompleta **superior** $\Gamma(\alpha t,\lambda a)/\Gamma(\alpha t)$, que es $P(X{>}a)$ — la probabilidad de **falla**, no de supervivencia. Debe ser la **inferior** $\gamma(\alpha t,\lambda a)/\Gamma(\alpha t)$. **Corregido.** (Severidad: media — un signo invertido en una de las distribuciones de degradación.)

### 1.3 Marcado para verificar (no vouching)

| Ítem | Riesgo | Acción |
|---|---|---|
| **Layouts SPN en `J1939.jl`** (175,183,100,247,245,168,91,92,98) | Escritos de memoria; marcados `verified=false` | Confirmar byte/PGN contra J1939-71 o DBC OEM **antes de producción** |
| **SPN exacto de NOx** (rango 3200s) | Fuentes en conflicto (3226 ambiguo) | Confirmar contra J1939-71 |
| **Aftertreatment PGN** (3251,1761,5246) | `pgn=0` a propósito | Poblar de DBC |
| **Refs marcadas `(verificar)`** en bibliografía | Varias no reconfirmadas en fuente original | Verificar DOIs/páginas antes de citar formalmente |
| **Código Julia** (`J1939.jl`, `SyntheticFleet.jl`) | No ejecutado (sin Julia en el entorno); lógica cross-validada en Python | Correr `test_*.jl` del lado del equipo |

### 1.4 Stubs / gaps conocidos (declarados, no ocultos)

- **TP/BAM (J1939-21):** sin reensamblado multipaquete → DM1 con >1 DTC no se lee en campo. Stub declarado.
- **Proxies sin calibrar** (Archard, rainflow): ordinales hasta tener ground truth. Riesgo registrado.
- **DPF en el generador:** usa $\eta_0$ de balata (placeholder). TODO declarado.

### 1.5 Riesgos de sobreafirmación (a vigilar)

1. **Regla de Miner ($D{=}1$):** es un modelo de daño **lineal**, conocido por ser impreciso (el $D$ real a falla varía ~0.7–2.2; ref. Fatemi-Yang). El documento debe presentarlo como aproximación de primer orden, no como ley exacta.
2. **Energía de frenado "$\propto m\,v\,\Delta v$":** es la linealización de $\tfrac12 m\,(v_1^2-v_2^2)$; correcto como proxy de escala, no como identidad.
3. **"La física transfiere entre marcas":** comparte la **forma funcional**, no las constantes; ya está acotado en §11 del dossier, mantener la disciplina.
4. **Ramp-up "95% con 5 fallas":** válido bajo poca censura; con flota joven (censura pesada) la varianza del estimador es mayor y el ramp en calendario es más lento. El caveat ya está; no soltarlo.

**Veredicto de auditoría:** la matemática central está **correcta** (un error de notación corregido). Los riesgos reales no son de teoría sino de **insumos sin verificar** (layouts SPN, refs) y **código no ejecutado en Julia** — ambos cerrables con trabajo mecánico del lado del equipo.

---

## Parte 2 — Evaluación de publicación (honesta)

### 2.1 La pregunta directa: ¿hay contribución para *Operations Research*?

**No.** Dos razones, ambas duras:

1. ***Operations Research* (INFORMS) no publica aplicaciones de PdM.** Publica contribuciones **metodológicas/teóricas** fundamentales (nueva teoría de optimización, control estocástico, resultados estructurales con demostración). Un sistema de mantenimiento predictivo, por bueno que sea, es una **aplicación** → desk reject. El venue está mal elegido.

2. **El "diferenciador" que imaginábamos ya está publicado, y reciente.** Las búsquedas lo confirman:
   - **Bull et al. (2023), Computer-Aided Civil and Infrastructure Engineering** — modelado jerárquico bayesiano para transferencia entre flotas vía multitask; grupos con datos incompletos toman prestada fuerza de los ricos en datos; análisis de supervivencia; reducción ~70% en SD de parámetros. **= nuestro pooling jerárquico cross-flota.**
   - **RESS (2025)** — Cox PH + jerárquico bayesiano con prior compartido para transfer learning entre poblaciones, con variaciones intra e inter, en motores de turbina. **= nuestro Cox + jerárquico multi-clase.**
   - **BMTR-Former (2025)** — censura tratada como recurso, no limitación, con jerárquico bayesiano; SOTA en datasets censurados. **= nuestra "censura de primera clase".**
   - **Physics-informed RUL** (PINN+atención 2023; data augmentation 2024) — el ángulo físico está saturado.

   Conclusión: el núcleo conceptual del proyecto es una **síntesis competente del estado del arte**, no una contribución novel. Como *method paper* sería rechazado por falta de novedad.

### 2.2 Lo que SÍ es defendible (y dónde)

El proyecto tiene valor real, pero su lugar no es OR ni un method paper:

- **Como producto:** es ingeniería sólida sobre un nicho (flota mixta pesado/ligero/moto, edge J1939 propio, gobernanza de datos). El valor es comercial, no académico.
- **Como *applied / case study* (post-despliegue):** un reporte en **RESS, IISE Transactions, IEEE Trans. Reliability, Mechanical Systems and Signal Processing, o PHM Society** es realista **si y solo si** hay (a) datos reales de una flota mixta, (b) comparación contra baselines, (c) ahorro validado. Pero sería "estudio de caso aplicado", no "método nuevo", y solo **después** de tener resultados.

### 2.3 El único ángulo con potencial de contribución genuina

Si el objetivo es **publicar de verdad** (no solo construir), el hueco menos explorado —y el único con sabor a OR/MSOM/Stochastic Systems— es:

> **Decisión-mientras-se-aprende para una flota multi-clase con datos censurados y prior físico:** formalizar el *value of information* de cada falla observada y el explore-exploit entre "reemplazar por seguridad" vs "dejar correr para aprender la distribución", con **resultados estructurales o cotas de regret**, especializado al setting censura + prior de física-de-falla.

Esto NO lo tenemos —es un proyecto de investigación propio, requiere teoría real (estructura de política óptima, regret), y el área (bandits/RL para mantenimiento) también tiene literatura previa, así que tampoco es fruta baja. Pero es el único sitio donde una contribución formal podría existir. El POMDP de Fund. VIII.5 es la puerta; hoy solo está enunciado, no demostrado.

### 2.4 Recomendación

1. **No persigan *Operations Research*** con lo que hay; es perder el tiempo en desk reject.
2. **El entregable es el producto**, no un paper. El ahorro (40–50% en componentes de desgaste caros) es la tesis de negocio, y es sólida.
3. **Si quieren un paper**, el camino realista es un **estudio de caso aplicado post-despliegue** (RESS/IISE/PHM) con datos y comparación reales — no antes.
4. **Si quieren investigación de verdad**, el proyecto es el de §2.3 (aprender-y-decidir con cotas), que es separado y ambicioso. Decidir explícitamente si vale el costo de oportunidad frente a construir el producto.

> Honestidad final: la tentación de "esto da para un paper en OR" es exactamente el *method-shopping*/vanidad que acordamos vigilar. El trabajo es bueno; su valor es el producto y la disciplina con que está hecho, no una publicación que el estado del arte ya ocupó.
