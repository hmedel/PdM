# Especificación de Adquisición de Datos — de la matemática a la realidad del flujo

**Cruce ingeniería ↔ modelo: qué señal necesita cada objeto matemático, qué entrega el hardware real, y el veredicto.**
Versión 0.1 — Junio 2026

> Principio rector (postdoc crítico): **solo se construye lo que el flujo de datos real alimenta hoy.** Todo lo demás se etiqueta como *proxy sin calibrar*, *manual*, o *bloqueado por hardware* — no se presenta como si fuera medición. Este documento es el filtro de realidad sobre la matemática de *Fundamentos* y la §2–5 del *Dossier*.

---

## 1. Inventario de fuentes reales (lo que el edge realmente produce)

| Fuente | Qué entrega | Naturaleza | Disponibilidad |
|---|---|---|---|
| **J1939** (CAN, 250 kbps, Deutsch 9 pines) | SPNs de motor/chasis/aftertreatment + DTC (DM1/DM2) | **broadcast** continuo | Camión pesado Clase 4–8 (rico) |
| **OBD-II** (ISO 15765 / CAN, 16 pines) | PIDs Mode 01 + DTC (P-codes) | **request-response** (hay que pollear) | Vehículo ligero (<~6350 kg); soporte de PID variable por modelo |
| **IMU MPU6050** (I2C) | accel 3 ejes + gyro 3 ejes | serie temporal | Siempre; **rate limitado** (ver §4) |
| **GPS** (desde dashcam) | posición, velocidad, rumbo | serie temporal | Siempre; ~cada 15 s en presupuesto actual |
| **AHD** (cámaras) | video por evento | evento | Nuevo edge; CV pesado bloqueado en el borde |
| **DVIR / orden de taller** | inspección, tread depth, reparación | evento (WS-A) | Proceso humano; calidad variable |

**La brecha estructural OBD vs J1939.** J1939 difunde decenas de SPNs de forma continua sin pedirlos; OBD-II es polling y su soporte de PID **varía por vehículo** (el bitmask del PID 0x00 dice cuáles existen). Consecuencia dura: el vehículo ligero (Tracker mini) entrega **menos y peor** que el camión pesado. La jerarquía bayesiana (VII.2) no es un lujo aquí: es lo que permite que las clases data-pobres "tomen prestada fuerza" de las data-ricas.

---

## 2. Tabla maestra: objeto matemático → señal → fuente real → veredicto

Veredictos: **A** = alimentable hoy sin calibración · **P** = proxy sin calibrar (usable como covariable ordinal) · **M** = requiere entrada manual/proceso · **B** = bloqueado por hardware.

| Objeto (Fundamentos) | Señal requerida | Fuente real (SPN/PID/sensor) | Cadencia | Veredicto |
|---|---|---|---|---|
| **CBM por DTC** (motor de reglas, Dossier §7.2) | DTC activos/históricos | J1939 **DM1/DM2** (SPN+FMI); OBD **Mode 03** (P-codes) | evento | **A** |
| **Vida Weibull/Cox en escala de uso** (II–III) | tiempo en horas-motor o km | **horas: SPN 247** (solo J1939); **km: SPN 245** (J1939) / GPS-km / OBD 0xA6 (irregular) | 0.1 Hz | **A** (J1939) / **P** (ligero) |
| **Aftertreatment DPF/DEF/SCR** (3.6) | ΔP DPF, nivel DEF, NOx, regen, derate | **SPN 3251** (ΔP DPF), **SPN 1761** (nivel DEF), **NOx SPN ~3200s (verificar)**, **SPN 5246** (derate) | 0.1–1 Hz | **A** |
| **Condición de motor/aceite** (3.5) | presión/temp aceite, refrigerante, fuel rate, carga | **SPN 100** (P aceite), **175** (T aceite), **110** (refrig.), **183** (fuel rate), **92** (carga), **98** (nivel aceite) | 0.1–1 Hz | **A** (J1939) |
| **Batería** (3.7) | voltaje arranque / bajo carga | **SPN 168** (battery potential) / OBD **0x42** (module voltage) | 1 Hz + en arranque | **A** |
| **Energía de frenado, Archard** (3.1, V.1) | $\propto m\,v\,\Delta v$ por evento, idealmente por rueda | velocidad **SPN 84** / OBD **0x0D**; desacel. **IMU**; freno **SPN 597** (switch, booleano); masa **SPN 178/179** (peso por eje, *si existe*) | IMU rate; eventos | **P** (por vehículo, no por posición; sin calibrar) |
| **Fatiga, Miner+rainflow** (3.4, V.3) | aceleración continua → ciclos; transferencia accel→esfuerzo | **IMU** (rainflow on-edge); transferencia **no calibrada** | IMU rate | **P** (índice ordinal de daño) |
| **Rodamientos L10** (3.3, V.4) | revoluciones, carga; **vibración** para falla incipiente | revs de velocidad; carga **SPN 178/179**; **vibración → MPU6050 insuficiente** | — | **P** (paramétrico) / **B** (CBM por vibración) |
| **Neumáticos** (3.2) | tread depth, presión, slip | tread = **DVIR manual**; presión = TPMS *si existe*; slip = proxy débil | inspección | **M** + **P** |
| **Covariables de ruta/conductor** (III, IV.5) | severidad de ruta, conductor | ruta: **GPS** (pendiente, rugosidad vía IMU); conductor: **falta proceso de asignación** | continua / por viaje | **A** (ruta) / **M** (conductor) |
| **Koopman/DMD + geometría** (Apéndice B) | series multivariadas del estado | los SPNs/PIDs + IMU + GPS muestreados | según muestreo | **A** (para EDA) |

