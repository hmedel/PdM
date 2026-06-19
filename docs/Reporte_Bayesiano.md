# Reporte bayesiano — estimación de la distribución de vida y convergencia

**Qué muestra:** cómo la engine estima la distribución de vida de cada componente con un modelo
**bayesiano jerárquico** (Turing.jl), validado contra **verdad conocida** (datos sintéticos del
simulador), a tres niveles (**componente / vehículo / flota**), su **convergencia** al acumular datos,
el paso de **solo-fallas → fallas+preventivo**, y la evolución de la **ecuación maestra** de la flota.

Generado por `run_bayes_report.jl` (figuras en `figures/`). El ajuste bayesiano es **offline** (p. ej.
1×/día); su costo en segundos no afecta el servicio en vivo, que solo consume el posterior ya ajustado.

Versión 1.0 — 2026-06-18. Cruza con `Fundamentos_Adenda_Implementacion_Auditoria.md`.

---

## 0. El puente físico → Weibull (de dónde sale la distribución)

La vida **no se postula**: emerge de la física. El daño acumula a tasa dependiente del uso y la
severidad de ruta `z`, y la pieza falla al cruzar un umbral aleatorio:

$$D(t)=\sum_{\text{viajes}} \text{engine\_h}\cdot e^{\kappa z}\cdot \xi,\qquad \text{falla cuando } D\ge \Theta\sim \text{Weibull}(\beta,\eta_{\text{ref}}).$$

Por construcción, la vida en horas-motor es

$$T\sim \text{Weibull}\big(\beta,\ \eta(z)\big),\qquad \eta(z)=\eta_{\text{ref}}\,e^{-\kappa z}.$$

⇒ La **forma** $\beta$ y la **pendiente AFT** $\gamma=-\kappa$ son verdad conocida y **recuperable**. La
heterogeneidad (montaña vs llano) no se postula: viene de `z`. Esto es lo que el estimador debe recobrar.

---

## 1. Verosimilitud Weibull-AFT (la ecuación maestra de la estimación)

Cada observación $i$ es $(t_i,a_i,d_i,z_i)$: vida `exit_age` $t_i$, edad de entrada `entry_age` $a_i$
(**truncamiento izquierdo**), indicador de falla $d_i\in\{0,1\}$ (0 = **censura derecha**), severidad
$z_i$. Con $\eta_i=\eta_0\,e^{\gamma z_i}$, la log-verosimilitud por observación es

$$\ell_i = d_i\Big[\log\beta-\beta\log\eta_i+(\beta-1)\log t_i\Big]-\Big(\tfrac{t_i}{\eta_i}\Big)^{\beta}+\Big(\tfrac{a_i}{\eta_i}\Big)^{\beta}.$$

El término $+(a_i/\eta_i)^\beta$ condiciona en que la pieza sobrevivió hasta $a_i$ (truncamiento). Para
censura ($d_i=0$) solo queda la supervivencia $\log S(t_i)=-(t_i/\eta_i)^\beta$. Esta es la base tanto
del ajuste frecuentista (`Survival.fit_grouped`) como del bayesiano (`BayesEstimator`).

---

## 2. Posterior bayesiano y jerarquía (partial pooling)

Bayes: $p(\theta\mid \text{datos})\propto \mathcal L(\text{datos}\mid\theta)\,p(\theta)$, con
$\theta=(\beta,\eta_0,\gamma,\sigma_v,\{b_v\})$. Priors débilmente informativos:

$$\beta\sim \mathcal N_{[0.2,12]}(2,1),\quad \log\eta_0\sim \mathcal N(\log\bar t,1.5),\quad \gamma\sim\mathcal N(0,1),\quad \sigma_v\sim \mathcal N^+(0,0.15).$$

**Jerarquía (3 niveles):** la escala por vehículo es

$$\eta_{v}=\eta_0\,\exp(\gamma\,z_v+\sigma_v\,b_v),\qquad b_v\sim\mathcal N(0,1).$$

- **Flota** = hiperparámetros compartidos $(\beta,\eta_0,\gamma)$ — todos los vehículos los informan.
- **Vehículo** = $\eta_v$ (su ruta $z_v$ + efecto residual $b_v$).
- **Componente** = la forma $\beta$ y escala $\eta_0$ del componente.

