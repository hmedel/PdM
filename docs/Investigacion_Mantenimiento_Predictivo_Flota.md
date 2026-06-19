# Investigación: Módulo de Mantenimiento Predictivo para Flota Vehicular

**Dossier técnico-científico para integración en plataforma de tracking (MDVR + telemetría)**
Versión 1.0 — Junio 2026

---

## 0. Propósito y alcance

Este documento es la fase de investigación previa a la implementación de un módulo de mantenimiento dentro de la plataforma existente (Traccar + PostgreSQL + bridge sobre Orange Pi Zero 3 + Headscale). El objetivo es que el módulo no sea un simple calendario de "cambio de aceite cada 15,000 km", sino un sistema **basado en física de falla, estadística de confiabilidad y aprendizaje automático**, capaz de generalizar a múltiples marcas y tipos de camión.

El criterio rector es el de la disciplina formal conocida como **PHM (Prognostics and Health Management)** y **CBM (Condition-Based Maintenance)**: medir el estado real, modelar cómo se degrada cada componente, y decidir la intervención en el momento óptimo, no en uno fijo.

Se cubren seis capas, de abajo hacia arriba:

1. Marco normativo y de gestión (qué define "bien hecho")
2. Adquisición de datos (la materia prima — y una brecha crítica de hardware)
3. Física de falla por componente (el núcleo científico)
4. Estadística de confiabilidad (vida, riesgo, RUL)
5. Modelado predictivo / ML de vanguardia
6. Optimización de decisiones e integración en la plataforma

---

## 1. Marco conceptual y normativo

### 1.1 Taxonomía de estrategias de mantenimiento

| Estrategia | Disparador | Costo típico | Riesgo |
|---|---|---|---|
| Reactivo (run-to-failure) | La pieza falla | Reparación cara + downtime + falla en ruta | Alto |
| Preventivo (PM) | Tiempo / km / horas fijos | Servicio innecesario o tardío | Medio |
| Basado en condición (CBM) | Indicador medido cruza umbral | Sensores + análisis | Bajo |
| Predictivo (PdM) | Modelo proyecta falla futura | Datos + modelos | Bajo, requiere madurez |
| Prescriptivo | Modelo recomienda acción óptima | Optimización + datos | El más avanzado |

El paso de preventivo a predictivo es un cambio de paradigma: en lugar de un calendario rígido, se usa telemetría y diagnóstico en tiempo real para servir el vehículo exactamente cuando se necesita, convirtiendo el mantenimiento de centro de costo a ventaja operativa. La meta de vanguardia es llegar al nivel **prescriptivo** (qué hacer, cuándo, con qué refacción y en qué taller).

### 1.2 Estándares que dan rigor profesional

Estos son los marcos que distinguen un sistema "amateur" de uno auditable y state-of-the-art:

- **ISO 55000 / 55001 / 55002** — Gestión de activos. Define principios, requisitos del sistema de gestión y guía de aplicación. Es el paraguas estratégico.
- **SAE JA1011 / JA1012** — Criterios de evaluación de procesos RCM (Reliability-Centered Maintenance). Origen en aviación comercial; es el estándar que define qué cuenta como RCM legítimo.
- **IEC 60300-3-11** — Gestión de confiabilidad, aplicación de RCM.
- **MIL-STD-1629A** — Procedimiento para FMECA (análisis de modos, efectos y criticidad de falla).
- **ISO 13374** — Procesamiento de datos de monitoreo de condición (arquitectura de capas: adquisición → manipulación → detección de estado → diagnóstico → pronóstico → aviso). Es prácticamente el plano de arquitectura de un sistema PHM.
- **ISO 17359** — Lineamientos generales de monitoreo de condición.
- **SAE J1939** (familia) — Protocolo de comunicación de vehículos pesados (ver §2).

**RCM** es la metodología que conecta todo: identifica funciones del activo, modos de falla, consecuencias, y asigna a cada modo de falla la estrategia óptima (reactiva/preventiva/predictiva). Estudios de caso reportan reducciones de 20–30 % en costo de mantenimiento y ~30 % en downtime no planeado cuando se aplica bien (cifras de proveedores/casos, a validar con datos propios).

### 1.3 Contexto regulatorio mexicano (Monterrey / autotransporte federal)

Para flota de autotransporte federal en México, el módulo debería **codificar como checklist digital** las condiciones físico-mecánicas exigidas por la normativa de la SICT (antes SCT) y las verificaciones de la NOM correspondiente a condiciones físico-mecánicas del autotransporte federal, además de las revisiones de la unidad. Recomendación: tratar estos puntos de inspección como "modos de falla con consecuencia regulatoria" dentro del FMECA, y verificar la versión vigente de cada NOM aplicable antes de implementar (la numeración y vigencia cambian).

---

## 2. Adquisición de datos: la materia prima

Ningún modelo supera la calidad de sus datos. Esta es la capa fundacional.

### 2.1 Estado del hardware de adquisición (actualizado)

**El nuevo edge ya incluye interfaz CAN y entradas para cámaras AHD.** La brecha de protocolo que existía con el bridge basado solo en ELM327 está cerrada. Quedan dos matices de diseño que conviene conservar:

- **Doble protocolo sobre el mismo CAN.** El transceptor físico es el mismo, pero hay que distinguir a nivel de aplicación:
  - **OBD-II** (ISO 15765 / CAN, vehículos ligeros < 14,000 lb / ~6,350 kg GVWR, conector 16 pines): códigos con prefijo P/C/B/U y diccionario de **PID**.
  - **SAE J1939** (medianos y pesados diésel Clase 4–8, CAN a 250 kbps, conector **Deutsch de 9 pines**): fallas como pares **SPN + FMI**, mensajes DM1/DM2.

  El firmware debe llevar **ambos decodificadores y autodetectar** qué protocolo/conector está presente (relevante porque la misma plataforma servirá camión pesado, vehículo ligero y eventualmente Tracker mini; ver §7.5).

