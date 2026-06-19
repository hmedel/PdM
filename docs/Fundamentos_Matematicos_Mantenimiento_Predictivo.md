# Fundamentos Matemáticos del Mantenimiento Predictivo

**Desde primeros principios — para un grupo de físicos teóricos**
Versión 1.0 — Junio 2026

---

## Cómo leer este documento

El objetivo es que cada ecuación que el sistema use tenga aquí su **derivación desde primeros principios**, con la intuición física al lado. No se asume conocimiento previo de ingeniería de confiabilidad ni de tribología; sí se asume cálculo, probabilidad y procesos estocásticos a nivel de posgrado en física. Las referencias [letra+número] remiten al documento *Referencias*.

El hilo conductor es uno solo: **una pieza es un sistema físico cuyo estado se degrada; la falla es el cruce de un umbral; y todo lo demás —estadística de vida, física de desgaste, decisión óptima— son tres lentes sobre ese mismo hecho.** Las tres lentes convergen en la Parte VII.

Estructura:

- **I.** Confiabilidad como teoría de una variable aleatoria de vida.
- **II.** De dónde salen las distribuciones de vida (Weibull desde valores extremos).
- **III.** Inferencia con datos censurados (la realidad de una flota).
- **IV.** Procesos de degradación (la falla como primer cruce).
- **V.** Física de falla (Archard, fatiga, rodamientos, neumáticos) desde primeros principios.
- **VI.** Teoría de decisión (intervalo óptimo, umbral sensible al costo).
- **VII.** Marco unificado: supervivencia jerárquica informada por física.
- **VIII.** Gaps y oportunidades de publicación.

---

# Parte I — Confiabilidad desde la probabilidad

## I.1 El tiempo de vida como variable aleatoria

Sea $T \geq 0$ el tiempo (o km, u horas-motor) hasta la falla de un componente. $T$ es una variable aleatoria con función de distribución acumulada (CDF)

$$F(t) = P(T \leq t),$$

densidad $f(t) = F'(t)$, y **función de confiabilidad** (o supervivencia)

$$R(t) = P(T > t) = 1 - F(t), \qquad R(0)=1,\quad R(\infty)=0.$$

$R(t)$ es la probabilidad de que la pieza siga viva a la edad $t$. Todo lo demás se deriva de aquí.

## I.2 La función de riesgo (hazard): el objeto central

Definimos la **tasa de riesgo instantánea**

$$h(t) = \lim_{\Delta t \to 0} \frac{P(t < T \leq t+\Delta t \mid T > t)}{\Delta t}.$$

En palabras: dado que la pieza llegó viva a $t$, ¿con qué tasa está fallando *ahora mismo*? Es la cantidad físicamente significativa, porque codifica el **envejecimiento**. Desarrollando la probabilidad condicional,

$$h(t) = \frac{f(t)}{R(t)}.$$

Hay una identidad fundamental. Como $f = -R'$,