---

## 3. Por rama: la realidad de ingeniería

### 3.1 Aftertreatment + motor: el *quick win* totalmente alimentable (Tier 1)
Es la rama donde la matemática sabrosa toca la realidad **sin calibración**: ΔP DPF (SPN 3251), nivel DEF (SPN 1761), NOx, regeneraciones y derate (SPN 5246) son SPNs J1939 difundidos por el ACM. Son además **las fallas más caras y frecuentes** del diésel moderno (Dossier §3.6). El modelo aquí —tendencia de ΔP, conteo de regeneraciones, hazard por SPN+FMI, Weibull sobre horas-motor— se entrena con dato que **ya existe en el bus**. Esto debería ser el primer producto, no la última fase.

### 3.2 Lifing por uso real: sólido en J1939, débil en ligero
La afirmación "vida por uso real, no por odómetro" (Dossier §2.3) depende de **horas-motor (SPN 247)**, que es fiable en J1939 y **ausente en OBD-II** (OBD solo da run-time desde arranque, PID 0x1F, que se reinicia). En vehículo ligero hay que caer a km (odómetro OBD 0xA6 de soporte irregular, o km integrado por GPS). Implicación de diseño: la **escala de tiempo primaria es por clase** (horas en pesado; km en ligero), y eso ya está contemplado en el esquema WS-A (§9, decisión 1).

### 3.3 Frenos y fatiga: proxies reales, pero sin calibrar (Tier 2)
La energía de frenado se arma con velocidad (SPN 84 / PID 0x0D) + desaceleración del IMU + switch de freno (SPN 597). Tres límites duros: (a) el switch de freno es **booleano** —no hay fuerza de frenado medida—, así que la magnitud sale del IMU, no de sensor; (b) la masa requiere **peso por eje (SPN 178/179)**, que solo existe si el camión tiene suspensión neumática instrumentada — si no, se asume; (c) es **por vehículo, no por posición** (no hay velocidad/presión por rueda). Resultado: un **proxy ordinal por vehículo**, útil como covariable, **no** como medición física hasta calibrar contra desgaste medido. Lo mismo aplica a rainflow→Miner: la conversión aceleración→esfuerzo es una función de transferencia específica del vehículo y **no calibrada**; da un índice de daño relativo, no daño absoluto de Miner. (Riesgos ya registrados en Dossier §11.)

### 3.4 Rodamientos: paramétrico sí, condición no
L10 (Lundberg–Palmgren) se puede calcular **paramétricamente** de la carga estimada y revoluciones. Pero la detección **temprana** de falla incipiente exige análisis de vibración (BPFO/BPFI), y eso está **bloqueado** por el MPU6050 (§4). Veredicto: modelo paramétrico ahora; CBM por vibración solo con hardware nuevo.

### 3.5 Neumáticos: el dato primario es manual
No hay sensor de profundidad de banda. La tasa de desgaste se alimenta de **mediciones periódicas de tread depth capturadas como eventos DVIR** (WS-A) + el proxy débil de energía/slip. La presión (TPMS) solo si el camión la difunde. Es la rama más dependiente de proceso humano disciplinado.

---

## 4. Chequeo de realidad del IMU (cuantitativo)

El MPU6050 sobre I2C: la FIFO permite hasta ~1 kHz de muestreo sostenido con un lector en C ajustado; en un bucle de Python sobre el Orange Pi, de forma realista unos pocos cientos de Hz por contención de bus y jitter del SO. Qué habilita y qué no:

| Uso | Banda requerida | ¿MPU6050? |
|---|---|---|
| Eventos bruscos (frenada, bache) | < ~20 Hz | **Sí** |
| Desaceleración para energía de frenado | < ~50 Hz | **Sí** |
| Fatiga de chasis/suspensión (rainflow) | < ~50–100 Hz | **Sí** (cabe en FIFO 1 kHz) |
| Lean/caída de moto (Tracker mini) | < ~20 Hz | **Sí** (IMU es sensor primario) |
| **Vibración de rodamiento (BPFO/BPFI + sidebands)** | **≥ varios kHz** | **No** (bloqueado) |