El posterior se obtiene por **MCMC (NUTS/HMC)** con init data-driven (momentos) y priors neutros.
Resultado en datos sintéticos: $\sigma_v$ es **pequeño** (≈0.02–0.06 según componente — brake_pad ~0.06,
battery ~0.03): la **ruta** ($z$, vía $\gamma$) explica la **mayor parte** de la heterogeneidad entre
vehículos, con un **pequeño frailty residual** no nulo. (Un prior estrecho lo sobre-encoge a ~0.03; el
prior neutro revela el residual real.) Confirma el espíritu del hallazgo del proyecto —la correlación es
sobre todo de ruta, recuperable vía $\gamma$— matizado: hay un residual por vehículo del orden de 6%.

### Recuperación de parámetros vs verdad
![β y γ por componente](../figures/1_post_params_brake_pad.png)
![dpf](../figures/1_post_params_dpf.png)
![battery](../figures/1_post_params_battery.png)

El posterior **cubre la verdad** en componentes de desgaste (brake_pad β≈2.3, dpf β≈2.0) y en battery
el posterior de β se concentra en ~1 (falla casi aleatoria) — por eso la regla IFR rehúsa preventivo.

---

## 3. Estimación de la distribución a 3 niveles

La **predictiva posterior** mezcla la incertidumbre de parámetros + la aleatoriedad intrínseca:

$$p(\tilde t\mid \text{datos},z)=\int \text{Weibull}\big(\tilde t\mid\beta,\eta_0 e^{\gamma z}\big)\,p(\beta,\eta_0,\gamma\mid\text{datos})\,d\theta.$$

Cada figura `2_dist_<componente>.png` tiene tres paneles:
- **Componente**: distribución de vida a severidad media $\bar z$ (predictiva azul vs observado gris vs Weibull verdad rojo).
- **Vehículo**: corrimiento AFT — ruta suave ($\eta$ grande, vida larga) vs severa ($\eta$ chica, vida corta).
- **Flota**: marginal sobre la población de rutas (mezcla de las predictivas por vehículo).

Se generan para varios componentes (β diverso): brake_pad (β≈2.3), dpf (≈2.0), scr (≈2.6), egr (≈1.8),
air_system (≈1.7), battery (≈1.0). Ejemplos:

**brake_pad** (desgaste marcado): ![](../figures/2_dist_brake_pad.png)
**scr** (desgaste, β alto): ![](../figures/2_dist_scr.png)
**battery** (β≈1, casi aleatoria): ![](../figures/2_dist_battery.png)
**egr**: ![](../figures/2_dist_egr.png)

La predictiva (azul) se ajusta al histograma observado (gris) y a la Weibull verdadera (rojo punteado)
en todos los niveles. El nivel **vehículo** muestra cuánto cambia la vida esperada por la severidad de la
ruta; el nivel **flota** es la mezcla que ve la operación agregada.

---

## 4. Convergencia: el posterior se estrecha al acumular datos

Bernstein–von Mises: con $N$ creciente el posterior tiende a normal alrededor de la verdad y su
dispersión cae como $1/\sqrt N$:

$$p(\theta\mid \text{datos})\ \xrightarrow{N\to\infty}\ \mathcal N\!\big(\hat\theta,\ \tfrac1N I(\theta)^{-1}\big),\qquad \text{ancho IC}\propto N^{-1/2}.$$

![convergencia](../figures/3_convergencia.png)

A la izquierda, el posterior de $\beta$ se concentra sobre la verdad conforme se acumulan fallas; a la
derecha, el ancho del IC95% sigue la referencia $1/\sqrt N$. **Implicación operativa:** con poca historia
el IC de $\beta$ es ancho ⇒ la regla IFR ($\beta_{lo}>1$) **rehúsa** preventivo (conservador y honesto)
hasta tener evidencia suficiente.

---

## 5. Solo-fallas (run-to-failure) → fallas + preventivo

