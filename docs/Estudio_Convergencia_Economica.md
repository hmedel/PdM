# Estudio de convergencia económica — sin preventivo vs con preventivo

**¿Cuándo y en cuánto tiempo se estabiliza la distribución de fallas, y cuándo el mantenimiento
preventivo paga dentro de la vida productiva del camión?** Estudio contrafactual dinámico sobre la
misma flota física (números aleatorios comunes), que extiende el `Estudio_Ahorro` (forma cerrada
estática) a una simulación de horizonte finito con descuento.

Versión 1.0 — Junio 2026. Código: `run_economics.jl` + `src/decision/{policy,economics}.jl` +
`src/sim/life_process.jl`.

---

## 1. Diseño: el gemelo contrafactual (CRN)

Se simula la física **una sola vez** (`LifeProcess`): cada camión-agente opera en su corredor,
acumula daño y tiene umbrales de falla Θ pre-sorteados (Weibull). La capa de **política** (`Policy`)
es un post-procesador determinista sobre ese sustrato — números aleatorios comunes (Glasserman & Yao
1992): los brazos comparten la **física por-vehículo y la primera instalación** (tras renovaciones
divergen en la realización Weibull; ver caveat en `Auditoria_Tecnica.md` §5.1). El acoplamiento
reduce la varianza de la diferencia (magnitud a **medir** con/sin CRN, no afirmada).

- **Reactivo** (run-to-failure): cada pieza corre hasta fallar; falla = correctiva (c_f, a menudo en
  ruta). Es la línea base "sin preventivo".
- **Preventivo por edad T\***: reemplazo al alcanzar la edad óptima (o falla, lo que ocurra primero).
- **Predictivo (RUL)**: usa la condición (vida remanente observada con error) para reemplazar
  `buffer` horas antes de la falla.

La estimación de (β, γ, η0) se hace **del mundo reactivo** (las fallas que se observan sin
preventivo), no del oráculo — como en la realidad.

---

## 2. Matemática

### 2.1 Costo de largo plazo (renovación-recompensa)
Barlow & Proschan (1965); Jardine & Tsang (2013): $C = E[\text{costo/ciclo}]/E[\text{duración/ciclo}]$.
Reactivo $C_{\text{rtf}}=c_f/\text{MTTF}$; preventivo $C^\star=\min_T \frac{c_pR(T)+c_f[1-R(T)]}{\int_0^T R}$.

### 2.2 Horizonte finito con descuento (VPN)
El peso de un peso ahorrado decae con el tiempo: factor $1/(1+r)^{t/365}$, $r=12\%$ anual (costo de
capital de flota MX). El costo acumulado descontado de cada brazo es
$$C_{\text{arm}}(t)=\sum_{\text{eventos } e:\,t_e\le t}\frac{\text{costo}_e}{(1+r)^{t_e/365}}.$$
En horizonte finito la política óptima es **no estacionaria** (Jiang et al., RESS 2009): el T\*
ideal depende de cuánto le queda de vida al camión.

### 2.3 Ahorro neto y break-even
$$\text{Ahorro}(t)=C_{\text{rtf}}(t)-\big[C_{\text{prev}}(t)+C_{\text{programa}}(t)\big],$$
con $C_{\text{programa}}$ = hardware/onboarding por unidad + cuota mensual de plataforma. El
**break-even** es el primer $t$ con Ahorro$(t)>0$.

### 2.4 Estabilización de la distribución (transitorio de renovación)
La tasa de fallas de una flota **joven** arranca baja (todo censurado) y sube hasta el régimen
estacionario del proceso de renovación. Por el teorema de renovación / Blackwell, la tasa converge
a su valor asintótico con un **transitorio** (arXiv 2401.12265, costo de mantenimiento en vida
finita). Se mide la tasa de fallas/mes/unidad y se detecta cuándo entra (y se queda) en ±15% de su
régimen del último año.