- **Cámaras AHD como sensor dirigido por evento.** El cómputo del Orange Pi Zero 3 (Mali-G31, sin NPU) no permite visión pesada en el borde, y el video domina el presupuesto de datos (~4.5 GB/mes). Por tanto el video se trata como **evidencia disparada por evento** (un pico de IMU o un DTC dispara la captura de un clip), no como flujo continuo. Sus tres usos para mantenimiento, ordenados por relación valor/esfuerzo, están en §7.4.

### 2.2 Anatomía de J1939 (lo que hay que parsear)

- **PGN (Parameter Group Number):** agrupa mensajes (p. ej. datos del motor).
- **SPN (Suspect Parameter Number):** identifica el parámetro/señal específica. Ej.: SPN 110 = temperatura de refrigerante; SPN 5246 = sistema de NOx/derate del aftertreatment.
- **FMI (Failure Mode Identifier):** describe *cómo* falló (32 modos estándar: "voltaje sobre lo normal", "fuera de rango alto", "falla mecánica", etc.).
- **DM1:** mensaje de DTC activos (los que más importan para alertas en tiempo real).
- **DM2:** DTC previamente activos (historial).
- **PPID/PSID:** códigos propietarios (Volvo y Mack en particular añaden los suyos). Hay que mantener un diccionario por OEM.

Plataformas comerciales (Samsara, Geotab, PeopleNet/Omnitracs) hacen exactamente esto: extraen el flujo J1939 del bus CAN y lo traducen a texto legible y workflows. Replicar y superar eso en el edge propio es el diferenciador.

### 2.3 Señales útiles y su rol predictivo

| Fuente | Señal | Uso en mantenimiento |
|---|---|---|
| J1939 / OBD-II | DTC (SPN+FMI / P-codes), códigos pendientes | Alerta temprana; señales pre-falla |
| J1939 | Horas-motor, RPM, carga %, consumo, idle | Vida por uso real (no solo odómetro) |
| J1939 | Temp. refrigerante, presión aceite, boost, ΔP del DPF, nivel DEF | Degradación de motor/aftertreatment |
| OBD-II | Velocidad, temp. motor, posición acelerador | Severidad de ciclo de servicio |
| IMU (MPU6050) | Aceleración 3 ejes, giro | Eventos bruscos, **carga de fatiga**, comportamiento de conductor |
| GPS (dashcam) | Posición, km, ruta, pendiente | Severidad de ruta, km por componente |
| Inspecciones | DVIR / checklist conductor | Indicadores adelantados (vibración reportada 3 inspecciones seguidas = deterioro) |

Punto clave de diseño: medir **vida por componente en horas/km reales de operación**, no por lectura de odómetro del vehículo. Una pastilla de freno instalada hace 40,000 km en ruta de montaña no es comparable con una de carretera plana.

### 2.4 Presupuesto de datos (cabe holgadamente)

La telemetría continua de mantenimiento es barata: del orden de **~60 MB/mes** según el propio análisis de consumo del bridge (GPS cada 15 s, OBD/J1939 cada 10 s, heartbeat). El presupuesto del sistema es ~5 GB/mes (dominado por video bajo demanda). Conclusión: se puede muestrear diagnóstico con generosidad sin afectar el plan de datos LTE.

---

## 3. Física de falla por componente (Physics-of-Failure)

Esta es la parte que el negocio pidió explícitamente: "física y matemáticas reales de cómo se desgastan las piezas". El enfoque **Physics-of-Failure (PoF)** modela el mecanismo de degradación (desgaste, fatiga, corrosión, fluencia térmica) en vez de solo correlacionar datos. Su ventaja: generaliza a marcas/modelos sin necesidad de millones de datos por cada uno, porque la física es la misma.

### 3.1 Frenos (pastillas/balatas y discos/tambores) — desgaste abrasivo

El mecanismo dominante es desgaste por deslizamiento, descrito por la **ley de Archard**:

$$V = K \cdot \frac{F_N \cdot L}{H}$$

donde $V$ = volumen desgastado, $F_N$ = fuerza normal (presión de frenado), $L$ = distancia de deslizamiento, $H$ = dureza del material, $K$ = coeficiente adimensional de desgaste. En forma local y diferencial (para integrar evento por evento):

$$\frac{dh}{dt} = k \cdot p(t) \cdot v(t)$$

con $h$ = profundidad desgastada, $k$ = tasa de desgaste específica, $p$ = presión de contacto, $v$ = velocidad de deslizamiento. La literatura corrige el modelo clásico de Archard incluyendo **temperatura interfacial** $\theta(t)$, porque el calor friccional cambia $k$ (los materiales de fricción no tienen una relación Archard simple con la dureza medida; $K$ depende de la química y de la capa de fricción formada).

**Cómo instrumentarlo con su hardware:** cada frenada genera energía friccional $\propto m \cdot v \cdot \Delta v$. Con IMU (desaceleración) + GPS (velocidad, masa estimada/carga) + eventos de freno se puede acumular un **proxy de energía de frenado** por unidad, mucho mejor predictor que "km recorridos". El umbral de reemplazo es físico (espesor mínimo de balata).

### 3.2 Neumáticos — desgaste por energía de fricción

El desgaste de banda de rodamiento se predice teóricamente a partir de la **energía de fricción en el contacto**, la abrasividad de la superficie, las características fuerza-deslizamiento ($F_x$ vs slip) del neumático y las propiedades del compuesto. Modelo operativo:

$$\dot{w} = f(E_{fric}, \text{abrasividad}, T_{tread})$$

donde la tasa de pérdida de banda varía típicamente entre **0.001 y 0.004 mm/km** según patrón de manejo y condiciones. La vida proyectada se estima por extrapolación tras un período de asentamiento (break-in), usando la profundidad mínima legal (1.6 mm en muchas jurisdicciones; verificar la mexicana) como umbral:

$$\text{Vida proyectada} = \frac{d_{inicial} - d_{min}}{\dot{w}_{medido}}$$

Hallazgo importante para flota: un modelo **jerárquico por posición de rueda** (dirección, tracción, arrastre) y por eje permite predecir el desgaste de un neumático nuevo con solo 1–2 mediciones de profundidad, una vez que la flota ha sido observada algunos meses. Además, 12+ patrones de desgaste irregular (centro = sobreinflado, bordes = subinflado, un lado = alineación, "cupping" = suspensión) son diagnósticos de **otras** fallas (suspensión, alineación, balanceo), no solo del neumático. El IMU y la presión (TPMS si se añade) alimentan esto.

