# Auditoría técnica — matemática, economía, física y literatura

**Auditoría adversarial de toda la implementación antes de lanzar pruebas más sofisticadas.** Tres
auditores independientes en paralelo (matemática de confiabilidad; economía/simulación; literatura +
sustento físico) verificaron cada fórmula contra su fuente y revisaron el código línea a línea.

Versión 1.0 — Junio 2026.

---

## 0. Veredicto

**El armazón teórico es correcto y está bien fundamentado** (las 4 fórmulas centrales —verosimilitud
Weibull-AFT truncada-censurada, RUL de forma cerrada, tasa de costo de renovación-recompensa, regla
IFR— se verificaron correctas). Los métodos son el **estándar aceptado** en la literatura. La
auditoría encontró **2 defectos críticos, 3 altos y varios medios/menores**; los que cambian
conclusiones **ya fueron corregidos** (ver §4). El más importante: la política predictiva miraba el
futuro (oráculo) — se reescribió como **CBM honesto sobre los precursores observados**, lo que bajó
el ahorro predictivo de ~2.3× a **~1.6× el del calendario** (cifra creíble, no artefacto).

---

## 1. Matemática de confiabilidad — CORRECTA (defectos menores corregidos)

| # | Hallazgo | Sev. | Estado |
|---|---|---|---|
| 1.1 | Verosimilitud Weibull-AFT con censura+truncamiento: signo `+(a/η)^β` correcto; censura correcta; AFT bien especificado | ok | ✓ verificado |
| 1.2 | RUL `E[T\|T>t]=η·e^w·Γ(1+1/β)·Q(1+1/β,w)` con gamma incompleta **superior**; límite t=0 ⇒ MTTF | ok | ✓ verificado |
| 1.3 | Tasa de costo `C(T)` de renovación-recompensa; Simpson válido | ok | ✓ verificado |
| 1.4 | Regla IFR `β_lo>1 ∧ s_prev≥s_min` estadísticamente sólida | ok | ✓ verificado |
| 1.5 | `optimal_age` no manejaba óptimo en frontera (β≤1 ⇒ T* finito espurio); paso de malla 240 vs 239 | MEDIO | **✓ corregido** (devuelve T*=∞ con tasa cf/MTTF; malla 241 puntos) |
| 1.6 | Bootstrap de β arrancaba desde el óptimo full-sample → subestimaba la varianza (IC angosto → riesgo de falso β>1) | MEDIO | **✓ corregido** (arranca desde `x0`; nota nboot≥500 en producción) |
| 1.7 | `exp(w)` desbordaba en RUL para piezas muy viejas (Inf·0=NaN) | menor | **✓ corregido** (asíntota MRL≈1/h(t)) |
| 1.8 | Simpson no validaba `n` par; sin guarda de `nfail≥1` por grupo | menor | **✓** (n forzado par); identificabilidad documentada |
| 1.9 | NelderMead con `g_tol` inerte para verosimilitud con gradiente cerrado | menor | documentado (recomendación: LBFGS+gradiente en producción) |

## 2. Economía / simulación — 2 CRÍTICOS corregidos

| # | Hallazgo | Sev. | Estado |
|---|---|---|---|
| 2.1 | **Predictivo miraba el futuro** (usaba el día de falla real `fday` + ruido simétrico, sin falsos positivos en censuras) → capturaba el techo por construcción (φ≈1) | **CRÍTICO** | **✓ corregido**: reescrito como CBM que observa el **daño acumulado hasta hoy** (precursor) con sesgo de sensor → falsos positivos/negativos reales, φ<1. Ahorro predictivo 2.3×→**1.6×** |
| 2.2 | El índice de instancia `ti` se desincroniza entre brazos (el preventivo renueva más) → el CRN acopla solo la 1ª instancia, no la secuencia de renovaciones; "~80% reducción de varianza" no medido | **CRÍTICO** | **documentado** (§5): el CRN acopla la física por-vehículo y la 1ª instancia; la afirmación de varianza se retira hasta medirla |
| 2.3 | Agotar `max_instances` terminaba el loop **sin censurar** → pérdida de eventos asimétrica entre brazos | ALTO | **✓ corregido** (emite censura al agotar; tope subido a 80) |
| 2.4 | EUAC: "mant anual = VPN/años" mezclaba descontado con promedio lineal | ALTO | **✓ corregido** (anualidad equivalente VPN×CRF) |
| 2.5 | Descuento VPN `1/(1+r)^(t/365)`; acumulación al día real del flujo; CRF/EUAC; gate IFR | ok | ✓ verificado |
| 2.6 | Detección de estabilización ancla en el último año simulado (finito), no en la asíntota; constantes mágicas | MEDIO | documentado (§5; sensibilidad a `tol` pendiente) |
| 2.7 | Costo de programa no escala por vehículos onboardeados (stagger) → conservador para el ahorro | MEDIO | documentado (sesgo en contra del preventivo, no fatal) |
| 2.8 | Salvamento EUAC con constantes (0.6, 15, 0.05) sin cita | MEDIO | documentado (parametrizable; sensibilidad pendiente) |
| 2.9 | Break-even por primer cruce podía capturar un transitorio | menor | **✓ corregido** (primer cruce **sostenido**) |
| 2.10 | Empate `pday==fday` se contaba como preventivo (pro-preventivo) | menor | **✓ corregido** (empate ⇒ falla, conservador) |

## 3. Literatura + sustento físico

