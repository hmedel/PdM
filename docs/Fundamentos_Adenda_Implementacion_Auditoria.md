# Adenda a los Fundamentos Matemáticos — congruencia con la implementación auditada

**Propósito:** reconciliar `Fundamentos_Matematicos_Mantenimiento_Predictivo.md` (derivaciones de
diseño) con el sistema realmente **implementado y auditado**. Registra (1) las correcciones que la
auditoría confirmó, (2) la matemática **nueva** que el proyecto introdujo y que los fundamentos
originales no cubrían, y (3) los **caveats de rigor** necesarios para que las afirmaciones sean
congruentes. Es el documento de verdad sobre "qué matemática usa el código y por qué es correcta".

Versión 1.0 — Junio 2026. Cruza con `Auditoria_Tecnica.md`, `Estudio_Convergencia_Economica.md`,
`Sustento_Fisico_Telemetria.md`, `Arquitectura_Unificada_Merge.md`.

---

## 1. Correcciones matemáticas confirmadas por auditoría (3 agentes independientes)

Las **cuatro fórmulas centrales** se verificaron correctas:

1. **Verosimilitud Weibull-AFT** con censura por la derecha y truncamiento por la izquierda
   (`survival.jl`):
   $$\ell_i = d_i\big[\log\beta - \beta\log\eta_i + (\beta-1)\log t_i\big] - (t_i/\eta_i)^\beta + (a_i/\eta_i)^\beta,\quad \eta_i=\eta_0\,e^{\gamma x_i}.$$
   El signo `+(a/\eta)^\beta` del truncamiento es correcto: la contribución condicionada es
   $f(t)/R(a)$ (falla) o $R(t)/R(a)$ (censura), cuyo log es $d\log h(t) - H(t) + H(a)$ con
   $H(t)=(t/\eta)^\beta$. **Requisito implícito (documentar):** `entry_age`/`exit_age` son edades de
   la pieza desde su instalación, no tiempo-en-observación.

2. **RUL de forma cerrada** (`rul.jl`): $E[T\mid T>t]=\eta\,e^{w}\,\Gamma(1+1/\beta)\,Q(1+1/\beta,w)$,
   $w=(t/\eta)^\beta$, con $Q$ la gamma incompleta **SUPERIOR** regularizada (no la inferior — error
   grueso evitado). Límite $t\to 0 \Rightarrow$ MTTF $=\eta\Gamma(1+1/\beta)$ ✓.
   **Corregido:** guarda anti-overflow para $w>100$ (asíntota $\mathrm{MRL}\approx 1/h(t)=\eta^\beta/(\beta t^{\beta-1})$).

3. **Tasa de costo de reemplazo por edad** (`optimal_interval.jl`):
   $C(T)=\dfrac{c_p R(T)+c_f[1-R(T)]}{\int_0^T R}$ (renovación-recompensa). Simpson con $n$ forzado par.
   **Corregido:** óptimo en la frontera superior (β≤1, IFR) ahora devuelve $T^\star\to\infty$ con tasa
   $c_f/\mathrm{MTTF}$, no un $T^\star$ finito espurio.

4. **Regla IFR + materialidad** (`Decision.decide`): preventivo solo si $\beta_\text{lo}>1$ (IC
   bootstrap excluye 1) **y** ahorro $s_\text{prev}\ge s_\min$. Estadísticamente sólido y conservador.
   **Corregido:** el bootstrap arranca cada réplica desde `x0` (no desde el óptimo full-sample) para
   no subestimar la varianza de $\beta$ — `\beta_\text{lo}` gobierna toda la decisión. Producción:
   $n_\text{boot}\ge 500$; LBFGS+gradiente en vez de NelderMead (gradiente cerrado disponible).

---

## 2. Matemática NUEVA introducida (no en los fundamentos originales)

### 2.1 Puente physics-of-failure → Weibull recuperable (el "damage clock")
La vida no se postula: emerge de la física. El daño acumula $D(t)=\sum \text{engine\_h}\cdot e^{\kappa_c z_c}\cdot\xi$
(ley `DamageModels`); la falla ocurre cuando $D$ cruza un umbral $\Theta\sim\text{Weibull}(\beta_c,\eta_{\text{ref},g})$.
Por construcción, la vida en horas-motor es $T\sim\text{Weibull}(\beta_c,\eta_{\text{ref},g}e^{-\kappa_c z_c})$:
la **forma $\beta$ y la pendiente AFT $\gamma=-\kappa$** son verdad conocida y **recuperable**, mientras
la heterogeneidad (corredor, carga) es física. Es la escala de tiempo basada en uso (Duchesne &
Lawless 2000) — estándar aceptado.