Es decir: el IMU actual cubre fatiga estructural, dinámica de manejo y eventos —todo lo de baja frecuencia— y queda corto **solo** para vibración de rodamiento de alta frecuencia. La mejora futura es un acelerómetro dedicado (≥ varios kHz) montado cerca de mazas/transmisión; no es de fase 1.

---

## 5. Contrato de datos del edge (lo que debe emitir, y el volumen)

Para que la telemetría quepa en el presupuesto (~60 MB/mes de no-video, Dossier §7.4) el edge **no** envía señal cruda: extrae features en el borde y emite por MQTT.

| Stream | Contenido | Cadencia | Volumen est. |
|---|---|---|---|
| Parámetros J1939/OBD | ~20 SPNs/PIDs (motor, aftertreatment, batería) | 1 muestra/10 s (con delta-encoding) | ~30 MB/mes |
| Eventos DTC | DM1 deltas (aparición/desaparición de SPN+FMI) | por evento | < 1 MB |
| Features IMU on-edge | histogramas rainflow, acumulador de energía de frenado, flags de evento brusco | agregado cada 1–5 min | pocos MB |
| GPS | pos/vel/rumbo | cada 15 s | ~3–4 MB |
| Heartbeat | salud del edge | cada 60 s | ~2 MB |
| Clips AHD | disparados por evento (IMU/DTC) | bajo demanda | (presupuesto de video aparte) |

Total no-video ≈ **40–50 MB/mes**, holgado contra los ~60 MB. Detalle clave: el **rainflow se cuenta en el borde** (no se puede shippear IMU continuo por LTE), emitiendo histogramas de ciclos — esto es un requisito de firmware, no de servidor.

---

## 6. Priorización por realidad de datos (la parte sin piedad)

| Tier | Qué | Por qué | Matemática que habilita |
|---|---|---|---|
| **1 — construir ya** | Aftertreatment + motor/aceite + batería + captura DTC + lifing por horas, **en J1939** | Totalmente alimentable, **cero calibración**, modos de falla caros | CBM por reglas, Weibull/Cox sobre horas, hazard por SPN+FMI |
| **2 — construir, etiquetar como proxy** | Energía de frenado, rainflow-fatiga | Diferenciador real, pero **sin calibrar** | Archard/Miner como **covariables ordinales** (no medición) |
| **3 — proceso humano** | Tread depth (DVIR), asignación de conductor | Dato primario es manual | desgaste de neumático; covariable conductor del Cox |
| **4 — diferir (bloqueado)** | Vibración de rodamiento, datos por posición, TDA de vibración | Falta hardware (acelerómetro kHz, sensores por rueda) | L10 por condición; diagnóstico por vibración |

---

## 7. Síntesis crítica

La realidad de los datos dicta una conclusión que conviene aceptar sin romanticismo: **el primer producto no es el módulo de física-de-falla completo, sino el de CBM/lifing sobre J1939 en camión pesado** — aftertreatment, motor, batería y DTC —, porque es la única rama donde la matemática sabrosa se alimenta de dato real **sin calibrar nada**, y ataca las fallas más caras. Los proxies físicos (frenos, fatiga vía IMU) son el diferenciador de mediano plazo, pero hay que venderlos internamente como **índices ordinales sin calibrar** hasta tener ground truth (desgaste medido, galgas), o se cae en el error de presentar una transferencia física no validada como medición. El vehículo ligero y la moto (Tracker mini) son estructuralmente data-pobres (OBD/IMU), y su rescate es la jerarquía bayesiana, no más sensores. Y la vibración de rodamiento —el caso de oro de varios métodos— está fuera hasta que cambie el hardware.

En una frase: **la física no se desperdicia, pero entra por capas según lo que el bus realmente difunde; lo que no se puede medir hoy se modela paramétricamente o se difiere, y nada sin calibrar se presenta como verdad.**

---

## 8. Decisiones de ingeniería para cerrar

1. ¿El camión objetivo difunde **peso por eje (SPN 178/179)**? Define si la masa para energía de frenado es medida o asumida.
2. ¿Confirmamos el **SPN exacto de NOx** (rango 3200s) contra J1939-71 o un DBC del OEM antes de codificar el parser?
3. ¿Lector IMU en **C/DMA** (para acercarse a 1 kHz y dejar margen de rainflow) o basta el bucle de Python a unos cientos de Hz?
4. ¿De dónde sale la **asignación de conductor** por viaje (login, NFC, app)? Sin esto, "conductor" del Cox es inferido, no medido.
5. ¿El DBC/diccionario de SPN por OEM (Cummins/Detroit/PACCAR/Volvo-Mack, incluidos PPID/PSID propietarios) lo licenciamos o lo construimos incrementalmente desde el bus?