**Métodos: todos el estándar aceptado** (citas verificadas con URLs reales):
- Weibull/Cox con censura+truncamiento (Emura & Michimae 2022; Balakrishnan & Mitra 2012).
- Reemplazo por edad/CBM, renovación-recompensa (Barlow-Proschan SIAM; Alaswad & Xiang 2017 RESS).
- Horizonte finito no-estacionario (Jiang 2009 RESS; Ponchet et al. 2011).
- Riesgos competitivos: hazard causa-específico + CIF (Fine-Gray 1999; Austin & Fine 2017).
- PoF + damage-clock + recuperación de parámetros (Pecht & Gu 2009; Duchesne & Lawless 2000; SBC Talts 2018).
- RUL Wiener/Gamma por first-passage-time (Si et al. 2011 EJOR).

**Pitfalls a atender (documentados como límites):**
1. **Circularidad de datos sintéticos** (el más importante): recuperar parámetros del **mismo** modelo prueba self-consistencia del estimador/código, **no fidelidad al mundo real**. Mitigación: generar bajo mecanismos **mal-especificados** (otra ley de daño, covariable omitida, cola pesada) y validar contra datos de campo separados. → trabajo futuro antes de producción.
2. **Reparable vs no-reparable**: Weibull de una falla es incorrecto para fallas recurrentes del **mismo** activo (Ascher-Feingold). Aquí se ajusta sobre **instancias de componente** (cada balata es una pieza nueva, renovación q=0) — el encuadre correcto. La recurrencia por posición se modela como renovación, no como Weibull repetida. ✓ coherente.
3. **Renovación-recompensa es horizonte ∞**; en horizonte finito la política óptima es no-estacionaria (citado Jiang 2009). Usamos el T\* estacionario como aproximación; el efecto fin-de-horizonte está pendiente de incorporar (DP backward induction).
4. **Competing risks**: no usar 1−KM (sobreestima). Usamos `status=mode_id` causa-específico. ✓
5. **RUL por first-passage-time, no umbral−media**; para intervalos de RUL (no solo el punto) falta el FPT/efectos aleatorios.
6. **MLE Weibull con pocas fallas sesga β** (se vio en battery β̂≈1.02): el IC bootstrap + la regla de materialidad lo contienen, pero conviene corrección de sesgo/priors en producción.

**Sustento físico: 6/7 valores correctos; 1 corregido.**
- **✓ corregido**: derate por altitud — el umbral de 1000 m era muy bajo (el turbo mantiene potencia hasta ~1500 m; Cummins ~1524 m). Subido a **1500 m** y re-etiquetado de "medido" a "típico/calibrable".
- Nota menor: el C_rr SmartWay 0.0063 es el borde optimista (fleet-average típico ~0.0065); defendible.
- CdA 6.3 m², BSFC 182–220 g/kWh, pendiente 6%, FMCSA 4/32″–2/32″, Gay-Lussac: **correctos y bien atribuidos**.

---

## 4. Impacto de las correcciones en los resultados

| Magnitud | Antes (con defectos) | Después (corregido) |
|---|---|---|
| Ahorro predictivo a 2 años | ~59 M MXN (φ≈1, oráculo) | **~33 M MXN** (CBM honesto, φ<1) |
| Predictivo vs calendario | ~2.3× | **~1.6×** |
| Battery (β≈1) | rechazada | rechazada (sin cambio) |
| Estabilización de la distribución | ~1 año | ~1.3 años (sin cambio cualitativo) |
| Eventos en la cola (max_instances) | pérdida silenciosa | censurados correctamente |

La dirección de las conclusiones se mantiene (el preventivo paga dentro de la ventana productiva
para componentes de desgaste con falla cara; IFR rehúsa donde β≈1), pero las **magnitudes ahora son
honestas y defendibles**.

---

## 5. Límites declarados (antes de pruebas más sofisticadas)

1. **CRN parcial**: acopla la física por-vehículo y la primera instalación; tras renovaciones, los
   brazos divergen en la realización Weibull. La reducción de varianza de la diferencia **debe
   medirse** (correr con/sin CRN sobre múltiples semillas), no afirmarse.
2. **Circularidad**: la recuperación de parámetros valida estimador+código, no el mundo real. Falta
   validación bajo mis-especificación y contra datos de campo.
3. **Horizonte finito**: T\* estacionario como aproximación; falta la política no-estacionaria.
4. **CBM idealizado**: el precursor observado es daño-fracción + sesgo de sensor; un CBM de
   producción usaría el **modelo de degradación ajustado a las señales reales** de `Diagnostics`
   (ΔP, blowby, SoH) con su propia incertidumbre y lead time.
5. **Optimización**: NelderMead funciona (recuperación ±5–8%) pero LBFGS+gradiente sería más robusto
   con muchos grupos; bootstrap a nboot≥500 para una decisión IFR de grado producción.

---

## 6. Conclusión

La base está **auditada y las correcciones que cambian conclusiones, aplicadas**. La matemática
central es correcta, los métodos son el estándar de la literatura, y los datos sintéticos tienen
sustento físico verificado. Con los límites de §5 declarados, la implementación es una base sólida
para pruebas más sofisticadas (CBM sobre señales reales de degradación, validación bajo
mis-especificación, política no-estacionaria, costos reales del cliente).

*Auditores: matemática de confiabilidad, economía/simulación, literatura+física (3 agentes
independientes). Hallazgos verificados analíticamente y, donde aplica, re-ejecutando los tests.*