Cuando se introduce el preventivo, las vidas largas se **censuran** en $T^\star$ (se reemplaza antes de
fallar): hay **menos fallas observadas** y más censura. La verosimilitud (§1) usa ambas, así que la
Weibull **sigue siendo recuperable** desde datos censurados — solo que con menos información por unidad.

![fallas vs preventivo](../figures/4_fallas_vs_preventivo.png)

Gris = mundo run-to-failure (muchas fallas, posterior estrecho); turquesa = régimen preventivo (pocas
fallas, resto censurado en $T^\star$, posterior más ancho pero centrado en la verdad). Es la trayectoria
real de una flota: empieza atendiendo fallas y converge al régimen preventivo sin perder el modelo.

### Decisión: intervalo óptimo y regla IFR
$$C(T)=\frac{c_p\,R(T)+c_f\,[1-R(T)]}{\int_0^T R(u)\,du},\qquad T^\star=\arg\min_T C(T).$$
Preventivo **solo si** $\beta_{lo}>1$ (IC excluye 1, desgaste real) **y** el ahorro $s_{\text{prev}}\ge
s_{\min}$. RUL de forma cerrada para "cuándo intervenir":
$$\mathrm{RUL}(t)=\mathbb E[T-t\mid T>t]=\eta\,e^{w}\,\Gamma\!\big(1+\tfrac1\beta\big)\,Q\!\big(1+\tfrac1\beta,w\big)-t,\quad w=(t/\eta)^\beta.$$

---

## 6. Ecuación maestra: renovación de la flota → estado estacionario

Cada componente es un **proceso de renovación**: falla, se reemplaza, vuelve a envejecer. La **ecuación
de renovación** (forma integral de la ecuación maestra / Chapman–Kolmogorov para el proceso de conteo)
para la función de renovación $m(t)=\mathbb E[N(t)]$ es

$$m(t)=F(t)+\int_0^t m(t-x)\,dF(x).$$

Dos consecuencias asintóticas que la simulación reproduce:

1. **Teorema elemental de renovación:** la tasa de falla de la flota converge a $1/\mu$ con
   $\mu=\mathbb E[T]=\eta\,\Gamma(1+1/\beta)$ (MTTF).
   ![tasa de falla](../figures/5_ecuacion_maestra_tasa.png)
2. **Teorema clave de renovación:** la **distribución de edades** de la flota converge al equilibrio
   $$f_A(a)=\frac{S(a)}{\mu}=\frac{1-F(a)}{\mu}.$$
   ![distribución de edades](../figures/5_ecuacion_maestra_edades.png)

La distribución de edades arranca concentrada (flota nueva) y se relaja al equilibrio (~año 1, dominado
por los componentes de vida corta como balatas). Este es el sustrato sobre el que la economía calcula el
break-even y el EUAC: el régimen estacionario es donde el ahorro del preventivo se estabiliza.

### Los tres niveles de la ecuación maestra
- **Componente:** un proceso de renovación con su $(\beta,\eta)$ → su tasa $1/\mu_c$ y equilibrio $S_c(a)/\mu_c$.
- **Vehículo:** superposición de los procesos de sus componentes (cada uno con su $\eta_v$ por ruta).
- **Flota:** superposición sobre todos los vehículos → la tasa agregada y la mezcla de edades de arriba.

---

## 7. Tiempo a estabilidad y traducción a ahorro de dinero

Dos preguntas operativas: **¿cuándo se estabiliza la flota?** y **¿cuánto dinero se ahorra?**

### 7.1 Tiempo a estabilidad
La tasa de falla de la flota sube desde el transitorio (flota nueva, pocas fallas) hasta el régimen
estacionario de renovación. `Economics._stabilization` marca el primer mes en que la tasa entra (y se
mantiene) dentro de tolerancia de su valor final. En la corrida de referencia (60 unidades, 4 años):
**se estabiliza ≈ mes 13** (~año 1), dominado por los componentes de vida corta (balatas).

![tiempo a estabilidad](../figures/6_estabilizacion.png)

Rojo = reactivo (run-to-failure) → ~1.9 fallas/unidad·mes en estado estacionario. Verde = con preventivo/
predictivo → ~0.65. **La brecha son las fallas en ruta evitadas** — el origen del ahorro.