### 3.3 Rodamientos y transmisión — fatiga de contacto

La vida de fatiga de rodamientos se rige por el modelo **Lundberg–Palmgren (vida L10)**:

$$L_{10} = \left(\frac{C}{P}\right)^{p}$$

en millones de revoluciones, donde $C$ = capacidad de carga dinámica (dato del fabricante), $P$ = carga dinámica equivalente, $p = 3$ para rodamientos de bolas y $p = 10/3$ para rodillos. $L_{10}$ es la vida a la que sobrevive el 90 % de la población (es decir, B10 — directamente conectado con Weibull, §4).

Para detección temprana de falla incipiente de rodamiento, el estado del arte usa **análisis de vibración** (FFT, energía en bandas de frecuencia de defecto: BPFO/BPFI/BSF/FTF). El MPU6050 actual es de baja frecuencia; para esto se necesitaría un **acelerómetro de mayor ancho de banda** (≥ varios kHz) montado cerca de mazas/transmisión. Es una mejora futura, no de fase 1.

### 3.4 Fatiga estructural (chasis, suspensión, soportes) — daño acumulado

Aquí el IMU que ya tienen es directamente aprovechable. La acumulación de daño por carga variable se modela con la **regla de Palmgren–Miner**:

$$D = \sum_i \frac{n_i}{N_i}, \qquad \text{falla cuando } D \geq 1$$

donde $n_i$ = ciclos aplicados a amplitud $i$, y $N_i$ = ciclos a falla a esa amplitud, obtenidos de la curva **S–N (Basquin)**:

$$\sigma_a = \sigma'_f \,(2N_f)^{b}$$

Para convertir la señal continua del IMU en ciclos de amplitud se usa **conteo rainflow** (rainflow counting). Esto permite estimar consumo de vida a fatiga de componentes estructurales a partir de baches, vibración y maniobras bruscas que ya registra el MPU6050. Es un diferenciador real: pocos competidores cierran el lazo IMU → daño por fatiga.

### 3.5 Motor y aceite — degradación química/condición

El aceite se degrada por oxidación, dilución por combustible, hollín y caída de viscosidad. El análisis de aceite (espectrometría de metales de desgaste: Fe, Cu, Al, Cr) es el "análisis de sangre" del motor. Aunque el laboratorio es externo, el módulo debe **registrar y tendenciar** resultados. En tiempo real, J1939 entrega proxies: presión de aceite, temperatura, horas, consumo de combustible (dilución), y patrones de ΔP del DPF. Una caída sostenida de presión de aceite a RPM/temperatura comparables es señal de alerta.

### 3.6 Aftertreatment (DPF/DEF/SCR) — el dolor moderno del diésel

Es de las fallas más caras y frecuentes: un sensor de NOx que deriva (p. ej. SPN 5246 / FMI 4) puede forzar un **derate** y dejar la unidad varada. El módulo debe priorizar: ΔP del DPF (saturación/regeneración), nivel y calidad de DEF, conteo de regeneraciones forzadas, y códigos pendientes de NOx **antes** de que escalen a falla activa.

### 3.7 Batería / sistema de arranque, embrague, sistema de aire (frenos)

- **Batería:** voltaje en arranque, caída bajo carga; degradación modelable con procesos estocásticos (§4.4).
- **Sistema de aire (APS):** genera la presión para frenos y cambios; es el subsistema del famoso reto público de Scania (§5.3).
- **Embrague:** desgaste por energía de patinamiento (análogo a Archard/energía).

### 3.8 Resumen: cada componente tiene una vida modelable

| Componente | Mecanismo | Modelo físico | Señales clave |
|---|---|---|---|
| Balatas/discos | Desgaste abrasivo + térmico | Archard (corregido por T) | Energía de frenado (IMU+GPS+J1939) |
| Neumáticos | Abrasión por energía de fricción | Energía-slip | km, slip, presión, alineación (IMU) |
| Rodamientos | Fatiga de contacto | Lundberg–Palmgren (L10) | Vibración, carga, RPM |
| Chasis/suspensión | Fatiga | Miner + S–N + rainflow | IMU (baches, maniobras) |
| Aceite/motor | Degradación química | Oxidación/dilución | Presión, temp, horas, hollín |
| DPF/SCR | Saturación/deriva sensor | Balance de masa, deriva | ΔP, NOx, DEF, regeneraciones |
| Batería | Degradación electroquímica | Proceso de Wiener/Gamma | Voltaje arranque, caída bajo carga |

---

## 4. Marco estadístico de confiabilidad

La física dice *cómo* se degrada; la estadística cuantifica *cuándo* falla, con incertidumbre.

### 4.1 La distribución de vida y la curva de bañera

La vida de un componente es una variable aleatoria. Funciones fundamentales:

- **Confiabilidad** $R(t) = P(T > t)$
- **Función de riesgo (hazard)** $h(t) = f(t)/R(t)$ — tasa instantánea de falla dado que sobrevivió hasta $t$.

La **curva de bañera** describe la mayoría de los componentes: mortalidad infantil (riesgo decreciente), vida útil (riesgo ~constante), desgaste (riesgo creciente).

### 4.2 Distribución de Weibull (el caballo de batalla)

Es la distribución más usada en confiabilidad porque su parámetro de forma captura los tres regímenes:

$$R(t) = \exp\!\left[-\left(\frac{t}{\eta}\right)^{\beta}\right], \qquad h(t) = \frac{\beta}{\eta}\left(\frac{t}{\eta}\right)^{\beta-1}$$

- $\beta < 1$: mortalidad infantil (riesgo decreciente)
- $\beta = 1$: fallas aleatorias (equivale a exponencial)
- $\beta > 1$: desgaste (riesgo creciente) — el caso típico de piezas mecánicas

$\eta$ es la **vida característica** (~63.2 % ha fallado). La **vida $B_q$** (p. ej. $B_{10}$, donde falla el 10 %) es:

$$B_q = \eta\,[-\ln(1-q)]^{1/\beta}$$