### 2.5 Regla IFR + materialidad
Preventivo solo si el IC95 de β **excluye 1** (desgaste confirmado) **y** el ahorro es material
($s_{\text{prev}}\ge 3\%$). Si no, se rehúsa (T\*→∞). Es lo que pasa con `battery` (β≈1).

### 2.6 Vida económica (EUAC)
Costo Anual Uniforme Equivalente vs vida de servicio L: recuperación de capital
$(P-\text{salvamento}/(1+r)^L)\cdot\text{CRF}(r,L)$ + mantenimiento anualizado; el mínimo es la vida
económica (caso de flota cisterna, ScienceDirect 2023; tractocamión line-haul ~7–8 años).

---

## 3. Resultados (120 vehículos, 7 años, descuento 12%)

**(1) Línea base reactiva — recuperación desde las fallas observadas:**

| comp | β̂ (IC95) | γ̂ | ¿preventivo? | T\* |
|---|---|---|---|---|
| brake_pad | 2.32 [2.29,2.36] | −0.99 | sí | 558 h |
| dpf | 2.00 [1.97,2.11] | −0.72 | sí | 1485 h |
| scr | 2.78 [2.61,2.96] | −0.39 | sí | 2035 h |
| battery | 1.02 [1.01,1.04] | −0.45 | **NO (IFR)** | — |

**(2)+(3) Convergencia y economía:**
- **La distribución se estabiliza ~año 1** (tasa de fallas/mes/unidad: 1.20 a los 6 meses → ~1.45 en
  régimen), dominada por las balatas (desgaste rápido). **Dentro de la ventana productiva de 2 años.**
  Los componentes lentos (DPF/SCR) tardan más en alcanzar su régimen — matiz que importa si la
  ventana fuera más corta.
- **Break-even:** preventivo por edad ~día 120 (4 meses); predictivo ~día 30 (1 mes). El c_f ≫ c_p
  (ρ≈8–9) hace que el programa se pague rápido.
- **Ahorro neto VPN a 2 años:** ~21 M MXN (edad) / ~33 M MXN (predictivo) para 120 unidades. El
  **predictivo captura ~1.6× el ahorro** del calendario — CBM honesto sobre el daño OBSERVADO
  (precursores de `Diagnostics`) con sesgo de sensor (falsos positivos/negativos reales), captura
  una fracción φ<1 del techo. *(Antes de la auditoría, una versión que "miraba el futuro" daba ~2.3×;
  era un artefacto — ver `Auditoria_Tecnica.md` §2.1.)*
- **EUAC:** mantenimiento/unidad cae de ~287k (reactivo) a ~188k MXN/año (preventivo), ~35%.

**Lectura:** para los componentes de **desgaste y falla cara**, la distribución estabiliza rápido
(~1 año) y el preventivo paga dentro de la vida productiva. Donde la falla es aleatoria (battery,
β≈1), la disciplina IFR lo rehúsa. La palanca es el predictivo (condición), no solo el calendario.

> Sensibilidad: el break-even y la estabilización dependen de la mezcla de flota (proporción de
> componentes de desgaste rápido vs lento), de ρ=c_f/c_p y de la tasa de descuento. Reproducible con
> `julia run_economics.jl <n> <días> <semilla>`.

---

## 4. Referencias

- Barlow, R. E. & Proschan, F. (1965). *Mathematical Theory of Reliability.* Wiley.
- Jardine, A. K. S. & Tsang, A. H. C. (2013). *Maintenance, Replacement, and Reliability.* CRC.
- Jiang, R. et al. (2009). *Optimal sequential age replacement for a finite-time horizon.* RESS.
- Glasserman, P. & Yao, D. (1992). *Guidelines and Guarantees for Common Random Numbers.* Mgmt. Sci.
- Wu, S. et al. (2016). *Optimisation of maintenance policy under parameter uncertainty.* IISE Trans.
- *Maintenance cost & availability in a finite life cycle…* arXiv:2401.12265 (transitorio de renovación).
- *Optimal service lives of trucks under EUAC…* ScienceDirect S2590198223001276 (2023).