$$h(t) = -\frac{R'(t)}{R(t)} = -\frac{d}{dt}\ln R(t).$$

Integrando desde 0, y usando $R(0)=1$, definimos el **riesgo acumulado** $H(t)$:

$$H(t) \equiv \int_0^t h(u)\,du = -\ln R(t) \quad\Longrightarrow\quad \boxed{R(t) = e^{-H(t)} = \exp\!\left(-\int_0^t h(u)\,du\right).}$$

Esta es la ecuación maestra de la confiabilidad. **Especificar el riesgo $h(t)$ equivale a especificar todo el modelo.** Diseñar un modelo de vida = postular una forma física para $h(t)$.

### La curva de bañera

La forma empírica típica de $h(t)$ tiene tres regímenes, cada uno con una física distinta:

- **Mortalidad infantil** ($h$ decreciente): defectos de fabricación/montaje; las piezas malas mueren temprano.
- **Vida útil** ($h \approx$ constante): fallas por choques aleatorios (impactos, eventos externos), independientes de la edad.
- **Desgaste** ($h$ creciente): acumulación de daño físico (abrasión, fatiga). Es el régimen que el mantenimiento predictivo busca anticipar.

## I.3 Momentos: vida media

El tiempo medio a la falla (MTTF) admite una forma elegante. Integrando por partes con $f=-R'$,

$$\mathrm{MTTF} = \mathbb{E}[T] = \int_0^\infty t\,f(t)\,dt = \big[-tR(t)\big]_0^\infty + \int_0^\infty R(t)\,dt = \int_0^\infty R(t)\,dt,$$

asumiendo $tR(t)\to 0$ (cierto si $\mathbb{E}[T]<\infty$). Es decir, **el área bajo la curva de confiabilidad es la vida media.** Geométricamente transparente.

## I.4 Vida residual media (la base del pronóstico RUL)

Lo que el negocio quiere no es la vida total, sino **cuánto le queda** a una pieza que *ya tiene* edad $t$. Definimos la vida útil remanente esperada:

$$\mathrm{RUL}(t) \equiv \mathbb{E}[T - t \mid T > t].$$

Por el mismo argumento de integración por partes, condicionado a $T>t$:

$$\boxed{\mathrm{RUL}(t) = \frac{\displaystyle\int_t^\infty R(u)\,du}{R(t)}.}$$

Nótese: la RUL **no** es $\mathrm{MTTF} - t$ en general. Una pieza vieja que sobrevivió puede tener más o menos vida esperada que una nueva, según el signo de $h'(t)$. Para riesgo constante (sin envejecimiento), $\mathrm{RUL}(t)=\mathrm{MTTF}$ siempre (memoria nula). Para riesgo creciente (desgaste), $\mathrm{RUL}(t)$ decrece con la edad. Este es el contenido físico del pronóstico.

---

# Parte II — Distribuciones de vida desde primeros principios

Cada distribución de vida corresponde a una hipótesis física sobre $h(t)$ o sobre el mecanismo de falla. No son elecciones arbitrarias.

## II.1 Exponencial: ausencia de memoria y el proceso de Poisson

**Hipótesis física:** la falla ocurre por choques externos que llegan como un proceso de Poisson de tasa $\lambda$ (sin acumulación de daño). El número de choques en $[0,t]$ es Poisson de media $\lambda t$; la pieza sobrevive si no hubo ningún choque:

$$R(t) = P(\text{0 choques en } [0,t]) = e^{-\lambda t}.$$

De aquí $h(t) = \lambda$ (constante) y $f(t)=\lambda e^{-\lambda t}$. La **propiedad de ausencia de memoria** se deriva directamente:

$$P(T > t+s \mid T > s) = \frac{R(t+s)}{R(s)} = \frac{e^{-\lambda(t+s)}}{e^{-\lambda s}} = e^{-\lambda t} = P(T>t).$$

La pieza "no recuerda" su edad. Esto la hace el modelo correcto **solo** para fallas aleatorias puras (electrónica sin desgaste, eventos externos), y el modelo *incorrecto* para desgaste mecánico. Su valor aquí es como caso base y como bloque de construcción (la suma de exponenciales da la Gamma).

## II.2 Weibull: el caballo de batalla, y por qué aparece en todas partes

### II.2.1 Como riesgo de potencia

La generalización mínima de "riesgo constante" es "riesgo de ley de potencia":

$$h(t) = \frac{\beta}{\eta}\left(\frac{t}{\eta}\right)^{\beta-1}.$$

Integrando, $H(t) = (t/\eta)^\beta$, de donde

$$\boxed{R(t) = \exp\!\left[-\left(\frac{t}{\eta}\right)^{\beta}\right], \qquad f(t) = \frac{\beta}{\eta}\left(\frac{t}{\eta}\right)^{\beta-1}\exp\!\left[-\left(\frac{t}{\eta}\right)^{\beta}\right].}$$

El **parámetro de forma** $\beta$ selecciona el régimen de la bañera:

- $\beta < 1$: $h$ decreciente → mortalidad infantil.
- $\beta = 1$: $h$ constante → exponencial (caso límite).
- $\beta > 1$: $h$ creciente → desgaste. Mecánica típica: $\beta \in [1.5, 4]$.

$\eta$ es la **vida característica**: $R(\eta) = e^{-1} \approx 0.368$, es decir el 63.2 % ha fallado en $t=\eta$.

### II.2.2 Por qué Weibull es *inevitable*: valores extremos y el eslabón más débil

Este es el argumento que un físico debe ver, porque explica por qué Weibull (y no otra) domina en materiales, fatiga y rodamientos.

Un componente real es un conjunto de $N$ "eslabones" (granos, volúmenes elementales, asperezas). Falla cuando **el más débil** falla:

$$T = \min(X_1, X_2, \dots, X_N),$$

con $X_i$ i.i.d. de confiabilidad $R_X$. Por independencia,

$$R_T(t) = P(\min_i X_i > t) = \prod_{i=1}^N P(X_i > t) = [R_X(t)]^N.$$

Supongamos que cerca del origen la cola izquierda de cada eslabón es una ley de potencia, $F_X(t) \approx (t/t_0)^\beta$ para $t\to 0^+$ (hipótesis natural: la probabilidad de un defecto crítico de "tamaño $t$" escala como potencia). Entonces

$$R_T(t) = [1 - (t/t_0)^\beta]^N \xrightarrow{N\gg 1} \exp\!\left[-N\,(t/t_0)^\beta\right] = \exp\!\left[-(t/\eta)^\beta\right], \qquad \eta = t_0\,N^{-1/\beta}.$$

Recuperamos **Weibull exactamente**, como ley límite de mínimos. Este es un caso del teorema de Fisher–Tippett–Gnedenko [A9, A10]: las distribuciones de mínimos de variables acotadas por abajo convergen a la familia Weibull. Consecuencias físicas:

- **Efecto de tamaño:** $\eta \propto N^{-1/\beta}$. Piezas más grandes (más eslabones) son *más débiles*. Esto se mide en materiales y es la razón de que la resistencia tenga dispersión Weibull (Weibull lo descubrió justamente con resistencia de materiales [A1]).
- **Estabilidad bajo mínimo:** el mínimo de Weibulls es Weibull. La familia es cerrada bajo la operación física relevante (falla del más débil).

Esto justifica usar Weibull como *prior* estructural para desgaste y fatiga, no por conveniencia sino por la física del eslabón más débil.

### II.2.3 Momentos de Weibull

Con la sustitución $w=(t/\eta)^\beta$,

$$\mathbb{E}[T] = \int_0^\infty R\,dt = \eta\,\Gamma\!\left(1+\tfrac{1}{\beta}\right), \qquad \mathrm{Var}[T] = \eta^2\left[\Gamma\!\left(1+\tfrac{2}{\beta}\right) - \Gamma^2\!\left(1+\tfrac{1}{\beta}\right)\right].$$

La **vida $B_q$** (edad a la que ha fallado una fracción $q$) se despeja de $R(B_q)=1-q$:

$$B_q = \eta\,[-\ln(1-q)]^{1/\beta}.$$

En rodamientos se usa $B_{10}$ (vida $L_{10}$, falla del 10 %): $B_{10}=\eta(-\ln 0.9)^{1/\beta}\approx \eta(0.1054)^{1/\beta}$.

### II.2.4 RUL condicional de Weibull (forma cerrada)

Aplicando I.4 con $R(u)=\exp[-(u/\eta)^\beta]$ y sustituyendo $w=(u/\eta)^\beta$, $w_t=(t/\eta)^\beta$:

$$\int_t^\infty R(u)\,du = \frac{\eta}{\beta}\int_{w_t}^\infty w^{\frac1\beta - 1} e^{-w}\,dw = \frac{\eta}{\beta}\,\Gamma\!\left(\tfrac1\beta, w_t\right),$$

donde $\Gamma(a,x)=\int_x^\infty w^{a-1}e^{-w}dw$ es la **gamma incompleta superior**. Usando la recurrencia $\Gamma(a+1,x)=a\Gamma(a,x)+x^a e^{-x}$ con $a=1/\beta$ se obtiene la forma compacta de la vida media condicional:

$$\boxed{\mathbb{E}[T \mid T>t] = \eta\, e^{(t/\eta)^\beta}\,\Gamma\!\left(1+\tfrac1\beta,\; (t/\eta)^\beta\right), \qquad \mathrm{RUL}(t) = \mathbb{E}[T\mid T>t] - t.}$$

Esto es lo que el motor de pronóstico evalúa *en línea* conforme la pieza envejece. Para $\beta>1$, $\mathrm{RUL}(t)$ es estrictamente decreciente: la pieza "consume" vida esperada al envejecer, lo opuesto al caso exponencial. La intervención se programa con un *buffer* conservador (se actúa cuando $R$ cae a un nivel objetivo, no cuando $\mathrm{RUL}\to 0$).

## II.3 Lognormal: degradación multiplicativa

**Hipótesis física:** el daño crece por incrementos *proporcionales* al daño actual (p. ej. crecimiento de grieta donde la tasa depende del tamaño actual). Si $D_{k+1}=D_k(1+\varepsilon_k)$, entonces $\ln D_n = \ln D_0 + \sum_k \ln(1+\varepsilon_k)$, y por el teorema central del límite $\ln D_n$ es asintóticamente normal. La pieza falla cuando $D$ cruza un umbral, lo que da un tiempo de falla **lognormal**:

$$f(t) = \frac{1}{t\,\sigma\sqrt{2\pi}}\exp\!\left[-\frac{(\ln t - \mu)^2}{2\sigma^2}\right].$$

Es el modelo natural para fatiga y procesos donde el daño se compone multiplicativamente. Útil como alternativa a Weibull; se discriminan con datos (gráficos de probabilidad, AIC).

## II.4 Gamma: acumulación de choques de desgaste

Si el desgaste avanza por incrementos positivos independientes (cada "evento" añade material removido), la suma de incrementos exponenciales i.i.d. es **Gamma**. Esto conecta con los **procesos Gamma** de la Parte IV, el modelo correcto para desgaste *monótono* (no se "des-desgasta").

---

# Parte III — Inferencia con datos censurados

## III.1 El problema central de una flota: casi nadie ha fallado

En una flota viva, la mayoría de las piezas **aún no han fallado** al momento de observar. Solo sabemos que su vida $T_i > t_i$ (su edad actual). Esto es **censura por la derecha**, y es la regla, no la excepción. Ignorarla (p. ej. promediar solo las piezas que fallaron) sesga groseramente la estimación hacia vidas cortas.

## III.2 La verosimilitud con censura

Sea $\delta_i=1$ si la pieza $i$ falló (observamos $t_i$ exacto) y $\delta_i=0$ si está censurada (solo sabemos $T_i>t_i$). Una falla aporta $f(t_i)$; una censura aporta $R(t_i)$. La verosimilitud es

$$\boxed{\mathcal{L}(\theta) = \prod_{i=1}^n f(t_i;\theta)^{\delta_i}\,R(t_i;\theta)^{1-\delta_i} = \prod_{i=1}^n h(t_i;\theta)^{\delta_i}\,R(t_i;\theta),}$$

usando $f=hR$. La forma de la derecha es iluminadora: **cada observación aporta su supervivencia $R(t_i)$, y las que fallaron aportan además el riesgo $h(t_i)$ en el instante de falla.** El log-verosimilitud es

$$\ell(\theta) = \sum_i \big[\delta_i \ln h(t_i;\theta) - H(t_i;\theta)\big].$$

## III.3 MLE de Weibull

Con $h(t)=\frac{\beta}{\eta}(t/\eta)^{\beta-1}$ y $H(t)=(t/\eta)^\beta$, sea $d=\sum_i \delta_i$ el número de fallas. El log-verosimilitud es

$$\ell(\beta,\eta) = d\ln\beta - d\beta\ln\eta + (\beta-1)\sum_i\delta_i\ln t_i - \sum_i (t_i/\eta)^\beta.$$

Las ecuaciones de score $\partial\ell/\partial\eta=0$, $\partial\ell/\partial\beta=0$ dan, tras eliminar $\eta$,

$$\hat\eta = \left(\frac{1}{d}\sum_i t_i^{\hat\beta}\right)^{1/\hat\beta}, \qquad \frac{\sum_i t_i^{\hat\beta}\ln t_i}{\sum_i t_i^{\hat\beta}} - \frac{1}{\hat\beta} = \frac{1}{d}\sum_i\delta_i\ln t_i,$$

la segunda resuelta numéricamente para $\hat\beta$ (es monótona, converge rápido por Newton). La **matriz de información de Fisher** $\mathcal{I}(\theta)=-\mathbb{E}[\partial^2\ell/\partial\theta^2]$ da los errores estándar asintóticos: $\hat\theta \approx \mathcal{N}(\theta, \mathcal{I}^{-1})$, base de los intervalos de confianza sobre $\eta$, $\beta$ y, por el método delta, sobre $\mathrm{RUL}(t)$.

## III.4 Riesgos proporcionales (Cox): meter la telemetría como covariables

Queremos que la vida dependa de condiciones medidas (carga, severidad de ruta, marca, conductor, daño de fatiga acumulado). El modelo de **riesgos proporcionales de Cox** [A3] postula

$$h(t \mid \mathbf{x}) = h_0(t)\,\exp(\boldsymbol{\beta}^\top \mathbf{x}),$$

donde $h_0(t)$ es un riesgo base (no especificado) y $\mathbf{x}$ el vector de covariables. La hipótesis física: las covariables **escalan multiplicativamente** el riesgo (una ruta de montaña multiplica por $e^{\beta_k}$ el riesgo de balata, a cualquier edad).

### La verosimilitud parcial (el truco elegante)

Lo notable de Cox es que se puede estimar $\boldsymbol{\beta}$ **sin conocer $h_0(t)$**. Ordenando los tiempos de falla $t_{(1)}<t_{(2)}<\dots$, en cada falla preguntamos: *de las piezas en riesgo en $t_{(j)}$ (el conjunto $\mathcal{R}_j$), ¿cuál es la probabilidad de que falle precisamente la que falló?* Esa probabilidad es

$$P(\text{falla } i \mid \text{una falla en } t_{(j)}) = \frac{h_0(t_{(j)})e^{\boldsymbol\beta^\top\mathbf{x}_i}}{\sum_{k\in\mathcal{R}_j} h_0(t_{(j)})e^{\boldsymbol\beta^\top\mathbf{x}_k}} = \frac{e^{\boldsymbol\beta^\top\mathbf{x}_i}}{\sum_{k\in\mathcal{R}_j}e^{\boldsymbol\beta^\top\mathbf{x}_k}}.$$

El riesgo base $h_0(t_{(j)})$ **se cancela**. La verosimilitud parcial es el producto de estas fracciones sobre las fallas, y se maximiza en $\boldsymbol\beta$ por Newton-Raphson. Esto permite cuantificar el efecto de cada covariable sobre la vida con mínimas suposiciones. (Si además se quiere $h_0$, se estima después con Breslow.)

### Modelos AFT como alternativa

Si la covariable no escala el riesgo sino el *tiempo* (acelera el reloj de envejecimiento), el modelo correcto es de **vida acelerada (AFT)**: $\ln T = \boldsymbol\gamma^\top\mathbf{x} + \sigma W$. Con $W$ Gumbel se recupera un Weibull con $\eta$ dependiente de $\mathbf{x}$. Físicamente: la covariable cambia $\eta$ (la escala de vida), que es exactamente lo que hace la severidad de operación sobre el desgaste.

---

# Parte IV — Procesos de degradación: la falla como primer cruce

Cuando podemos *medir* una variable de salud que degrada (espesor de balata, capacidad de batería, $\Delta P$ del DPF), no necesitamos esperar a la falla: modelamos la **trayectoria** $X(t)$ y la falla es el cruce de un umbral $a$. Esto es prognosis a nivel de individuo, más informativa que la estadística poblacional.

## IV.1 Proceso de Wiener (degradación con ruido)

Modelo: $X(t) = x_0 + \mu t + \sigma B(t)$, con $B(t)$ movimiento browniano estándar. Es el modelo natural para degradación **lineal en media con fluctuaciones gaussianas** (deriva $\mu$ = tasa de degradación; $\sigma$ = ruido). Incrementos independientes y gaussianos; markoviano.

### Tiempo de primer cruce → Gaussiana Inversa

La falla ocurre al primer cruce del umbral $a$: $T_a=\inf\{t: X(t)=a\}$ (con $x_0<a$, $\mu>0$). Por el principio de reflexión del browniano con deriva, la densidad del primer paso es

$$\boxed{f_{T_a}(t) = \frac{(a-x_0)}{\sigma\sqrt{2\pi t^3}}\exp\!\left[-\frac{(a-x_0-\mu t)^2}{2\sigma^2 t}\right],}$$

que es la distribución **Gaussiana Inversa** $\mathrm{IG}\!\big(\tfrac{a-x_0}{\mu},\,\tfrac{(a-x_0)^2}{\sigma^2}\big)$, con media $(a-x_0)/\mu$ (tiempo determinista de cruce) y varianza creciente con $\sigma$. Por tanto, **la RUL de una pieza con degradación tipo Wiener tiene distribución Gaussiana Inversa**, condicionada al estado actual $X(t_{\text{now}})$: se reinicia el problema con $x_0\to X(t_{\text{now}})$ y se recalcula. Esto da no solo la RUL media sino su distribución completa (intervalos de confianza del pronóstico), que es lo que se necesita para decidir con riesgo cuantificado.

## IV.2 Proceso Gamma (desgaste monótono)

Para desgaste estrictamente creciente (no puede revertirse), el browniano es inadecuado (sus incrementos pueden ser negativos). El modelo correcto es el **proceso Gamma** [B12]: incrementos independientes $X(t+\Delta)-X(t)\sim \mathrm{Gamma}(\alpha\Delta,\;\lambda)$, no negativos, con media $\alpha\Delta/\lambda$. La probabilidad de no haber cruzado el umbral $a$ hasta $t$ es

$$R(t) = P(X(t) < a) = \frac{\gamma(\alpha t,\; \lambda a)}{\Gamma(\alpha t)} \quad\text{(gamma incompleta \textbf{inferior} regularizada; }= 1-\text{la superior)},$$

de donde se obtiene la distribución de RUL. Es el modelo de referencia para abrasión y corrosión.

## IV.3 Conexión con física de falla

La potencia de esta parte es que $\mu$, $\alpha$, $a$ **no son parámetros de ajuste libres**: provienen de la física de la Parte V. Por ejemplo, en frenos la deriva $\mu$ del espesor de balata es la tasa de desgaste de Archard, función de la energía de frenado medida. Acoplar PoF (que fija la deriva) con el proceso estocástico (que cuantifica el ruido y da la distribución de RUL) es el enfoque **híbrido** state-of-the-art.

---

# Parte V — Física de falla desde primeros principios

Aquí "abrimos la caja negra" de la deriva de degradación. Cada componente tiene un mecanismo con su derivación.

## V.1 Desgaste por deslizamiento: derivación de la ley de Archard

Es el mecanismo de frenos, embrague y, parcialmente, neumáticos. La derivamos desde el contacto de asperezas [C16].

**Paso 1 — Área real de contacto.** Dos superficies se tocan solo en las cimas de sus rugosidades. Bajo carga $W$, estas asperezas se deforman plásticamente hasta que la presión de contacto iguala la **dureza** $H$ del material (la dureza es, operativamente, la presión de flujo plástico). El área *real* de contacto es entonces

$$A_r = \frac{W}{H},$$

independiente del área aparente. (Resultado de Bowden–Tabor; explica por qué la fricción es $\propto W$ y no $\propto$ área aparente.)

**Paso 2 — Geometría de una junta.** Modelamos cada contacto como circular de radio $a$, área $\pi a^2$. El número de juntas simultáneas es $n = A_r/(\pi a^2)$.

**Paso 3 — Producción de partícula.** Al deslizar, una junta se forma y se rompe en una distancia $\sim 2a$. Con probabilidad $\kappa$, la ruptura arranca una partícula hemisférica de volumen $\tfrac{2}{3}\pi a^3$ (criterio de Rabinowicz [C18]). El volumen desgastado por junta y por unidad de deslizamiento es

$$\frac{\tfrac{2}{3}\pi a^3 \cdot \kappa}{2a} = \frac{\kappa\pi a^2}{3}.$$

**Paso 4 — Ensamblar.** La tasa de volumen desgastado por unidad de distancia deslizada es

$$\frac{dV}{dL} = n\cdot\frac{\kappa\pi a^2}{3} = \frac{A_r}{\pi a^2}\cdot\frac{\kappa\pi a^2}{3} = \frac{\kappa\,A_r}{3} = \frac{\kappa}{3}\frac{W}{H}.$$

Definiendo el **coeficiente adimensional de desgaste** $K\equiv\kappa/3$, integramos:

$$\boxed{V = K\,\frac{W\,L}{H}.}$$

Esta es la **ley de Archard**. $K$ encapsula la probabilidad de arranque de partícula; varía de $10^{-2}$ (desgaste severo) a $10^{-7}$ (suave) y es la firma tribológica del par de materiales.

### Forma local y conexión con la deriva del proceso

Dividiendo por el área aparente y diferenciando en el tiempo, con presión de contacto $p$ y velocidad de deslizamiento $v=dL/dt$, la **profundidad** desgastada $h_w$ evoluciona como

$$\frac{dh_w}{dt} = K\,\frac{p\,v}{H} = k\, p\, v, \qquad k\equiv K/H \;\text{(tasa de desgaste específica)}.$$

Esta es exactamente la **deriva $\mu$** del proceso de Wiener de la Parte IV cuando la variable de salud es el espesor de balata. La energía de frenado por área es $\dot e = \mu_f\, p\, v$ (con $\mu_f$ coeficiente de fricción); por tanto $dh_w/dt \propto \dot e/\mu_f$: **el desgaste de balata es proporcional a la energía friccional disipada**, que medimos con IMU (desaceleración) + GPS (velocidad) + masa estimada. Integramos evento a evento:

$$\Delta h_w \;\propto\; \sum_{\text{frenadas}} \frac{E_{\text{frenada}}}{H} , \qquad E_{\text{frenada}} \approx \tfrac{1}{2}m\,(v_i^2 - v_f^2).$$

## V.2 Corrección termo-mecánica

A alta energía, $K=K(\theta)$ con $\theta$ la temperatura interfacial, generada por la potencia friccional $q''=\mu_f\,p\,v$ [C21]. El "fade" del freno y el cambio de régimen de desgaste se modelan haciendo $k$ función de $\theta$, que a su vez resuelve una ecuación de calor con fuente $q''$. Para el sistema operativo basta una corrección empírica $k(\theta)=k_0\,e^{\gamma\theta}$ (tipo Arrhenius), con $\theta$ estimada de la historia reciente de frenado.

## V.3 Fatiga: de Basquin–Coffin–Manson a Palmgren–Miner y rainflow

Es el mecanismo de chasis, suspensión y soportes, y el que **aprovecha directamente el IMU**.

### V.3.1 Curva esfuerzo–vida (Basquin)

Empíricamente, en escala log–log el número de ciclos a falla $N_f$ y la amplitud de esfuerzo $\sigma_a$ siguen una recta [D23]:

$$\sigma_a = \sigma_f'\,(2N_f)^b,$$

con $\sigma_f'$ coeficiente de resistencia a fatiga y $b\in[-0.12,-0.05]$ exponente de Basquin. Para deformación plástica (bajo ciclo) se añade Coffin–Manson [D26, D27]: $\varepsilon_p/2=\varepsilon_f'(2N_f)^c$. La curva combinada esfuerzo/deformación–vida da $N_f$ para cualquier amplitud.

### V.3.2 Daño acumulado lineal (Palmgren–Miner)

**Hipótesis física:** cada ciclo a amplitud $\sigma_i$ consume una fracción $1/N_i$ de la vida, independientemente del orden. El daño total es la suma [D24, D25]:

$$\boxed{D = \sum_i \frac{n_i}{N_i}, \qquad \text{falla cuando } D \geq 1.}$$

Es lineal y desprecia efectos de secuencia; el daño crítico real está experimentalmente en $D_c\in[0.7,2.2]$ (media $\approx 1$). Se usa $D_c=1$ por diseño, y la dispersión se absorbe en el modelo estadístico (Parte III) tratando $D$ como covariable, no como predictor determinista.

### V.3.3 Conteo rainflow: extraer ciclos de una señal aleatoria

El IMU entrega una señal continua $a(t)$, no "ciclos". El **conteo rainflow** [D28, D29] resuelve esto: descompone la historia de carga en **lazos de histéresis cerrados** en el plano esfuerzo–deformación; cada lazo cerrado es un ciclo con su amplitud. Es el puente entre una señal real y la regla de Miner. Una forma compacta del daño en términos de los rangos $h_i$ de los ciclos rainflow [D32] es

$$D_\beta = \alpha\sum_i h_i^{\,\beta}, \qquad \beta\approx 3 \text{ (crecimiento de grieta)},\; \beta\approx 5 \text{ (iniciación)},$$

con $\alpha^{-1}$ el número de ciclos de rango unitario a falla. **Pipeline de bajo costo:** $a(t)$ del MPU6050 $\to$ proxy de esfuerzo $\sigma(t)=c\,a(t)$ $\to$ rainflow $\to$ $D_\beta$ acumulado por componente. Cuando $D_\beta\to 1$, intervenir. La constante $c$ y $\alpha$ se calibran por componente con pocos casos (Parte VII).

## V.4 Vida de rodamientos: Lundberg–Palmgren *es* un Weibull de eslabón más débil

Cierra el círculo con la Parte II. Lundberg y Palmgren [E33] postularon que la falla por fatiga de contacto se inicia bajo la superficie, donde el esfuerzo cortante ortogonal $\tau_0$ es máximo, y que la probabilidad de supervivencia del volumen esforzado $V$ sigue una ley de Weibull en el número de ciclos $N$:

$$\ln\frac{1}{S} \;\propto\; \frac{\tau_0^{\,c}\,N^{\,e}\,V}{z_0^{\,h}},$$

con $z_0$ la profundidad del cortante máximo y $c,e,h$ exponentes. Esto es **exactamente** el argumento de eslabón más débil de II.2.2 aplicado al volumen subsuperficial: $S=\exp(-A\,\tau_0^c N^e V/z_0^h)$ es Weibull en $N$ con forma $e$. Traduciendo el esfuerzo de Hertz a carga $P$ y definiendo la **capacidad dinámica** $C$ como la carga que da $L_{10}=10^6$ revoluciones, se obtiene la ley carga–vida:

$$\boxed{L_{10} = \left(\frac{C}{P}\right)^{p}, \qquad p=3 \text{ (bolas)},\; p=\tfrac{10}{3} \text{ (rodillos)}.}$$

$C$ es dato del fabricante; $P$ se calcula de las cargas radial/axial. Para detección incipiente se usa además vibración (frecuencias de defecto BPFO/BPFI/BSF/FTF), que requiere un acelerómetro de mayor ancho de banda que el MPU6050 (mejora de fase posterior).

## V.5 Desgaste de neumáticos: energía de fricción y abrasión

El desgaste de banda se rige por la **energía friccional disipada en la huella de contacto** [F39, F40]. La tasa de pérdida de espesor de banda es

$$\dot w \;\propto\; \frac{E_{\text{fric}}}{A}\cdot \xi(\text{abrasividad}, T_{\text{tread}}),$$

donde $E_{\text{fric}}$ es la energía disipada por deslizamiento parcial (slip) en la huella y $\xi$ una función de la abrasividad del pavimento y la temperatura. El slip se relaciona con la fuerza longitudinal por la rigidez longitudinal $K_x$: en la zona sin deslizamiento, $F_x = K_x\,g$ (con $g$ tasa de slip), y la pendiente de la nube $(F_x,g)$ estima $K_x$ [F42]. La tasa empírica es del orden de $0.001$–$0.004$ mm/km según conducción y pavimento [F39]. La vida proyectada, tras un período de asentamiento, es

$$\text{Vida} = \frac{d_{\text{inicial}} - d_{\min}}{\langle\dot w\rangle},$$

con $d_{\min}$ la profundidad mínima legal. Los **patrones de desgaste irregular** (centro/bordes/un lado/cupping) son diagnósticos de presión, alineación, balanceo o suspensión: el módulo los usa como detector de fallas *de otros subsistemas*.

---

# Parte VI — Teoría de decisión: cuándo intervenir

Predecir no basta: hay que decidir óptimamente. Dos resultados clave.

## VI.1 Intervalo óptimo de reemplazo (teorema de renovación-recompensa)

Política de reemplazo por edad: se reemplaza la pieza al alcanzar la edad $T$ (preventivo, costo $c_p$) o cuando falla antes (correctivo, costo $c_f$, con $c_f>c_p$ porque incluye remolque, downtime, falla en ruta y riesgo). Cada ciclo termina en $\min(T_{\text{vida}}, T)$. Por el **teorema de renovación-recompensa**, la tasa de costo a largo plazo es

$$g(T) = \frac{\mathbb{E}[\text{costo por ciclo}]}{\mathbb{E}[\text{duración del ciclo}]}.$$

El costo esperado por ciclo es $c_p R(T) + c_f F(T)$ (preventivo si sobrevive a $T$, correctivo si no). La duración esperada del ciclo es $\mathbb{E}[\min(T_{\text{vida}},T)] = \int_0^T R(t)\,dt$. Por tanto

$$\boxed{g(T) = \frac{c_p R(T) + c_f F(T)}{\displaystyle\int_0^T R(t)\,dt} = \frac{c_p + (c_f-c_p)F(T)}{\displaystyle\int_0^T R(t)\,dt}.}$$

**Optimización.** Derivando $g'(T)=0$ (regla del cociente) y simplificando con $f=hR$ se llega a la condición de optimalidad:

$$\boxed{h(T^\*)\int_0^{T^\*} R(t)\,dt - F(T^\*) = \frac{c_p}{c_f - c_p}.}$$

Interpretación física: el lado izquierdo crece con $T$ **solo si el riesgo $h$ es creciente** (desgaste, $\beta>1$). Por tanto existe un óptimo finito $T^\*$ **si y solo si la pieza envejece**. Para fallas aleatorias ($\beta=1$, $h$ constante) no hay óptimo: el reemplazo preventivo no ayuda (no se puede "anticipar" lo aleatorio). Esto da una regla de diseño dura: **el mantenimiento preventivo por calendario solo tiene sentido para modos de falla por desgaste; los aleatorios requieren CBM/PdM o redundancia.** El cociente $c_p/(c_f-c_p)$ fija cuán agresivo es el óptimo: si la falla es muy cara ($c_f\gg c_p$), $T^\*$ se adelanta.

## VI.2 Umbral de alerta sensible al costo (decisión de Bayes)

Un modelo predictivo entrega $p=P(\text{fallará en el horizonte}\mid \mathbf{x})$. ¿Cuándo disparar la alerta? Minimizamos el **costo esperado**. Con costos: falso positivo (revisión innecesaria) $c_{FP}$; falso negativo (falla no anticipada) $c_{FN}$; y costo despreciable para los aciertos, alertamos si

$$p\,c_{FN} > (1-p)\,c_{FP} \quad\Longleftrightarrow\quad \boxed{p > p^\* = \frac{c_{FP}}{c_{FP}+c_{FN}}.}$$

El umbral **no es 0.5**: depende de la asimetría de costos. En el reto APS de Scania [G44], $c_{FN}=500$ y $c_{FP}=10$, de modo que $p^\* = 10/510 \approx 0.0196$: se alerta con apenas ~2 % de probabilidad de falla, porque dejarla pasar es 50 veces más caro. **La métrica de entrenamiento debe ser el costo monetario esperado, no la exactitud.** Con clases desbalanceadas (las fallas son raras), esto se complementa con re-muestreo (SMOTE/RUSBoost) y calibración de probabilidades (la calibración importa porque $p^\*$ es un umbral sobre $p$, no sobre un score arbitrario).

## VI.3 Cuánto se ahorra: economía del mantenimiento

Esta sección cierra el lazo "predecir → decidir → ahorrar". Conceptos fundamentales a entender primero:

- **Tasa de costo de largo plazo** $C$: dinero por unidad de tiempo (o km / hora-motor) en régimen estacionario. Es lo que se minimiza; renovación-recompensa la da como $\tfrac{\text{costo/ciclo}}{\text{duración/ciclo}}$.
- **MTTF** $=\int_0^\infty R\,dt = \eta\,\Gamma(1+1/\beta)$: vida media.
- **Razón de costos** $\rho = c_f/c_p \ge 1$: cuánto más cara es una falla que una intervención planeada. En flota $\rho\approx 4$–10 (grúa, downtime, daño secundario, falla en ruta).
- **IFR/DFR**: riesgo creciente/decreciente. Solo **IFR** ($\beta>1$) admite ahorro preventivo (VI.1).

**Tres políticas, tres tasas de costo.**
$$C_{\text{rtf}} = \frac{c_f}{\text{MTTF}}\ \text{(reactivo)}, \qquad C^\star = \min_T g(T)\ \text{(preventivo óptimo, VI.1)}, \qquad C_{\text{pred}}^{\min} = \frac{c_p}{\text{MTTF}}\ \text{(predicción perfecta)}.$$
El reactivo paga $c_f$ cada MTTF; el predictivo perfecto paga solo $c_p$ cada MTTF (reemplaza justo antes de fallar, sin desperdiciar vida ni pagar la falla). Jerarquía garantizada:
$$C_{\text{rtf}} \ge C^\star \ge C_{\text{cbm}} \ge C_{\text{pred}}^{\min}.$$

**Ahorro y su cota dura.** El ahorro preventivo es $s_{\text{prev}} = 1 - C^\star/C_{\text{rtf}}$. El **techo predictivo** es independiente de $\beta$:
$$\boxed{s_{\text{pred}}^{\max} = 1 - \frac{c_p/\text{MTTF}}{c_f/\text{MTTF}} = 1 - \frac{1}{\rho}.}$$
Consecuencia central: **ningún algoritmo supera $1-1/\rho$**; la palanca del ahorro es la razón de costos, no la sofisticación del modelo ($\rho{=}2\Rightarrow50\%$, $\rho{=}4\Rightarrow75\%$, $\rho{=}8\Rightarrow88\%$). Y por el teorema IFR (VI.1), si $\beta\le1$ entonces $C^\star=C_{\text{rtf}}$ y $s_{\text{prev}}=0$: **sin desgaste no hay ahorro preventivo, cualquiera sea $\rho$.** El ahorro exige $\beta>1$ **y** $\rho$ alto. Ejemplo (Weibull $\beta{=}2.3$, $\rho{=}8.4$): $s_{\text{prev}}\approx 48\%$, techo $\approx 88\%$. La brecha entre ambos es lo que captura el CBM/RUL condicional sobre un calendario óptimo.

**Régimen online (por qué se realiza rápido).** $g(T)$ es **plana cerca de su mínimo**, de modo que la política plug-in con $(\hat\beta,\hat\eta)$ estimados de **pocas** fallas es casi óptima (captura ~95 % del ahorro con ~5 fallas observadas; es robusta al error de estimación). El cuello de botella no es el número de fallas sino acumularlas en **calendario** (al inicio casi todo está censurado); el **prior físico** (Parte V) da un $\hat T^\star$ razonable desde el día 1 y el posterior se contrae conforme llegan datos (Parte VIII). El POMDP de VIII.5 generaliza esto al caso secuencial con incertidumbre.

La derivación completa, la tabla $(\beta,\rho)$, los ejemplos en MXN y la literatura (DOE/FEMP, EPRI) están en el documento *Estudio de Ahorro — Mantenimiento Predictivo vs Reactivo*.

---

# Parte VII — Marco unificado: supervivencia jerárquica informada por física

Aquí convergen las tres lentes. El requisito de negocio —"todas las clases, marcas y tipos de vehículo (camión pesado, auto, motocicleta), con pocos datos por marca"— tiene una solución matemática precisa.

## VII.1 El vector de covariables informado por física

Para cada componente, construimos $\mathbf{x}$ con **features derivadas de la Parte V**, no señales crudas:

- $E_{\text{freno}}$: energía de frenado acumulada (Archard, V.1).
- $D_\beta$: daño de fatiga rainflow–Miner (V.3).
- consumo de $L_{10}$: revoluciones equivalentes ponderadas por carga (V.4).
- severidad de ruta (pendiente, paradas/km vía GPS), carga media (J1939), comportamiento de conductor (IMU).

Esto reduce drásticamente la dimensionalidad y la cantidad de datos necesaria: la física ya hizo el trabajo pesado de compresión.

## VII.2 Modelo jerárquico bayesiano multi-clase (partial pooling anidado)

El alcance multi-clase (camión pesado + Tracker mini para autos y motos) **profundiza** la jerarquía en lugar de complicarla. Modelamos la vida del componente $c$ en una unidad indexada por **clase** $k$ (pesado/ligero/moto), **marca** $m$ y **modelo** $j$, con un Weibull cuya escala (AFT) depende de covariables y cuyos parámetros se comparten parcialmente en cada nivel:

$$
\begin{aligned}
T_{c,k,m,j,i} &\sim \mathrm{Weibull}(\beta_{c,k},\;\eta_{i}), \\
\ln \eta_{i} &= \alpha_{c,k} + \delta_{c,k,m} + \zeta_{c,k,m,j} + \boldsymbol\gamma_c^\top \mathbf{x}_{i}, \\
\alpha_{c,k} &\sim \mathcal{N}(\mu_c,\;\tau_{\text{clase}}^2), \\
\delta_{c,k,m} &\sim \mathcal{N}(0,\;\tau_{\text{marca}}^2), \\
\zeta_{c,k,m,j} &\sim \mathcal{N}(0,\;\tau_{\text{modelo}}^2), \qquad \mu_c,\beta_{c,k},\boldsymbol\gamma_c,\tau_{\bullet} \sim \text{(priors físicos)}.
\end{aligned}
$$

Es un modelo **anidado de tres niveles**: clase dentro de la flota global, marca dentro de clase, modelo dentro de marca. La intuición de encogimiento (Stein/James–Stein) ahora opera **en cascada**: una moto de un modelo con pocas fallas toma fuerza prestada de su modelo → marca → clase → media global $\mu_c$, en ese orden de cercanía. Cuanto más escaso es el dato local, más pesa el nivel superior. Las $\tau_\bullet$ —estimadas de los datos— deciden cuánta información fluye entre niveles: si las marcas de una clase se parecen ($\tau_{\text{marca}}$ pequeña), se agrupan fuerte; si difieren, el modelo lo detecta y desagrupa.

La razón de fondo de que esto funcione entre clases tan distintas como un tráiler y una moto es la **Parte V**: la física de falla (Archard, Miner, Weibull, Lundberg–Palmgren) es la misma; solo cambian los parámetros. Por eso las features físicas $\mathbf{x}$ transfieren entre clases aunque las marcas no se parezcan en nada. La física provee el prior estructural ($\beta_{c,k}\sim 2$ para fatiga, etc.), regularizando la inferencia HMC (`Turing.jl`).

### VII.2.1 Manejo nativo de modalidades faltantes

El Tracker mini tendrá menos sensores que el bridge de camión (una moto rara vez expone OBD; ver tabla de niveles de edge en el dossier, §7.5). Esto significa que el vector de covariables $\mathbf{x}_i$ está **incompleto** en algunas unidades. El marco bayesiano lo resuelve sin parches: si la componente $x_{i,\ell}$ falta, se trata como variable latente con su prior condicional de clase $p(x_{\ell}\mid k)$ y se **marginaliza**,

$$p(T_i \mid \mathbf{x}_{i,\text{obs}}) = \int p(T_i \mid \mathbf{x}_{i,\text{obs}}, x_{i,\text{mis}})\,p(x_{i,\text{mis}}\mid k)\,dx_{i,\text{mis}}.$$

El efecto es automático y deseable: una unidad con menos información tiene un **posterior predictivo más ancho** (el modelo "sabe que sabe menos") y se apoya más en el prior de clase. No hay que imputar a mano ni descartar unidades incompletas; la incertidumbre se propaga correctamente a la RUL y al umbral de decisión (Parte VI).

### VII.2.2 Modos de falla específicos de motocicleta

Tres mecanismos nuevos, todos encajables en el mismo marco (cada uno es una variable de salud que cruza un umbral, Parte IV):

- **Cadena y piñón (elongación).** El desgaste pin–buje bajo tensión es de tipo Archard (V.1): la elongación porcentual de la cadena crece con la distancia deslizada bajo carga. La variable de salud es el alargamiento $\Delta L/L$; el umbral de reemplazo es $\sim 1$–$3\%$. Deriva $\propto$ par transmitido $\times$ km, estimable de GPS + (si existe) par del motor.
- **Neumático trasero (desgaste acelerado).** En moto, la rueda motriz concentra la energía de tracción y el desgaste es mucho más rápido que en auto; el modelo de energía de fricción (V.5) aplica con un $\xi$ y una fracción de slip mayores. Se modela **por posición** (delantero vs trasero) como en el caso multi-posición de neumáticos de flota.
- **Dinámica de inclinación (lean) y caída.** El ángulo de inclinación en curva añade carga de fatiga y de neumático; entra como covariable derivada del IMU (integración de la orientación). La **detección de caída/impacto** es un evento de alta $g$ + cambio brusco de orientación: dispara alerta crítica y, vía AHD, captura de clip (dossier §7.4).

Para motos el IMU es el sensor **primario**, lo que hace que el pipeline rainflow → Miner (V.3) y la estimación de exposición a lean sean la columna vertebral del modelo de esa clase.

## VII.3 El flujo completo (la cadena de la física a la decisión)

$$
\underbrace{a(t),\,v(t),\,\text{J1939}}_{\text{sensor}}
\;\xrightarrow{\text{V}}\;
\underbrace{E_{\text{freno}},\,D_\beta,\,L_{10}}_{\text{features físicas}}
\;\xrightarrow{\text{III/VII}}\;
\underbrace{h(t\mid\mathbf{x}),\,R(t\mid\mathbf{x})}_{\text{supervivencia}}
\;\xrightarrow{\text{II.2.4}}\;
\underbrace{\mathrm{RUL}(t),\,p}_{\text{pronóstico}}
\;\xrightarrow{\text{VI}}\;
\underbrace{T^\*,\,\text{alerta}}_{\text{decisión}}
$$

Cada flecha es una de las partes de este documento. El sistema es esa cadena, instrumentada.

---

# Parte VIII — Estimación secuencial y aprendizaje online

En la vida real las unidades no fallan en un instante de calibración: cada ponchadura, cada reparación rápida, cada trama OBD/CAN llega en su propio tiempo y debe **actualizar las distribuciones** sin reajustar todo desde cero. Esto convierte el problema estático de las Partes III–IV en uno **secuencial**. Hay tres subproblemas acoplados y, sí, las tres intuiciones —ecuación maestra, Metrópolis, optimización dinámica— corresponden a piezas reales que conviven en capas a distinta cadencia.

## VIII.1 El filtro bayesiano recursivo es una ecuación maestra

Separemos dos objetos que suelen confundirse:

- **Estado** $x_t$: la salud latente de *una* unidad (espesor de balata, daño $D$, capacidad). Evoluciona (Parte IV).
- **Parámetros** $\theta$: las cantidades de flota (Weibull $\beta,\eta$; jerarquía $\tau_\bullet$; factor de reparación $q$). Cambian lento o nada.

Para el **estado**, con observaciones $y_t$, transición $p(x_t\mid x_{t-1})$ (la física de Parte IV) y modelo de observación $p(y_t\mid x_t)$, la creencia se actualiza con la recursión de **filtrado bayesiano**, en dos pasos:

$$\underbrace{p(x_t\mid y_{1:t-1}) = \int p(x_t\mid x_{t-1})\,p(x_{t-1}\mid y_{1:t-1})\,dx_{t-1}}_{\text{predicción (Chapman–Kolmogorov)}}$$

$$\underbrace{p(x_t\mid y_{1:t}) \propto p(y_t\mid x_t)\,p(x_t\mid y_{1:t-1})}_{\text{actualización (Bayes)}}$$

El paso de predicción es **propagar una densidad por la dinámica**. En tiempo continuo, para la degradación tipo Wiener $dX=\mu\,dt+\sigma\,dW$ (Parte IV), la densidad de creencia $p(x,t)$ obedece la **ecuación de Fokker–Planck (Kolmogorov hacia adelante)**:

$$\boxed{\frac{\partial p}{\partial t} = -\frac{\partial}{\partial x}\big[\mu\,p\big] + \frac12\frac{\partial^2}{\partial x^2}\big[\sigma^2 p\big].}$$

Esa es la "ecuación maestra" que intuías: el filtro **propaga la densidad con Fokker–Planck y la corrige con Bayes** en cada observación. La RUL es, como en IV, el primer cruce del umbral por la densidad ya filtrada.

## VIII.2 Filtrar el estado: de Kalman a partículas

Según linealidad y ruido:

- **Kalman (KF):** dinámica lineal + ruido gaussiano → filtro exacto y cerrado (media y covarianza). Para degradación lineal con ruido gaussiano basta.
- **EKF / UKF:** linealización (EKF) o transformación *unscented* (UKF) para dinámica no lineal moderada.
- **Filtro de partículas (SMC):** representa $p(x_t\mid y_{1:t})$ con un conjunto ponderado de muestras ("partículas") propagadas por la dinámica y repesadas por la verosimilitud, con remuestreo. Es **Monte Carlo de la ecuación maestra**: no asume linealidad ni gaussianidad, y es el caballo de batalla del pronóstico de RUL no lineal/no gaussiano [N84–N86].

Los parámetros *por unidad* que la física deja libres (p. ej. la tasa de desgaste $k$ de esa balata específica) se estiman **conjuntamente** con el estado aumentando el vector ($\tilde x=(x,k)$) y dejando que el filtro los aprenda al vuelo (estado aumentado / estadísticos suficientes / EM dentro del filtro).

## VIII.3 Aprender los parámetros de flota en streaming (Metrópolis y descendientes)

Los hiperparámetros jerárquicos (Parte VII) deben actualizarse al llegar datos, no recalcularse. Opciones, de exacta a escalable:

- **Bayes secuencial exacto (conjugado):** si el modelo es de familia exponencial con prior conjugado, el posterior se actualiza en forma cerrada acumulando **estadísticos suficientes**; el posterior de hoy es el prior de mañana, en $O(1)$ por evento. (Weibull no es conjugado completo, pero partes del modelo —conteos y tasas de eventos— sí lo son.)
- **SG-MCMC (la versión streaming de Metrópolis):** Metropolis–Hastings clásico exige recorrer *todo* el dato por paso. El **Stochastic Gradient Langevin Dynamics (SGLD)** [N87] lo evita simulando la SDE de Langevin
$$d\theta = \tfrac12\,\nabla\log\pi(\theta)\,dt + dW, \qquad \pi(\theta)=p(\theta\mid \text{datos}),$$
cuya **distribución estacionaria es el posterior** (de nuevo una ecuación maestra: el Fokker–Planck de esta SDE tiene $\pi$ como solución estacionaria). Discretizada con gradientes de minibatch:
$$\theta_{k+1} = \theta_k + \frac{\epsilon_k}{2}\Big(\nabla\log p(\theta_k) + \frac{N}{n}\!\!\sum_{i\in\text{batch}}\!\!\nabla\log p(y_i\mid\theta_k)\Big) + \mathcal{N}(0,\epsilon_k).$$
Es Metrópolis sin barrer todo el dato; **SGHMC** añade momento [N88].
- **Inferencia variacional en streaming (SVI / SVB):** aproxima el posterior por una familia tratable y la actualiza por minibatch [N89, N90]. Rápida y amortizable.
- **SMC samplers / particle MCMC:** mantienen partículas sobre $\theta$ actualizadas por lote [N91].

Para **no-estacionariedad** (la flota cambia: rutas, conductores, estaciones) se usa **factor de olvido / power prior** (descontar dato viejo) o se trata $\theta$ como estado lento con caminata aleatoria, filtrándolo como en VIII.2.

## VIII.4 Cada reparación es un evento: sistemas reparables

Una unidad genera un **proceso puntual** de eventos (fallas, reparaciones, ponchaduras). El objeto correcto es la **intensidad condicional** $\lambda(t\mid H_t)$, con verosimilitud de proceso puntual

$$L = \Big[\prod_i \lambda(t_i\mid H_{t_i})\Big]\exp\!\Big(-\!\int_0^T \lambda(t\mid H_t)\,dt\Big).$$

La pregunta clave es **cuánto restaura cada reparación**, y hay un espectro [N92, N93]:

- **Renovación (reparación perfecta, "as good as new"):** el reloj se reinicia; cada intervalo es i.i.d. (Parte II).
- **NHPP (reparación mínima, "as bad as old"):** la intensidad sigue la edad real; potencia-ley $\lambda(t)=(\beta/\eta)(t/\eta)^{\beta-1}$ (proceso de Crow–AMSAA).
- **Edad virtual de Kijima / Proceso de Renovación Generalizado (GRP):** el caso real intermedio. Tras la $i$-ésima reparación la **edad virtual** es $v_i = v_{i-1} + q\,x_i$ (Kijima I) o $v_i = q\,(v_{i-1}+x_i)$ (Kijima II), con $x_i$ el tiempo del último ciclo y $q$ el **factor de restauración**: $q=0$ perfecta, $q=1$ mínima, $0<q<1$ imperfecta, $q>1$ "peor que vieja" (reparación que daña). La intensidad se evalúa en la edad virtual.

Esto responde literal al ejemplo: una **ponchadura reparada rápido** y un **reemplazo de neumático** retrasan el reloj de forma distinta —distinto $q$— y $q$ es **estimable de los datos** (la calidad del taller se vuelve parámetro). Para meter covariables a los eventos recurrentes se usa la extensión de **Andersen–Gill** del modelo de Cox (Parte III) sobre el proceso de conteo [N94].

## VIII.5 No recalcular: inferencia amortizada (statistical learning)

Aquí se formaliza "llevarlo a statistical learning para no estar calculando todo el tiempo". La **inferencia amortizada** entrena **una vez, offline**, una red $q_\psi(\theta\mid x)$ que aprende el mapa datos→posterior, con pares $(\theta, x)$ **simulados** del modelo físico (Parte V) + prior jerárquico (Parte VII). En despliegue, inferir el posterior de una unidad nueva es **un forward pass**, no una corrida de MCMC. Es la **inferencia basada en simulación (SBI) / Neural Posterior Estimation** [N95, N96]. Encaja perfecto aquí porque el simulador *ya lo tenemos*: la física de falla genera datos sintéticos etiquetados ilimitados. El mismo truco (surrogate neuronal de la verosimilitud) acelera el filtro de partículas de VIII.2.

## VIII.6 Cerrar el lazo: decisión bajo creencia que evoluciona

La creencia filtrada alimenta la decisión. El problema de **cuándo intervenir bajo observación parcial** es un **POMDP** (proceso de decisión de Markov parcialmente observable): el estado de salud es latente, se observa con ruido, y se elige acción (esperar / inspeccionar / reparar) para minimizar el costo esperado descontado. Se resuelve por programación dinámica, parada óptima, o **deep RL** con el posterior de parámetros incorporado por *domain randomization* para robustez al error de modelo [N97, N98]. Generaliza el intervalo óptimo de Parte VI al caso secuencial con incertidumbre.

## VIII.7 Arquitectura de capas y cadencia (la respuesta a "¿todo lo anterior?")

Sí: las tres intuiciones conviven, pero **a distintas escalas de tiempo**. Ninguna capa recalcula todo.

| Capa | Qué estima | Método | Cadencia | Dónde |
|---|---|---|---|---|
| Filtrado de estado | salud de cada unidad (RUL al vuelo) | KF/UKF/partículas (VIII.2) | por evento / continuo | borde + servidor |
| Eventos recurrentes | intensidad; factor de reparación $q$ | GRP/NHPP, Andersen–Gill (VIII.4) | por reparación | servidor |
| Hiperparámetros de flota | $\beta,\eta,\tau_\bullet,\boldsymbol\gamma$ | HMC por lotes / SG-MCMC (VIII.3) | nocturno/semanal | servidor |
| Inferencia de despliegue | posterior de unidad nueva | red amortizada / SBI (VIII.5) | instantáneo | servidor/borde |
| Política de intervención | acción óptima | POMDP / RL (VIII.6) | por decisión | servidor |

El filtrado es $O(1)$ por paso, los hiperparámetros se refrescan por lotes en segundo plano, y la red amortizada convierte la inferencia en un forward pass. Esa separación es lo que hace al sistema escalable a flota grande en streaming.

---

# Parte IX — Gaps y oportunidades de publicación

> Prioridad: implementar primero. Esta sección documenta dónde, *si en paralelo aparece algo interesante*, habría contribución publicable. La evidencia de la literatura sugiere que sí hay huecos defendibles.

## VIII.1 Gaps reconocidos en la literatura

- La literatura reconoce explícitamente un **hueco entre la confiabilidad a nivel flota (bases históricas) y el pronóstico a nivel de individuo (trayectorias de degradación)**; los enfoques que integran ambos siguen siendo escasos [G49].
- Las revisiones recientes [G52, G48] señalan como limitaciones persistentes la **escasez de datos**, el **costo de etiquetado** y la **falta de benchmarks estándar**, especialmente fuera de aeroespacial/turbomaquinaria.
- El PoF informado por ML existe sobre todo en activos caros y bien instrumentados (turbinas, motores aeronáuticos) [G47, G50]; hay poco sobre **flota terrestre heterogénea con sensores de bajo costo**.

## VIII.2 Nichos defendibles para este proyecto

1. **PoF con sensores de consumo masivo como instrumento científico.** Validar que un bridge de ~110 USD (IMU MPU6050 + GPS + interfaz J1939) produce features físicas (energía de frenado, daño rainflow–Miner) con poder predictivo *comparable* a instrumentación dedicada. Contribución de sistemas + validación experimental. La estimación online de daño por fatiga en vehículos ya existe [D32]; la novedad sería el **acoplamiento con supervivencia jerárquica multimarca y la validación contra desgaste físico medido**.

2. **Supervivencia jerárquica bayesiana informada por física para flota multimarca** (VII.2). Combinar partial pooling entre marcas + covariables PoF + censura aborda simultáneamente los dos gaps citados (flota-vs-individuo y datos escasos). Es la contribución metodológica más fuerte. Venue: *Reliability Engineering & System Safety*, *Mechanical Systems and Signal Processing*, o *PHM Society*.

3. **Cuantificación de complejidad muestral.** Pregunta limpia y medible: ¿cuánto reduce el feature físico la cantidad de datos etiquetados necesaria para generalizar a una marca nueva, frente a un modelo puramente data-driven? Diseño experimental claro (curvas de aprendizaje, ablación de features físicas). Responde a un gap explícito.

4. **Contribución de dataset.** Los datasets públicos (Scania APS, Component X) son de **un solo componente y anonimizados** [G44, G45]. Un dataset real, multimarca, con J1939 + IMU + GPS + registros de mantenimiento **sincronizados** de flota mexicana sería un recurso único. Los datasets son explícitamente el recurso escaso del campo; publicarlos (anonimizados) en *Scientific Data* es de alto impacto y bajo riesgo competitivo.

## VIII.3 Caveat metodológico

Para que cualquiera de estos sea publicable se necesita **ground truth**: piezas con desgaste medido (espesor de balata, profundidad de banda) y fechas de falla bien registradas. Eso lo produce la Fase 1 (captura) del roadmap como subproducto. Es decir: implementar bien genera, sin costo adicional, el activo que habilita la publicación. No hay conflicto entre las dos metas; la segunda es un dividendo de la primera.

---

## Apéndice: tabla de símbolos

| Símbolo | Significado | Parte |
|---|---|---|
| $T$ | tiempo (o km, horas) a la falla | I |
| $R(t),F(t),f(t)$ | confiabilidad, CDF, densidad | I |
| $h(t),H(t)$ | riesgo y riesgo acumulado | I |
| $\mathrm{RUL}(t)$ | vida residual esperada | I.4 |
| $\beta,\eta$ | forma y escala de Weibull | II.2 |
| $\delta_i$ | indicador de falla (vs censura) | III |
| $\boldsymbol\beta,\mathbf{x}$ | coeficientes y covariables de Cox | III.4 |
| $\mu,\sigma,a$ | deriva, ruido, umbral del proceso de degradación | IV |
| $K,k,H,p,v$ | coef. de Archard, tasa específica, dureza, presión, velocidad | V.1 |
| $\sigma_a,N_f,b$ | amplitud, ciclos a falla, exponente de Basquin | V.3 |
| $D,D_\beta$ | daño acumulado de Miner | V.3 |
| $C,P,L_{10},p$ | capacidad, carga, vida B10, exponente carga-vida | V.4 |
| $c_p,c_f,c_{FP},c_{FN}$ | costos preventivo, correctivo, falsos pos./neg. | VI |
| $\alpha_{c,k},\delta_{c,k,m},\zeta_{c,k,m,j}$ | efectos de clase, marca, modelo (jerarquía anidada) | VII.2 |
| $\mu_c,\tau_{\text{clase}},\tau_{\text{marca}},\tau_{\text{modelo}}$ | media de flota y dispersiones entre niveles | VII.2 |
| $x_t,y_t,\theta$ | estado latente, observación, parámetros de flota | VIII.1 |
| $\lambda(t\mid H_t),\,q,\,v_i$ | intensidad condicional, factor de restauración, edad virtual | VIII.4 |
| $q_\psi(\theta\mid x)$ | red de inferencia amortizada (SBI) | VIII.5 |

## Apéndice B — Métodos geométricos, espectrales y topológicos: alcance y límites

El negocio preguntó si conviene incorporar TDA (homología persistente, ciclos, Mapper), PCA global/local, "valores espectrales locales" y similares. Respuesta de postdoc crítico: la mayoría son herramientas de **análisis exploratorio (EDA) y verificación de supuestos**, no predictores de producción aquí; **uno** (Koopman/DMD) es un candidato genuino para la dinámica de degradación; y el caso mejor evidenciado de TDA está **bloqueado por hardware**. Detalle con la matemática y el veredicto.

### B.1 PCA global y local (lo barato y seguro)

PCA global: con covarianza $\Sigma$, los eigenvectores son las direcciones principales y los eigenvalores $\lambda_i$ la varianza en cada una. Asume que el dato vive cerca de un **único subespacio lineal**. Los datos de régimen de operación (cargas, velocidades, rutas, modos de manejo) viven en un manifold curvo y probablemente disconexo; un subespacio lineal único mezcla regímenes y distorsiona la geometría. Por eso PCA global es geométricamente pobre para esta clase de dato. **Pero no se descarta: se demota.** Sigue siendo el baseline más barato, un denoiser excelente, y —decisivo para un sistema auditable— **interpretable**: una componente principal es una combinación lineal de features con nombre físico. Los métodos geométricos compran riqueza a costa de interpretabilidad (sus coordenadas no tienen significado físico directo) y de hiperparámetros ($\varepsilon$, $\alpha$). **Veredicto: córrelo primero, como baseline interpretable y chequeo de dimensión efectiva** ($\sum_{i\le d}\lambda_i/\sum_i\lambda_i$, que verifica el supuesto de baja dimensión de VII.1); invoca geometría solo donde PCA global falle visiblemente (varianza residual alta, curvatura).

PCA local / dimensión intrínseca: en una vecindad, los eigenvalores locales estiman la **dimensión intrínseca** y la anisotropía del manifold ("valores espectrales locales y calidad de aproximación"). Aquí una corrección importante: **PCA local por sí solo es un primitivo, no un método terminado.** Es sensible al tamaño de vecindad; sufre hambre de muestras locales en dimensión ambiente alta; y deja un *parche de marcos locales sin sistema de coordenadas global* que hay que coser — y coserlos es exactamente lo que hacen los algoritmos de manifold learning (LTSA, Laplacian eigenmaps, diffusion maps). Es decir: **"PCA local geométrico" y "métodos espectrales de grafo" (B.2) son la misma pista**, no dos. La realización rigurosa de la intuición geométrica es diffusion maps, no una colección de PCAs locales sueltos.

**Advertencia transversal a todo el apéndice (supervisado vs no supervisado):** PCA, diffusion maps y Koopman son **no supervisados** — describen la estructura del dato, no su relación con la falla. La pregunta "qué es lo más importante en mantenimiento" es **supervisada** ("importante para predecir/evitar la falla") y la responden la dependencia del hazard en las covariables (coeficientes de Cox / hazard ratios, Parte III), la física de falla (qué mecanismo domina por componente, Parte V), el FMECA/RPN y el peso por costo (VI.2). Estos métodos geométricos sirven para entender regímenes, subpoblaciones y dinámica; **no** para contestar importancia por sí solos.

### B.2 Métodos espectrales de grafo (estructura, nodos, subpoblaciones)

Sobre un grafo de similitud con pesos $W$ y grado $D$, el **Laplaciano** $L=D-W$ tiene un espectro que codifica estructura: el número de eigenvalores nulos cuenta componentes conexas, y el **gap espectral** mide separación de clusters. Sus eigenvectores de baja frecuencia dan un embedding no lineal (**Laplacian eigenmaps**, **diffusion maps** de Coifman–Lafon, ligados al kernel de calor y al operador de difusión —terreno familiar para un físico). **Spectral clustering** sale de ahí. **Veredicto: más principiado que Mapper/TDA para la pregunta de "nodos importantes / subpoblaciones / estructura"; uso con propósito = descubrir/validar qué marcas o modelos se comportan parecido, lo que informa directamente el pooling jerárquico de VII.2.**

### B.3 Koopman / Dynamic Mode Decomposition (el candidato espectral real)

El **operador de Koopman** $\mathcal{K}$ actúa sobre observables $g$ por $(\mathcal{K}g)(x)=g(F(x))$, donde $F$ es el flujo: **lifta una dinámica no lineal a una lineal (infinito-dimensional) en el espacio de observables** (Koopman 1931). DMD y su extensión EDMD lo aproximan con datos, descomponiendo la dinámica en **modos** con eigenvalores $\lambda$ (frecuencia + crecimiento/decaimiento). Para degradación, los **modos lentos** (con $|\lambda|$ cerca del borde de estabilidad) son la firma del envejecimiento; del espectro sale un indicador de salud con buena tendencia y monotonicidad. Funciona en series de baja dimensión y ruidosas, y sirve además de **surrogate** lineal rápido. **Veredicto: candidato genuino, alineado con el marco de espacio de estados (Partes IV/VIII); más defendible que TDA porque es un método de dinámica, no de forma estática.** Riesgo: la elección del diccionario de observables (EDMD) no es trivial; el *Deep Koopman* lo aprende pero añade complejidad y datos.

### B.4 Análisis topológico de datos (TDA / homología persistente)

Construcción: de una nube de puntos (p. ej. embedding de Takens de una serie temporal), se filtra por escala y se rastrea cuándo nacen y mueren componentes ($H_0$), lazos ($H_1$) y huecos ($H_2$): el **diagrama de persistencia**. Captura **forma global y recurrencia no lineal** que los resúmenes locales pueden perder.

Evidencia en PHM: real, pero **concentrada en vibración** (rodamientos CWRU, NASA bearing, engranes de turbina eólica) vía Takens → homología persistente → indicadores de Betti/persistencia/entropía, que cambian *antes* de la falla. Consistentemente descrito como **complementario** al análisis espectral, rara vez dominante.

Límites duros (no retóricos):

1. **Cómputo:** la homología persistente escala muy mal (peor caso $\sim 2^{3n}$); miles de puntos en 3D ya son prohibitivos. Requiere subsampleo/aproximaciones.
2. **Estadística:** la salida es un diagrama (multiconjunto de intervalos), **no un vector**; no admite estadística/ML clásica directa. Hay que vectorizar (persistence landscapes, images, Betti curves) o usar kernels, sobre un espacio que no es Hilbert/Banach agradable.
3. **Sensibilidad:** depende crucialmente de la métrica, la filtración y el preprocesamiento.

**Veredicto crítico para ESTE proyecto:**
- El uso mejor evidenciado (vibración) está **bloqueado por hardware**: el MPU6050 es de baja frecuencia; sin un acelerómetro de varios kHz cerca de mazas/transmisión no hay señal de vibración de rodamiento que analizar (mismo gating de §V.4). Es mejora de hardware futura.
- Sus otros usos (detección de régimen/anomalía en telemetría, descubrimiento de subpoblaciones) compiten con baselines más baratos y mejor entendidos (FFT/wavelet, isolation forest/autoencoder, PCA/diffusion-maps + clustering), y su ganancia marginal **no está establecida** para este tipo de dato.
- **Decisión (descartado del plan activo).** Por las dos razones anteriores, TDA **sale** del plan. No es que sea inútil —captura forma global y recurrencia no lineal real— sino que su mejor caso está bloqueado por hardware y sus otros usos no superan baselines más baratos para este dato. Se **revisita solo si** aparece hardware de vibración (acelerómetro de varios kHz cerca de mazas/transmisión); ahí compite de verdad, junto a Koopman/espectral, y aun así contra un baseline espectral pre-registrado.

### B.5 La unificación por operadores (geometría, dinámica y clusters son el mismo operador)

Las tres pistas que quedan —PCA/geometría, métodos de grafo, Koopman— no son herramientas inconexas: son **caras del mismo operador de difusión/transferencia**, y se conectan directo con la ecuación maestra de la Parte VIII. Esto no es decoración; dicta cómo construirlas de forma coherente (mismo kernel, mismo grafo, distinta normalización).

**Diffusion maps con parámetro $\alpha$ (Coifman–Lafon; Nadler–Lafon–Coifman–Kevrekidis).** El Laplaciano de grafo construido de los datos, en el límite de muestreo denso, converge a un operador
$$\mathcal{L}_\alpha\,\phi \;=\; \tfrac12\Delta\phi \;+\; (1-\alpha)\,\nabla\log\rho\cdot\nabla\phi,$$
donde $\rho$ es la densidad de muestreo. Los tres casos canónicos:
- $\alpha=1$ → **Laplace–Beltrami** ($\tfrac12\Delta$): geometría riemanniana pura, el término de densidad desaparece. Es la realización rigurosa de tu **"PCA geométrico"**: recupera la geometría intrínseca *independiente de cómo se muestreó* el dato.
- $\alpha=\tfrac12$ → **Fokker–Planck/Kolmogorov backward** con el potencial $U$ del sistema ($\rho\propto e^{-U}$): es **literalmente el generador de la ecuación maestra de la Parte VIII** (la misma SDE de Langevin de VIII.3, el mismo Fokker–Planck que propaga la creencia en el filtro de VIII.2).
- $\alpha=0$ → **Laplaciano de grafo** clásico: clustering espectral (mezcla geometría y densidad).

**Koopman y Perron–Frobenius: los dos lifts de la dinámica.** El operador de Koopman $\mathcal{K}_t$ actúa sobre observables por composición, $(\mathcal{K}_t\varphi)(x)=\varphi(s_t(x))$, con generador $\mathcal{K}\varphi = f\cdot\nabla\varphi$ (determinista) o el operador de Kolmogorov backward (estocástico). Su **adjunto** es el operador de Perron–Frobenius (transferencia), que propaga densidades hacia adelante; su generador estocástico es el **Fokker–Planck**. Es decir: Kolmogorov backward (Koopman) y Fokker–Planck (Perron–Frobenius) son **adjuntos** — los mismos operadores que ya aparecen en VIII.2–VIII.3. Y el clustering espectral está espectralmente ligado: los eigenvalores mayores del Koopman corresponden a los menores del Laplaciano de caminata aleatoria.

**Síntesis.** El mismo operador, muestreado a distinta normalización y actuando sobre observables vs densidades, da:

| Ángulo | Operador | Normalización / lado | Para qué |
|---|---|---|---|
| Geometría estática | Laplace–Beltrami | diffusion maps $\alpha=1$ | manifold de regímenes (tu "PCA geométrico") |
| Clusters | Laplaciano de grafo | diffusion maps $\alpha=0$ | subpoblaciones → validar jerarquía VII.2 |
| Dinámica | Koopman / Perron–Frobenius | observables / densidades | degradación, HI, surrogate |
| Belief / inferencia | Fokker–Planck (= $\alpha=\tfrac12$) | generador de VIII | el filtro y el SG-MCMC ya construidos |

La consecuencia práctica: construir **un solo grafo de similitud** sobre los estados y leerlo de tres formas (geometría, clusters, dinámica) es más barato y más coherente que tratar PCA, clustering y Koopman como tres pipelines separados.

### B.6 Tabla veredicto

| Método | Qué da | Costo | Veredicto aquí | Cuándo |
|---|---|---|---|---|
| PCA global | varianza, denoising, dim. efectiva | trivial | **Sí** | ya (EDA) |
| PCA local / dim. intrínseca | geometría local, calidad de aprox. | bajo | **Sí** (diagnóstico) | ya |
| Laplaciano / diffusion maps | estructura, clusters, nodos | medio | Útil para validar jerarquía | EDA / fase media |
| Koopman / DMD | modos de dinámica, HI, surrogate | medio | **Candidato real** (degradación) | fase media, evaluar |
| TDA / homología persistente | forma global, recurrencia | alto | **Descartado del plan activo** | revisitar solo con hardware de vibración |

### B.7 El punto de fondo

Ninguno de estos resuelve el cuello de botella real, que no es de método sino de **datos e identificabilidad**: etiquetas de reparación, fallas observadas, calibración de probabilidades, y validar empíricamente que las features físicas transfieren entre marcas (la "misma física" comparte la **forma funcional**, no las **constantes** $K,k,\alpha$, que se estiman por componente y marca). El *method-shopping* antes de tener datos es decorar antes de cimentar. Estos métodos entran como **microscopio sobre los supuestos del modelo**, no como sustituto de la disciplina de datos.

---

*Documento de fundamentos. Cada caja recuadrada es una ecuación que el sistema implementa. Las derivaciones priorizan transparencia física sobre rigor measure-theoretic; donde se omiten tecnicismos (existencia de momentos, regularidad), son los estándar.*