Weibull es especialmente valioso porque permite estimar vida útil **con datos limitados y censurados** (piezas que aún no fallan), situación normal en una flota.

### 4.3 Vida útil remanente (RUL) condicional — el objetivo del pronóstico

Lo que el negocio quiere predecir es la **RUL**: cuánto le queda a la pieza *dado que ya sobrevivió* hasta su edad actual $t$. La forma general es la **vida media residual**:

$$\text{MRL}(t) = \frac{\int_t^{\infty} R(u)\,du}{R(t)}$$

Para Weibull, la vida media condicional de unidades que alcanzan la edad $t$ admite forma cerrada con la función gamma incompleta:

$$E(T\mid t) = \eta\,\Gamma\!\left(1+\tfrac{1}{\beta}\right)\,e^{(t/\eta)^{\beta}}\left\{1-\gamma\!\left(1+\tfrac{1}{\beta};\,(t/\eta)^{\beta}\right)\right\}, \qquad \text{RUL} = E(T\mid t) - t$$

La RUL se calcula "al vuelo" conforme envejece la pieza, y se usa de forma **conservadora**: se programa la intervención antes de que la confiabilidad caiga significativamente, aplicando un *buffer* temporal a la fecha de falla predicha.

### 4.4 Modelos de degradación estocástica

Cuando se mide una variable de salud que degrada de forma monótona o con ruido (espesor de balata, capacidad de batería, ΔP del DPF):

- **Proceso de Wiener:** $X(t) = x_0 + \mu t + \sigma B(t)$. La RUL es el **tiempo de primer cruce (first hitting time)** del umbral de falla, con distribución gaussiana inversa. Versiones de vanguardia usan procesos de Wiener **no lineales y bifásicos** (con punto de cambio detectado por criterios de información SIC/AIC).
- **Proceso Gamma:** para desgaste estrictamente monótono (no puede "des-desgastarse").

### 4.5 Regresión de supervivencia con covariables (Cox)

Para incorporar telemetría como factores de riesgo:

$$h(t \mid \mathbf{x}) = h_0(t)\,\exp(\boldsymbol{\beta}^{\top}\mathbf{x})$$

donde $\mathbf{x}$ son covariables (carga promedio, severidad de ruta, eventos bruscos, marca, modelo, conductor). Esto responde directamente al requisito de "todo tipo de camiones y marcas": la marca/modelo entra como covariable, y un modelo **jerárquico bayesiano** (partial pooling) permite que marcas con pocos datos "tomen prestada fuerza" de la flota completa. Ese es el truco para ser robusto desde el día 1 sin millones de registros por marca.

---

## 5. Modelado predictivo y ML de vanguardia

### 5.1 Las cuatro tareas de PHM

1. **Clasificación:** ¿hay/habrá falla de un subsistema? (binaria, con horizonte, p. ej. 10 días)
2. **Regresión de RUL:** ¿cuántos días/km le quedan?
3. **Análisis de supervivencia:** modela datos **censurados** (la mayoría de las piezas no han fallado todavía) — más correcto que regresión ingenua.
4. **Detección de anomalías:** sin etiquetas, detecta desviación del comportamiento normal.

### 5.2 Familias de modelos (de simple a sofisticado)

| Modelo | Cuándo usarlo | Notas |
|---|---|---|
| Reglas + umbrales OEM | Fase 1, quick win | Interpretable, sin entrenamiento |
| Weibull / Cox | Vida por componente | Base estadística, pocos datos |
| Random Forest / Gradient Boosting (XGBoost) | Tabular (conteos de DTC, histogramas) | Fuerte baseline; ganó el reto APS |
| LSTM / Multi-head LSTM | Series de tiempo multivariadas | SOTA en RUL; ver §5.3 |
| Redes de supervivencia (SurvLoss, DeepSurv) | Datos censurados + RUL | Manejo correcto de censura |
| Graph Neural Networks | Relaciones entre señales/ECUs | Investigación reciente |
| + SHAP (explicabilidad) | Confianza del mecánico | Por qué el modelo alerta |

### 5.3 Datasets públicos de referencia (para prototipar y hacer benchmark)

- **APS Failure at Scania Trucks** (UCI, reto IDA 2016): clasificación binaria de fallas del sistema de aire. 60,000 muestras (altamente desbalanceadas: ~1,000 positivas), 16,000 de prueba. Introduce una **matriz de costo asimétrica** (un falso negativo cuesta mucho más que un falso positivo) — exactamente la lógica del negocio: dejar pasar una falla es más caro que una revisión de más.
- **SCANIA Component X** (2024): dataset multivariado de series de tiempo de un componente de motor a lo largo de una flota, con registros de reparación. Apto para clasificación, regresión RUL, supervivencia y anomalía. Un modelo **MH-LSTM con atención** logró RMSE ≈ 1.0 día y MAE ≈ 0.8 día en RUL, y ~0.88 de exactitud en clasificación de falla a 10 días, superando a LSTM estándar, Random Forest y regresión lineal.
- **NASA C-MAPSS** (turbofán): el benchmark clásico de RUL.
- **NASA PCoE** (rodamientos, baterías): degradación.

Empezar con estos datasets permite construir y validar el pipeline **antes** de tener datos propios maduros.

### 5.4 El problema del desbalance (crítico aquí)

Las fallas son raras (datos muy desbalanceados). Técnicas obligatorias: **aprendizaje sensible al costo** (penalizar falsos negativos según el costo real de la falla), remuestreo (SMOTE, SMOTEBoost, RUSBoost) y métricas adecuadas (no "accuracy", sino costo total, recall de la clase falla, F-beta). La función objetivo debe ser el **costo monetario esperado**, no una métrica genérica.

### 5.5 Estrategia híbrida recomendada (PoF + datos)

El estado del arte combina lo mejor de ambos mundos:

- **Physics-informed:** la física (§3) genera *features* y restricciones (p. ej. energía de frenado acumulada, daño de Miner) que el modelo de datos consume. Esto reduce drásticamente la cantidad de datos necesaria y mejora la generalización entre marcas.
- **Data-driven:** ML aprende los residuos y patrones que la física no captura.

Esta combinación es lo que permite "ser vanguardia" sin tener la escala de datos de un Samsara.

---