### 7.2 Traducción a ahorro de dinero
El costo acumulado descontado (VPN, tasa $r$) de cada política:
$$\text{VPN}(t)=\sum_{\text{eventos } \le t} \frac{c_{\text{evento}}}{(1+r)^{t_{\text{evento}}/365}},\qquad
\text{ahorro}(t)=\text{VPN}_{\text{reactivo}}(t)-\big[\text{VPN}_{\text{predictivo}}(t)+\text{programa}(t)\big].$$
El **break-even** es el primer mes con ahorro positivo sostenido (incluye el costo del programa: hardware
+ cuota mensual). En la referencia: **break-even ≈ mes 1**, **ahorro VPN ≈ 46.7M MXN** a 4 años
(~**195k MXN/unidad·año**). El correctivo en ruta cuesta ~$c_f/c_p\approx 4\times$ el preventivo en taller
(ancla TMC/FleetNet), por eso el preventivo paga casi de inmediato.

![ahorro económico](../figures/6_ahorro.png)

Rojo = costo acumulado reactivo; verde = predictivo (+ programa). La brecha creciente es el ahorro. La
**vida económica del camión** (EUAC) baja al reducir el costo de mantenimiento anual (`euac_curve`).

### 7.3 Ahorro desglosado por componente
Corriendo la economía componente-por-componente (sin el costo de programa, que es overhead de flota) se
ve **de dónde sale el ahorro**:

![ahorro por componente](../figures/6_ahorro_por_componente.png)

| Componente | Ahorro (k MXN/unidad·año) | Por qué |
|---|---|---|
| brake_pad | ~125 | vida corta + muchas fallas + $c_f/c_p$ alto → domina (~63%) |
| dpf | ~39 | desgaste, falla cara de escape |
| scr | ~27 | desgaste, derate = varado |
| oil, turbo, fuel, egr, tire… | ~0–2 c/u | vida larga → pocas fallas en el horizonte → poco que ahorrar |
| **battery** | **0** | β≈1 (aleatoria) → **IFR rehúsa preventivo** ($T^\star=\infty$): correctamente, no se invierte |

El total del desglose (~198 k/unidad·año) ≈ el agregado (~195 k) — la diferencia es el costo del programa
(hardware+cuota). **Conclusión accionable:** el preventivo se justifica sobre todo en **balatas, DPF y SCR**;
en battery NO (es aleatoria). Los de vida larga rendirán más ahorro con un horizonte/historial mayor.

> Caveat honesto: estos montos usan β/η/costos **[estimación]** (no datos reales de flota). El valor del
> ejercicio es el MÉTODO (cuándo estabiliza, cómo se traduce a VPN/break-even); los números absolutos se
> recalibran cuando entre el historial real de `maintenance_records` de Tracker.

---

## 8. Resumen de ecuaciones usadas

| # | Ecuación | Rol | Código |
|---|---|---|---|
| 0 | $T\sim\text{Weibull}(\beta,\eta_{\text{ref}}e^{-\kappa z})$ | puente físico→vida (verdad) | `DamageModels`, `LifeProcess` |
| 1 | $\ell_i$ Weibull-AFT (censura+truncamiento) | verosimilitud | `Survival`, `BayesEstimator` |
| 2 | $p(\theta\mid D)\propto \mathcal L\,p(\theta)$ + jerarquía $\eta_v$ | posterior bayesiano | `BayesEstimator` |
| 3 | predictiva posterior $p(\tilde t\mid D,z)$ | distribución estimada | `predict_lifetimes` |
| 4 | $\text{ancho IC}\propto N^{-1/2}$ (Bernstein–von Mises) | convergencia | — |
| 5 | $C(T)$, $T^\star$, regla IFR ($\beta_{lo}>1$) | decisión preventiva | `Decision` |
| 6 | $\mathrm{RUL}(t)$ forma cerrada | cuándo intervenir | `RUL` |
| 7 | $m(t)=F+\!\int m\,dF$; $1/\mu$; $f_A=S/\mu$ | ecuación maestra / renovación | `LifeProcess`, `Economics` |
| 8 | $\text{VPN}(t)$, ahorro, break-even, estabilización | tiempo a estable + ahorro \$ | `Economics` |
