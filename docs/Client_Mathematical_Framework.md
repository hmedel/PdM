---
title: "Mathematical framework for predictive fleet maintenance"
subtitle: "A representative selection of the decision model"
date: "2026"
lang: en
---

Fleet maintenance stops being a calendar schedule and becomes a **decision under uncertainty**: when
should each component be serviced to minimize the total expected cost? The equations below summarize
the **foundation** of that decision. They are a deliberately brief sample —not the full system—
chosen to convey the rigor of the approach.

---

## 1. The objective: minimize the expected cost of failure

Intervention does not aim to make the part cheaper, but to reduce the **expected value** of what a
failure costs:

$$c_f \;=\; c_{\text{rep}} \;+\; c_{\text{immob}} \;+\; P(\text{crash}\mid\text{failure})\cdot c_{\text{crash}} \;+\; P(\text{non-compl.})\cdot c_{\text{compl.}}$$

> Each failure is weighted by its **probability and its consequence**: repair, roadside
> immobilization, exposure to a crash and to non-compliance. The dominant term is rarely the part.

---

## 2. Component life: reliability and risk

A component's useful life is modeled with a Weibull distribution. Its **reliability** (probability of
still being sound at age $t$) and its **instantaneous hazard rate** are:

$$R(t)=\exp\!\Big[-\big(t/\eta\big)^{\beta}\Big], \qquad\qquad h(t)=\frac{\beta}{\eta}\left(\frac{t}{\eta}\right)^{\beta-1}$$

> $\eta$ sets the life scale; $\beta$ the shape. The key condition is $\beta>1$: **there is wear**
> —failure becomes more likely with use (increasing hazard rate)—. That is what makes timely
> intervention worthwhile.

---

## 3. How much life remains: expected remaining useful life

Given the current age $t$ of a part still in service, its expected remaining life is:

$$\operatorname{RUL}(t)=\mathbb{E}\big[\,T-t \,\mid\, T>t\,\big]=\frac{1}{R(t)}\int_{t}^{\infty} R(s)\,ds$$

> It turns the asset's state into an actionable number: **how much is left**, conditioned on the part
> not having failed yet.

---

## 4. The optimal moment to intervene

Replacing at age $T$ has an expected cost per unit time (classical age-replacement model,
Barlow–Proschan):

$$C(T)=\frac{c_p\,R(T)\;+\;c_f\,F(T)}{\displaystyle\int_{0}^{T} R(s)\,ds}\,,\qquad F(T)=1-R(T)$$

> $c_p$ = planned cost, $c_f$ = failure cost. When there is wear ($\beta>1$), this curve has a
> **unique interior minimum $T^\star$**: neither too early (wasted useful life) nor too late (risk of
> failure). That $T^\star$ is the recommendation, and it shifts with each asset's real condition.

That minimum is not sought blindly: it is **characterized precisely** by the first-order condition

$$h(T^\star)\int_{0}^{T^\star} R(t)\,dt \;-\; F(T^\star) \;=\; \frac{c_p}{\,c_f-c_p\,}$$

> At the optimum, the **marginal risk** of continuing to operate exactly balances the **relative
> saving** of intervening, $c_p/(c_f-c_p)$. It is an equation to be solved, not a hunch.

![**The optimum, in practice.** Projected cumulative maintenance cost under four intervention policies, for a new and an aging fleet. Intervening at the optimal point —instead of waiting for failure (reactive) or following a fixed calendar— lowers total cost over the fleet's life. *(Illustrative figures; calibrated per fleet.)*](../figures/cost_by_policy.png){width=100%}

---

## Note

The framework above belongs to **classical reliability theory** and is in the public domain. The
system's differential value —estimating the parameters from real operating data, their calibration,
the incorporation of the condition signal, and the integration with the platform— is **proprietary**
and lies outside the scope of this document.

*Technical document for illustrative purposes. Figures and operational decisions are calibrated with each fleet's data.*