## 6. Optimización de decisiones (nivel prescriptivo)

Predecir no basta; hay que **decidir óptimamente**.

### 6.1 Intervalo óptimo de reemplazo preventivo

Para una política de reemplazo por edad, el costo por unidad de tiempo es:

$$C(T) = \frac{c_p\,R(T) + c_f\,[1 - R(T)]}{\int_0^{T} R(t)\,dt}$$

donde $c_p$ = costo de intervención preventiva, $c_f$ = costo de falla (incluye remolque, downtime, falla en ruta, multas), $T$ = intervalo. Se minimiza $C(T)$. Con $c_f \gg c_p$ (típico en flota), el óptimo se adelanta. Esto convierte la confiabilidad ($R(t)$ de §4) en una **decisión de dinero**.

### 6.2 Priorización por criticidad (FMECA / RPN)

Cada modo de falla recibe un **Número de Prioridad de Riesgo**:

$$\text{RPN} = S \times O \times D$$

(Severidad × Ocurrencia × Detección). Esto enfoca el esfuerzo del módulo en los modos de falla que más importan (seguridad, costo, regulatorios) antes de pulir los marginales.

### 6.3 Decisiones aguas abajo

- **Inventario de refacciones:** los pronósticos de RUL agregados proyectan compras (cuántas balatas/neumáticos el próximo trimestre), liberando capital de trabajo.
- **Ruteo a taller:** dado RUL + ubicación GPS + red de talleres, programar el servicio donde y cuando minimice downtime.
- **Scorecard de conductores/rutas:** la misma data identifica qué conductores/rutas "queman" componentes más rápido.

### 6.4 El caso económico: cuánto se ahorra y bajo qué condición

El argumento de venta debe ser honesto y defendible ante un cliente técnico, no un porcentaje de brochure. Conceptos:

- Toda política tiene una **tasa de costo de largo plazo** (dinero por hora-motor/km). Hay tres: reactivo $C_{\text{rtf}}=c_f/\text{MTTF}$, preventivo óptimo $C^\star$, y predictivo (techo) $c_p/\text{MTTF}$, con $C_{\text{rtf}}\ge C^\star\ge C_{\text{cbm}}\ge c_p/\text{MTTF}$.
- La palanca es $\rho=c_f/c_p$ (cuánto más cara es la falla que la intervención planeada). El **techo de ahorro es $1-1/\rho$**, independiente del modelo: ningún algoritmo lo supera. En flota $\rho\approx 4$–10 por grúa, downtime, daño secundario y falla en ruta.

**La condición que los proveedores omiten:** el ahorro **requiere desgaste** ($\beta>1$). Si la falla es aleatoria ($\beta\le1$, sin memoria), el preventivo **no ahorra nada** — es un teorema (Barlow–Proschan). Por eso el sistema **clasifica por $\beta$ antes de prometer ahorro**, y enfoca el esfuerzo en componentes de desgaste con falla cara: DPF, balatas, rodamientos.

**Números (cálculo propio, no brochure).** Balata ($\beta{=}2.3$, $\eta{=}1500$ h, $\rho{=}8.4$): reactivo ~17,000 MXN/1000h → preventivo óptimo ~8,600 (**−50 %**) → techo predictivo ~2,000 (−88 %). DPF ($\rho{=}8.9$): **−43 %** preventivo, −89 % techo. El ahorro de flota es la suma sobre componentes y unidades, ponderada por la mezcla.

**Realización en streaming:** la política es robusta al error de estimación (la curva de costo es plana cerca del óptimo), así que se captura ~95 % del ahorro con ~5 fallas observadas; el cuello de botella es acumularlas en calendario, que el prior físico acelera.

**Reconciliación con la literatura.** El DOE/FEMP reporta 25–30 % de reducción de costo de mantenimiento (predictivo vs reactivo), 70–75 % menos paros, 35–45 % menos downtime; EPRI, −30 % vs periódico y −50 % vs reactivo. Esos son **promedios de flota** que mezclan desgaste (ahorro alto) con falla aleatoria (ahorro ~0) y descuentan fricción real; nuestros 40–50 % son **por componente favorable**. Ambos son consistentes. La cifra defendible: "40–50 % en los componentes de desgaste caros donde concentramos el sistema, ~0 donde la falla es aleatoria, blended hacia 25–30 % de flota — y lo calculamos con tus datos". El desarrollo completo está en *Estudio de Ahorro — Mantenimiento Predictivo vs Reactivo*.

---

## 7. Arquitectura de integración en la plataforma existente

Mapeo directo a su stack actual (Orange Pi bridge + Traccar + PostgreSQL + Headscale):

### 7.1 Edge (Orange Pi Zero 3)

- **Interfaz CAN ya incluida en el nuevo edge** (OBD-II + J1939 con autodetección, ver §2.1). Ya no es un pendiente de hardware.
- Captura de DTC (DM1/DM2 en J1939; P-codes en OBD-II), muestreo de parámetros (RPM, temp, presión, carga, ΔP DPF, DEF).
- **Extracción de features en el borde:** eventos bruscos y conteo rainflow del IMU (daño de Miner), energía de frenado, km por componente vía GPS. Esto reduce ancho de banda (se envían features, no señal cruda).
- **Entradas AHD:** captura de clip dirigida por evento (ver §7.4), no streaming continuo.
- Buffer local (la microSD ya está) + publicación por **MQTT** (ya contemplado en el bridge).
- ACL de Headscale ya aísla `tag:mdvr-device` (no se comunican entre sí): el módulo respeta ese modelo de seguridad.
- El stack de features se despliega por **niveles** según el SKU de hardware (camión pesado vs Tracker mini): ver §7.5.

### 7.2 Servidor central

- **PostgreSQL + extensión TimescaleDB** para las señales de alta frecuencia (series de tiempo). Traccar sigue para posición.
- **Registro de activos y ciclo de vida de componentes** (qué balata/neumático, instalada cuándo, en qué posición, vida acumulada real).
- **Módulo CMMS / órdenes de trabajo** (un DTC crítico genera orden automática).
- **Motor de reglas** (umbrales OEM + DTC) para CBM inmediato.
- **Servicio de inferencia** (RUL/anomalía por componente) + **registro de modelos**.