### 2.2 Precursores: mapa f→señal y CBM por condición
`Precursors` define, por componente, la señal física observable como función monótona de la fracción
de daño $f=(D-D_0+a_0)/\Theta\in[0,1]$, con un umbral de alarma físico $\Rightarrow f^\star=(\text{alarma}-\text{nuevo})/(\text{falla}-\text{nuevo})$.
El **CBM honesto** dispara cuando $f\cdot(\text{sesgo de sensor})\ge f^\star$: observa el daño HASTA
hoy (no el futuro), con sesgo de medición $\Rightarrow$ falsos positivos/negativos reales, capturando
una fracción $\varphi<1$ del techo $1-1/\rho$ (no $\varphi\approx1$ como una versión oracular previa,
que la auditoría detectó como artefacto). Es la fuente ÚNICA degradación→señal: el mismo $f$ causa la
falla, genera la telemetría y dispara el CBM.

### 2.3 Economía de horizonte finito (nueva respecto a la forma cerrada estática)
- **VPN con descuento** $1/(1+r)^{t/365}$, $r=12\%$; costo acumulado descontado por brazo.
- **Break-even sostenido**; **ahorro neto** = reactivo − (preventivo + costo de programa).
- **EUAC**: $\text{CRF}(r,L)=\dfrac{r(1+r)^L}{(1+r)^L-1}$; mantenimiento anualizado = VPN$\times$CRF
  (coherente con la recuperación de capital, no VPN/años).
- **CRN** (Glasserman-Yao): post-procesador determinista sobre el mismo sustrato; reducción de
  varianza **medida** (correlación de costo/vehículo $r\approx0.97$), no afirmada.
- **Estabilización**: transitorio de renovación (Blackwell); la tasa de fallas/mes/unidad converge a
  su régimen (~1 año, dominado por desgaste rápido). Horizonte finito ⇒ política óptima no
  estacionaria (Jiang 2009) — usamos $T^\star$ estacionario como aproximación.

---

## 3. Caveats de rigor (para que las afirmaciones sean congruentes)

1. **Circularidad (el más importante).** Recuperar $(\beta,\gamma,\eta_0)$ de datos generados por el
   mismo modelo prueba la corrección del **estimador y el código** (self-consistencia), NO la fidelidad
   al mundo real. Validación pendiente: generar bajo mecanismos **mal-especificados** (otra ley de
   daño, covariable omitida, cola pesada) y contra datos de campo. (Talts et al. 2018, SBC.)
2. **Heterogeneidad no observada (frailty) sesga $\beta$.** Se verificó empíricamente: una frailty
   por vehículo $\sigma=0.30$ sesgó $\hat\beta$ **−17%** (aplana el hazard aparente). Por eso NO se
   incluyó: rompería la recuperación. La correlación entre componentes proviene de la severidad de
   ruta compartida $z$ (recuperable vía $\gamma$), no de una frailty. (Pitfall clásico: Vaupel 1979.)
3. **Reparable vs no-reparable.** El ajuste es sobre **instancias de componente** (cada balata es una
   pieza nueva; renovación $q=0$), no sobre el vehículo — encuadre correcto (evita el error
   Ascher-Feingold de usar Weibull para fallas recurrentes del mismo activo).
4. **Riesgos competitivos.** `status` es causa-específico (`mode_id`), no binario; no se usa $1-$KM
   (que sobreestima). Riesgos competitivos dependientes son no identificables sin supuesto de
   independencia (Tsiatis 1975) — explícito.
5. **RUL puntual, no intervalos.** $E[T\mid T>t]$ es un estimador puntual; intervalos de RUL rigurosos
   requieren first-passage-time (Inverse-Gaussian para Wiener) + efectos aleatorios (Si et al. 2011).
6. **MLE Weibull con pocas fallas sesga $\beta$** al alza (visto en battery $\hat\beta\approx1.02$);
   contenido por el IC bootstrap + materialidad, pero conviene corrección de sesgo/priors en producción.

---

## 4. Estado de congruencia

- Matemática central: **correcta y auditada**.
- Métodos: **estándar aceptado** de la literatura (ver `Auditoria_Tecnica.md` §3 con citas verificadas).
- Implementación ↔ derivaciones: **congruente**, con las correcciones de §1 aplicadas y los caveats de
  §3 declarados. Los "grados típico" del sustento físico son calibrables; los "medido/estándar" están
  citados.
- Pendiente de validación (no de corrección): circularidad bajo mis-especificación; política no
  estacionaria de horizonte finito; intervalos de RUL por FPT.
