---
title: "Marco matemático del mantenimiento predictivo de flota"
subtitle: "Una selección representativa del modelo de decisión"
date: "2026"
lang: es
---

El mantenimiento de una flota deja de ser una agenda de calendario y se vuelve una **decisión bajo
incertidumbre**: ¿cuándo intervenir cada componente para minimizar el costo total esperado? Las
siguientes ecuaciones resumen el **fundamento** de esa decisión. Son una muestra deliberadamente
breve —no el sistema completo— escogida para mostrar el rigor del enfoque.

---

## 1. El objetivo: minimizar el costo esperado de falla

La intervención no busca abaratar la refacción, sino reducir el **valor esperado** de lo que cuesta
una falla:

$$c_f \;=\; c_{\text{rep}} \;+\; c_{\text{inmov}} \;+\; P(\text{accidente}\mid\text{falla})\cdot c_{\text{accidente}} \;+\; P(\text{incumpl.})\cdot c_{\text{cumpl.}}$$

> Cada falla pesa por su **probabilidad y su consecuencia**: reparación, inmovilización en ruta,
> exposición a un accidente y a incumplimiento. El término dominante rara vez es la refacción.

---

## 2. La vida del componente: confiabilidad y riesgo

La vida útil de un componente se modela con una distribución de Weibull. Su **confiabilidad** (probabilidad
de seguir sano a la edad $t$) y su **tasa de riesgo instantánea** son:

$$R(t)=\exp\!\Big[-\big(t/\eta\big)^{\beta}\Big], \qquad\qquad h(t)=\frac{\beta}{\eta}\left(\frac{t}{\eta}\right)^{\beta-1}$$

> $\eta$ fija la escala de vida; $\beta$ la forma. La condición clave es $\beta>1$: **hay desgaste**
> —la falla se vuelve más probable con el uso (tasa de riesgo creciente)—. Es lo que hace que
> intervenir a tiempo tenga sentido.

---

## 3. Cuánta vida le queda: vida remanente esperada

Dada la edad actual $t$ de una pieza que sigue viva, su vida remanente esperada es:

$$\operatorname{RUL}(t)=\mathbb{E}\big[\,T-t \,\mid\, T>t\,\big]=\frac{1}{R(t)}\int_{t}^{\infty} R(s)\,ds$$

> Traduce el estado del activo en una cifra accionable: **cuánto le queda**, condicionado a que aún
> no ha fallado.

---

## 4. El momento óptimo de intervenir

Reemplazar a la edad $T$ tiene un costo esperado por unidad de tiempo (modelo clásico de reemplazo por
edad, Barlow–Proschan):

$$C(T)=\frac{c_p\,R(T)\;+\;c_f\,F(T)}{\displaystyle\int_{0}^{T} R(s)\,ds}\,,\qquad F(T)=1-R(T)$$

> $c_p$ = costo planeado, $c_f$ = costo de falla. Cuando hay desgaste ($\beta>1$), esta curva tiene un
> **mínimo interior único $T^\star$**: ni antes (desperdicio de vida útil) ni después (riesgo de falla).
> Ese $T^\star$ es la recomendación, y se desplaza con la condición real de cada activo.

---

## Nota

El marco anterior pertenece a la **teoría de confiabilidad clásica** y es de dominio público. El valor
diferencial del sistema —la estimación de los parámetros a partir de datos reales de operación, su
calibración, la incorporación de la señal de condición y la integración con la plataforma— es
**propietario** y queda fuera del alcance de este documento.

*Documento técnico de carácter ilustrativo. Las cifras y decisiones operativas se calibran con los datos de cada flota.*