### 7.3 Pipeline de modelado

- Entrenamiento offline + **feature store** + **model registry**.
- Modelos **jerárquicos** con la estructura **clase → marca → modelo → unidad** (camión pesado / vehículo ligero / motocicleta), con conductor y ruta como covariables. Esta jerarquía multi-clase es la que permite que el Tracker mini (autos y motos) y la flota pesada compartan un mismo marco estadístico: la derivación formal está en la Parte VII del documento de Fundamentos Matemáticos.
- Reentrenamiento periódico conforme la flota acumula historia; cada falla real actualiza el modelo local del componente.

### 7.4 Cámaras AHD como sensor de mantenimiento (dirigido por evento)

El video no se usa como flujo continuo (cómputo y datos limitados), sino disparado por evento. Tres usos ordenados por relación valor/esfuerzo:

1. **Etiquetado de eventos.** Un clip disparado por IMU/J1939 clasifica el evento (bache, frenada brusca, colisión). Esto mejora la *atribución de daño por fatiga* (Parte V del doc. matemático): el conteo rainflow gana una etiqueta de causa, y el trío "clip + daño rainflow + reparación posterior" es un ejemplo de entrenamiento etiquetado de alta calidad.
2. **Monitoreo de conductor (DMS).** Fatiga y distracción medidas visualmente. Convierte la covariable "conductor" del modelo de Cox/AFT de *inferida* (IMU) a *medida*, sharpeando ese factor de riesgo. (Nota: el video hacia el conductor es dato personal sensible; ver §10 de gobernanza.)
3. **Inspección visual asistida** (banda/flanco de neumático, fugas). Mayor esfuerzo y menor madurez; fase posterior.

Restricción de cómputo: el Orange Pi Zero 3 (Mali-G31, sin NPU) no corre visión pesada; CV ligero o nulo en el borde, inferencia pesada en un SKU con NPU (clase RK3588) o en servidor sobre clips subidos.

### 7.5 Niveles de edge (camión pesado vs Tracker mini)

La extracción de features se despliega por niveles según sensores y cómputo disponibles. El **modelo es el mismo**; cambia la disponibilidad de entradas, que el marco bayesiano tolera de forma nativa (una unidad con menos covariables tiene posteriors más anchos y cae hacia el prior de su clase).

| Nivel | Plataforma | Sensores | Features físicas disponibles |
|---|---|---|---|
| **Pleno** | Bridge camión | J1939 + IMU + GPS + AHD | DTC/SPN, energía de frenado, daño rainflow–Miner, L10, severidad de ruta, eventos de video |
| **Medio** | Tracker mini (auto) | OBD-II + IMU + GPS | P-codes, energía de frenado, daño rainflow, severidad de ruta |
| **Ligero** | Tracker mini (moto) | IMU + GPS (OBD raro) | daño rainflow, energía de frenado (proxy), ángulo de lean, detección de caída |

Para motos, el IMU es el sensor *primario* (muchas carecen de puerto de diagnóstico estándar), y aparecen modos de falla propios (cadena/piñón, desgaste acelerado de neumático trasero) tratados en el doc. matemático.

### 7.6 Nota sobre lenguajes

Para la capa de modelado, el ecosistema **Julia** cubre todo esto con rendimiento cercano a C: `Distributions.jl` y `Survival.jl` (Weibull/Cox/supervivencia), `Turing.jl` (modelos jerárquicos bayesianos — ideal para el partial pooling entre clases y marcas), `DifferentialEquations.jl` (modelos de degradación PoF), `Flux.jl`/`Lux.jl` (LSTM), `MLJ.jl` (gradient boosting/RF). El edge en Python (el bridge ya lo usa) para captura; el modelado pesado en Julia.

### 7.7 Estimación online: capas y cadencia

El modelo no se ajusta una sola vez: **asimila eventos en streaming** (una ponchadura, una reparación, el flujo OBD/CAN) y actualiza las distribuciones sin recalcular todo. Se organiza en capas a distinta cadencia (la derivación formal —filtro bayesiano como ecuación maestra, SG-MCMC, sistemas reparables de Kijima, inferencia amortizada, POMDP— está en la Parte VIII del doc. matemático):

| Capa | Qué estima | Método | Cadencia | Dónde |
|---|---|---|---|---|
| Filtrado de estado | salud de cada unidad (RUL al vuelo) | Kalman/UKF/partículas | por evento / tiempo real | borde + servidor |
| Eventos recurrentes | intensidad de fallas; calidad de reparación $q$ | NHPP / renovación generalizada (Kijima) | por reparación | servidor |
| Hiperparámetros de flota | Weibull/jerarquía ($\beta,\eta,\tau$) | HMC por lotes / SG-MCMC | nocturno/semanal | servidor |
| Inferencia de despliegue | posterior de unidad nueva | red amortizada (SBI) | instantáneo | servidor/borde |
| Política de intervención | acción óptima | POMDP / RL | por decisión | servidor |

Dos consecuencias de diseño: (1) la **reparación es dato de primera clase** — cada orden de trabajo actualiza tanto el modelo de esa unidad como los hiperparámetros de flota, y la *calidad* de la reparación se estima como parámetro $q$ (modelo de edad virtual); (2) la **inferencia amortizada** —entrenar offline con el simulador físico (§3), inferir con un forward pass— evita el cómputo repetido. El feature store y el model registry de §7.3 sostienen este reparto. El plan de construcción de esta máquina de estimación está en el documento *Mapa de Trabajo — Estimación Online*.

### 7.8 Métodos geométricos y espectrales (EDA y verificación de modelo, no predictores centrales)

Conviene distinguir herramientas de **exploración y chequeo de supuestos** de los predictores de producción. Tratamiento riguroso y veredicto en el Apéndice B del doc. matemático; resumen operativo:

- **PCA global/local:** PCA global como **baseline interpretable** y chequeo de que las features físicas viven en baja dimensión (supuesto de §3 / VII.1); se demota, no se descarta. La intuición "geométrica" (PCA local) se realiza rigurosamente como diffusion maps, no como PCAs locales sueltos.
- **Diffusion maps / métodos espectrales de grafo:** una sola pista (geometría + clusters). Útil para descubrir qué marcas/modelos se comportan parecido y **validar la estructura de pooling jerárquico** de VII.2.
- **Koopman / DMD:** la pista de **dinámica** de degradación (indicador de salud con buena tendencia + surrogate rápido); evaluar en fase media. Es el dual de operador del Fokker–Planck que ya usa el filtro (VIII).
- **Unificación (Apéndice B.5):** PCA-geométrico, grafo y Koopman son caras del mismo operador de difusión/transferencia (diffusion maps $\alpha=1$ geometría, $\alpha=0$ clusters, $\alpha=\tfrac12$ = Fokker–Planck de VIII; Koopman/Perron–Frobenius adjuntos). Construir **un solo grafo de similitud** y leerlo de tres formas es más barato y coherente que tres pipelines.
- **TDA / homología persistente:** **descartado del plan activo.** Su mejor caso (vibración de rodamientos) está bloqueado por hardware (el MPU6050 es de baja frecuencia) y sus otros usos no superan baselines más baratos. Se revisita solo si aparece hardware de vibración.
- **Caveat (supervisado vs no supervisado):** ninguno de estos contesta "qué es lo más importante en mantenimiento" — esa es una pregunta supervisada que responden el hazard (Cox), la física de falla, el FMECA/RPN y el costo (VI.2).

---

## 8. Biblioteca de fuentes, manuales y estándares a reunir

Para hacerlo "con documentos y manuales reales", esta es la lista de adquisición:

**Estándares (comprar/licenciar):**
- ISO 55000/55001/55002 (gestión de activos)
- SAE JA1011 + JA1012 (RCM); IEC 60300-3-11
- MIL-STD-1629A (FMECA); ISO 13374, ISO 17359 (monitoreo de condición)
- Familia SAE J1939 (especialmente J1939-71 capa de aplicación, J1939-73 diagnósticos) — necesaria para parsear SPN/FMI correctamente
- NOMs mexicanas vigentes de condiciones físico-mecánicas del autotransporte federal (verificar versión)

**Manuales OEM (intervalos de servicio, TSBs, diccionarios de códigos):**
- Motores: Cummins (QuickServe), Detroit Diesel, PACCAR MX, Navistar/International, Volvo/Mack (incluye PPID/PSID propietarios)
- Chasis: Freightliner, Kenworth, Peterbilt, International, Volvo, Mack
- Componentes: frenos Bendix/Wabco; transmisiones Eaton/Allison; ejes Dana/Meritor; neumáticos (data books de Michelin, Bridgestone, Continental con curvas de desgaste y profundidad mínima)

**Literatura científica (modelos):**
- Archard (1953) y correcciones termo-mecánicas para frenos
- Lundberg–Palmgren (vida L10 de rodamientos)
- Palmgren–Miner + Basquin + rainflow (fatiga)
- Modelos de desgaste de neumático por energía de fricción/slip
- Papers de RUL: Weibull condicional, procesos de Wiener/Gamma, C-MAPSS, datasets Scania (APS y Component X)

---

## 9. Roadmap por fases

| Fase | Entregable | Valor |
|---|---|---|
| **0. Diagnóstico y gobernanza** | Parser dual OBD-II/J1939 con autodetección; auditoría de datos; FMECA inicial con RPN; **registro de consentimiento + separación operativo/analítico** (ver §10) | Fundación legal y técnica |
| **1. Captura** | Ingesta normalizada de DTC + telemetría + horas/km reales por componente; **esquema estructurado de evento de reparación** (las etiquetas); registro de activos | Datos confiables y etiquetados |
| **2. CBM por reglas** | Umbrales OEM + alertas DTC + checklist regulatorio + órdenes de trabajo | Quick win, ROI temprano |
| **3. Vida estadística** | Weibull/Cox por componente; jerarquía clase → marca → modelo → unidad; RUL condicional con buffer | Predicción real, multi-clase |
| **4. PoF híbrido** | Frenos (Archard), neumáticos (energía-slip), fatiga (Miner+IMU); modos de moto (cadena, lean) | Diferenciador técnico |
| **5. ML avanzado** | Survival nets / LSTM / anomalía + visión por evento (AHD) + SHAP + costo-sensible | Vanguardia |
| **6. Prescriptivo** | Intervalo óptimo de costo, inventario, ruteo a taller | Optimización de negocio |

Cada fase produce valor por sí sola; no hay que esperar a la fase 6 para tener retorno.

---

## 10. Gobernanza de datos, consentimiento y estrategia de datos

El dato agregado entre flotas no es un subproducto: es el **activo estratégico** (el "moat"). Más unidades → mejores priors jerárquicos (Parte VII del doc. matemático) → mejores predicciones para el siguiente cliente con poca historia. Es lo que tienen los incumbentes (Samsara, Geotab) y un entrante no; construirlo deliberadamente, **bajo consentimiento explícito y firmado**, es la jugada. Esta sección define cómo hacerlo bien.

### 10.1 Las reparaciones son las etiquetas: esquema estructurado

Sin *ground truth* estructurado, los modelos de supervivencia no tienen con qué entrenarse. Cada reparación debe capturarse como un **evento estructurado**, no como texto libre:

| Campo | Ejemplo | Uso |
|---|---|---|
| `componente` | balata delantera izq. | clave del modelo de vida |
| `modo_falla` | desgaste / fractura / fuga | FMECA, hazard por modo |
| `fecha`, `odómetro`, `horas_motor` | — | edad real a la falla (censura) |
| `accion` | reemplazo / ajuste | distinguir falla de mantenimiento |
| `costo` | MXN | $c_f$, $c_p$ de la decisión óptima (§6) |
| `causa_raiz` | alineación, sobrecarga | atribución, covariable |
| `vehiculo_id`, `clase`, `marca`, `modelo` | — | nivel jerárquico |

Esto se diseña en la Fase 1 y es tan importante como la captura de sensores.

### 10.2 Consentimiento por capas y por finalidad

Dos ejes de consentimiento, ambos necesarios:

- **Por capas (quién consiente):** el **cliente** (flota) consiente compartir datos vía contrato; pero el **conductor** tiene derechos propios, sobre todo por la cámara en cabina, cuya imagen es dato personal sensible. Diseñar dos niveles: contrato con el cliente + aviso/consentimiento del conductor.
- **Por finalidad (para qué):** la limitación de finalidad impide repurposear datos en silencio. Tres finalidades distintas, cada una con su consentimiento:
  1. **Operar el servicio** para ese cliente (dato identificable).
  2. **Mejorar modelos para todos** (uso secundario; debe ir **des-identificado**).
  3. **Publicar estadística agregada** (anonimizado, ver §10.4 y oportunidades de publicación en el doc. matemático).

El permiso firmado y el **aviso de privacidad** deben cubrir explícitamente las finalidades 2 y 3, o no podrán usarse legítimamente.

### 10.3 Marco legal mexicano (actualizado 2025)

Punto sensible que cambió recientemente: desde el **21 de marzo de 2025 está en vigor una nueva LFPDPPP** (Ley Federal de Protección de Datos Personales en Posesión de los Particulares) que **abrogó la de 2010**. El **INAI desapareció**; la autoridad de protección de datos es ahora la **Secretaría Anticorrupción y Buen Gobierno (SABG)**. La nueva ley amplía la definición de *responsable* y de *tratamiento*. Implicaciones para este proyecto:

- Ubicación del vehículo, identidad del conductor y **video hacia el conductor** son datos personales; la imagen del conductor entra en terreno sensible.
- Se requieren: **aviso de privacidad** conforme a la nueva ley, **consentimiento expreso** (el permiso firmado), limitación de finalidad, minimización de datos, medidas de seguridad, y atención a derechos **ARCO** (acceso, rectificación, cancelación, oposición).
- El **reglamento** de la nueva ley estaba pendiente de emitirse; conviene revisar su contenido al momento de implementar.

**Advertencia:** esto no es asesoría legal. Conviene contratar asesoría mexicana en protección de datos para redactar el aviso de privacidad, el contrato con el cliente y el consentimiento del conductor conforme a la ley vigente y su reglamento.

### 10.4 Arquitectura de gobernanza

Tres componentes técnicos que hacen cumplible lo anterior:

- **Registro de consentimiento versionado:** quién consintió a qué finalidad y cuándo. Es la fuente de verdad para qué datos pueden usarse y para qué.
- **Trazabilidad/etiquetado de datos (data lineage):** cada registro arrastra su consentimiento. Si un cliente retira el consentimiento, su unidad se **excluye de los sets de entrenamiento** de forma reproducible.
- **Separación operativo / analítico:** dos almacenes. El **operativo** (identificable) sirve a ese cliente; el de **analítica/entrenamiento** recibe datos **des-identificados** (pseudonimización de IDs, agregación, supresión de trazas finas de ubicación). Para la finalidad 3 (publicación), anonimización completa.

Esto encaja con el modelo de **ACL por tags de Headscale** que ya tienes: la separación de planos de datos es una extensión natural del aislamiento por tags que ya aísla `tag:mdvr-device`.

---

## 11. Riesgos y consideraciones

- **Calidad de datos:** modelos buenos con datos malos fallan. La fase 1 es la más importante y la menos glamorosa.
- **Heterogeneidad de flota y multi-clase:** distintas marcas/años/protocolos/clases (pesado, ligero, moto). Mitigación: diccionarios de códigos por OEM + jerarquía clase → marca → modelo → unidad + manejo nativo de modalidades faltantes.
- **Desbalance y costo asimétrico:** optimizar por costo monetario, no por accuracy.
- **Falsos positivos:** erosionan la confianza del taller. Calibrar umbrales y dar explicabilidad (SHAP) para que el mecánico entienda la alerta.
- **Privacidad y consumo de la cámara:** el video hacia el conductor es dato sensible (§10.3) y consume el grueso del plan de datos; tratarlo como evidencia por evento, no streaming.
- **Hardware de vibración:** el MPU6050 no basta para diagnóstico de rodamientos por vibración de alta frecuencia; es una mejora de fase posterior.
- **Cómputo del edge:** el Orange Pi Zero 3 no corre visión pesada; CV en SKU con NPU o en servidor.
- **Method-shopping (scope creep):** el riesgo de invertir en métodos vistosos (TDA, espectral avanzado) antes de resolver el cuello de botella real, que es de **datos e identificabilidad**, no de método. Regla: ningún método nuevo entra a producción sin superar un baseline en una tarea con held-out. La disciplina de datos (Fase 0–1) tiene prioridad sobre cualquier sofisticación.
- **Transferencia de física sobreestimada:** "la misma física entre marcas" comparte la forma funcional, no las constantes ($K,k,\alpha$), que se estiman por componente y marca. Validar empíricamente la transferencia antes de asumirla.
- **Proxies del IMU no calibrados:** convertir aceleración del MPU6050 a esfuerzo/energía de un componente es específico del vehículo; sin ground truth (galgas, desgaste medido) son proxies ordinales. Calibrar antes de tratarlos como medición.

---

## 12. Síntesis

Ser "lo mejor del mercado" en este nicho no significa más sensores que Samsara; significa **cerrar el lazo físico-estadístico-de-decisión** que la mayoría de plataformas comerciales no cierran: usar la física de falla (Archard, Miner, L10, energía de neumático) para generar features que un modelo jerárquico bayesiano/ML consume, calibrado por costo monetario real, y traducido a una decisión óptima de cuándo y dónde intervenir. El nuevo edge ya trae CAN (OBD-II + J1939) y entradas AHD, así que la adquisición está resuelta; lo que falta es la capa de modelado, el CMMS y la gobernanza de datos. El alcance multi-clase (camión pesado + Tracker mini para autos y motos) **refuerza** el marco: la misma física y la misma jerarquía bayesiana sirven a todas las clases, y cada unidad nueva mejora los priors de todas. El activo de largo plazo es el dato agregado bajo consentimiento; el IMU vía rainflow + Miner sigue siendo un diferenciador que pocos explotan.

---

*Documento de investigación. Las cifras de ahorro citadas provienen de proveedores/casos de estudio y deben validarse con datos propios. Verificar versión vigente de toda NOM y estándar antes de implementar.*
