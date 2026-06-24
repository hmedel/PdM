# The economic case for predictive fleet maintenance

### Why the return on predictive maintenance isn't in the parts, but in the expected cost of failure

*Technical whitepaper — PhAIMaT · Tracker / Predictive Maintenance (PdM)*

---

## Executive summary

The usual conversation about fleet maintenance revolves around spend on parts and labor. That's the
wrong line of attack. Maintenance and repair (M&R) spend is around **9 % of a Class 8 truck's
operating cost per mile** — it's real, but it's one of the few *controllable* line items, and it is
not where the economic outcome is decided.

The real return on **predictive** maintenance (PdM) is in reducing the **expected cost of failure**:

$$c_f = c_\text{repair} + c_\text{breakdown} + P(\text{crash}\mid\text{failure})\cdot c_\text{crash} + P(\text{OOS})\cdot c_\text{compliance}$$

The dominant term is not the repair: it's **the product of the probability of a crash and its cost**.
A fatal large-truck crash is valued by the FMCSA at **$15.23 million**, and the median *nuclear
verdict* (verdicts over $10M) against motor carriers reached **$36 million in 2022**. Against those
magnitudes, **avoiding a single catastrophic event every few years is enough to pay for decades of a
predictive program across the entire fleet.**

This document builds the argument end to end with verifiable sources, separating throughout the
**authoritative** (federal agencies, peer-reviewed studies) from the **commercial** (estimates from
the insurance industry or vendors — useful as illustration, but self-interested).

**The five anchor figures of the case:**

| Figure | Value | Source |
|---|---|---|
| Cost of a **fatal** large-truck crash | **$15.23 M** (USD 2023) | FMCSA, *Crash Costs Methodology 2025* — Table 3 |
| Median *nuclear verdict* against motor carriers | **$36 M** (2022), ~50 % over 2013 | ATRI |
| Crash over-risk of a carrier with a poor Vehicle Maintenance BASIC | **+65 %** (5.65 vs 3.43 crashes / 100 power units) | FMCSA SMS |
| Effectiveness of PdM over traditional PM | **+8–12 %** savings; **−70–75 %** breakdowns; **10× ROI** | DOE/FEMP O&M Best Practices Guide, Ch. 5 |
| Marginal operating cost (basis for the parked-day) | **$2.26/mile = $90.89/hour** (2024) | ATRI |

---

## 1. The problem: a double-digit fraction of the fleet runs with defects

This is not a hypothesis. At the **2024 International Roadcheck** by the **CVSA** (Commercial Vehicle
Safety Alliance) —48,761 inspections across Canada, Mexico and the United States, May 14–16— **23.2 %
of inspected vehicles were placed out of service** (OOS) for a defect: nearly **one in four**. And of
all vehicle OOS violations, the top two causes were precisely the two most prevalent vehicle-associated
crash factors (§2): **defective service brakes (26.5 %)** and **tires (22.1 %)**. A material share of
the fleet is rolling, at any given moment, with a defect an inspection would have flagged.

This matters because it defines the problem space: **the defect is not a rare event, it's a prevalent
state**. The economic question is not "can a truck fail?" but "what does it cost, in expected value, to
let that prevalent state progress to an on-road failure?". The rest of this document answers that
question, term by term of $c_f$.

---

## 2. From failure to crash, quantified

### 2.1 The published relative risk (authoritative)

The FMCSA's **Large Truck Crash Causation Study (LTCCS)** —the reference study, on a sample of 967
crashes weighted to ~141,000 events— establishes the relative risk (RR) of vehicle-associated factors:

| Associated factor | Relative risk (RR) | Prevalence among study trucks |
|---|---|---|
| Brakes | **2.7** | ~29 % |
| Tires | **2.5** | ~6 % |
| Cargo shift | **56.3** | ~4 % |

Direct reading: a truck with a brake problem is **+170 % more likely** to be assigned the crash's
critical reason (RR 2.7). In the LTCCS assignment of the *critical reason*, the vehicle accounts for
~10 %, the driver ~87 % and the environment ~3 %; **within the vehicle's share, brakes are the number
one associated factor.**

### 2.2 From RR to attributable fraction: the defensible figure is PAF ≈ 0.33

A point of honesty many analyses skip is worth making here. The LTCCS RR is for an *associated factor*,
**not** directly $P(\text{crash}\mid\text{failure})$. To translate it into an attributable fraction
there are two calculations, and only one is defensible at the fleet level:

- **Attributable fraction in the exposed**, $AF = (RR-1)/RR$: for brakes this gives 0.63. But this
  applies *only* to the subgroup that already has the failure; using it across the whole fleet
  **overestimates** the effect.
- **Population attributable fraction (PAF)**, $\text{PAF} = \dfrac{p(RR-1)}{1+p(RR-1)}$: with a
  prevalence $p \approx 0.29$ for brakes, this gives **PAF ≈ 0.33**. That is, **about one third of
  truck crashes are attributable, at the population level, to the brake factor.** This is the figure
  that sustains the case.

> *Methodological note:* the RR (2.7 / 2.5 / 56.3) is data published by the FMCSA; the PAF is a figure
> derived from that RR using the standard epidemiological formula. We keep the distinction visible
> deliberately.

### 2.3 The predictor that closes the loop: maintenance history predicts the crash

The maintenance → crash-rate link is not theoretical. The FMCSA's own system data show it:

- A carrier with an alert in **any** BASIC has a **+79 %** future crash rate (FMCSA SMS Effectiveness
  Test, 2014).
- A carrier flagged in the **Vehicle Maintenance BASIC** specifically averages **5.65 crashes per 100
  power units, versus 3.43 for the national average: +65 %.**

This is backed by peer-reviewed research (*Accident Analysis & Prevention*) and by ATRI's analysis of
the relationship between CSA scores and crash risk. An honest caveat: **not every BASIC predicts**
(Driver Fitness or Controlled Substances do not show the same relationship); it is the **Vehicle
Maintenance BASIC** that correlates positively with future risk. Precisely the one a predictive
maintenance program moves.

![**Accident rate by maintenance policy.** Levels are anchored in the documented figures of §2.3 (5.65 vs 3.43 crashes per 100 power units-year, the +65 % gap); the "reactive adopting preventive" policy transitions from one to the other as preventive maintenance is adopted. *PhAIMaT simulation, illustrative.*](../figures/accident_rate_by_policy.png){width=90%}

![**Cumulative accidents** (100-unit fleet, 4 years). The shaded area between reactive and preventive is the crash avoided: the program's safety prize, dominated by the term $P(\text{crash}\mid\text{failure})\cdot c_\text{crash}$. *PhAIMaT simulation, illustrative.*](../figures/cumulative_accidents_by_policy.png){width=90%}

---

## 3. The cost of the crash

Here is the term that dominates $c_f$. The FMCSA publishes large-vehicle crash costs by severity (2025
methodology, 2023 dollars):

| Severity | Cost per crash (USD 2023) |
|---|---|
| No injury (property damage only) | **$49,398** |
| With injury | **$326,810** |
| **Fatal** | **$15,230,414** |

On top of this comes the civil-liability front, where the trend is what changes the risk calculus: the
median *nuclear verdict* (verdicts over $10M) against motor carriers reached **$36 million in 2022,
~50 % above the 2013 median**; lawsuits against carriers are growing **+5.7 % per year (2014–2023)**
and the share of verdicts over $50M rose 6.4 points. These figures are confirmed against ATRI's primary
report.

The implication is arithmetic, not rhetorical. With the cost distribution's tail this heavy —a single
fatal event or a single nuclear verdict— **the expected value of the crash dominates any conceivable
savings on parts.** Predictive maintenance is, before it is an efficiency tool, a risk-tail management
instrument.

---

## 4. From failure to roadside breakdown: the breakdown cost ($c_\text{breakdown}$)

Not every failure is a crash; most are on-road breakdowns. Their cost is built from a chain of links,
from the most solid to the weakest:

1. **Value of stopped time (authoritative):** ATRI puts the cost of driver idle time at **$91.27/hour**
   (2023).
2. **Cost of the on-road repair event (industry):** TMC/FleetNet benchmarking data place the typical
   event at **~$522** (Q2 2020), with a frequency of **~31,638 miles between breakdowns** (MMBRR, mean
   miles between road calls).
3. **Heavy-duty tow (commercial — weakest link):** $4–15/mile plus a $250–600 hookup; with no federal
   source, treat as an industry estimate.
4. **Emergency premium:** an unplanned roadside repair costs on the order of **2 to 3×** the same
   repair done in-shop and planned.

To this add the regulatory context (mandatory emergency equipment, 49 CFR §393.95) and the delay
penalty borne by the average *dwell* documented by ATRI (1 h 40 min). The economic point: **every
breakdown shifts work from the cheap, planned quadrant to the expensive, on-road quadrant**, and it
does so at a measurable frequency.

![**Breakdowns that immobilize the vehicle** (on-road failure), accumulated by policy. Output of PhAIMaT's agent-physical simulator over a 60-truck fleet across 4 years: reactive accumulates 2,622 immobilizations; predictive CBM, 1,076. Each is a $c_\text{breakdown}$ event —roadside repair, emergency premium and stopped time.](../figures/immobilizing_breakdowns_by_policy.png){width=90%}

---

## 5. Secondary damage: the cost of "run it till it breaks"

Letting a defect progress does not cost linearly. It costs in **cascade**.

The physical sequence is authoritative and codified by the industry. Recommended Practice **TMC RP
622B** documents, for example, the chain *wheel seal → bearing → hub/spindle/ABS → wheel-off*: a $50
seal that's ignored ends in a lost wheel. Likewise, pad-to-metal → scored rotor → rotor replacement; or
overheating → warped head → gasket/block → engine. The sequence is real and well known.

On the economic magnitude of "reactive vs planned", the best available source is federal but **not
about trucks**: the DOE/FEMP (PNNL) *O&M Best Practices Guide* documents that reactive maintenance is
still the **predominant mode (>55 % of maintenance activity at U.S. facilities)** and the most
expensive, and that moving from reactive to **preventive saves 12–18 %**, and to **predictive, 25–30 %**
of maintenance cost (figures verified literally against the guide's text). We state it honestly: it's a
**cross-industry benchmark** (federal plants and buildings) extrapolated to fleets. The well-known
"reactive costs 3–5× the planned" multiplier circulates widely, but **we could not confirm it in this
guide or in a Class-8-specific primary source**, so we do not use it as an anchor. The cost overrun of
the unplanned is, in any case, consistent in order of magnitude with the 2–3× emergency premium from
the previous section.

> The dollar amounts of the physical cascades that circulate in the literature are usually for light
> vehicles; for Class 8 (a rotor, a $20–40k diesel rebuild) real OEM/VMRS quotes are needed. The
> **sequence** is authoritative (TMC); the **specific dollars** are illustrative.

---

## 6. Uptime is revenue, not just avoided cost

A common path underestimates the case by counting only the avoided repair and forgetting the revenue
not generated. The authoritative anchor for valuing availability is ATRI's **marginal operating cost:
$90.89/hour = $2.26/mile (2024)**. From it, with an ~11-hour hours-of-service (HOS) day, an opportunity
cost on the order of **~$1,000 per parked day** is derived on solid footing.

ATRI also tracks **"miles between breakdowns"** as a KPI — the direct conceptual bridge to our failure
model: every additional mile between events is uptime that the predictive approach turns into revenue.
(The "$448–760 per parked-day" figures that circulate come from vendors —SOTI— and are used here only
as a qualitative range, not as an anchor.)

---

## 7. Preventive/predictive does save: federal evidence, not a vendor's

The most common counterargument —"those savings figures are put out by whoever sells the system"— is
answered with a source that sells nothing. The DOE/FEMP (PNNL) **O&M Best Practices Guide, Chapter 5
(Predictive Maintenance)** establishes, for a predictive maintenance program:

- **10× ROI**
- Maintenance costs **−25 to −30 %**
- Breakdowns **−70 to −75 %**
- Downtime **−35 to −45 %**
- Production **+20 to +25 %**
- **Predictive over traditional preventive: +8 to 12 %** of additional improvement (up to 30–40 % where
  reactive dominates)

A point of provenance, for rigor: the DOE *publishes* these figures but attributes them to a
reliability-industry source; that's why we cite them as **"per the DOE/FEMP O&M Best Practices Guide,
Ch. 5"** (federally-published), not as the result of a federal experiment. The **approach** —that
condition-based maintenance reduces life-cycle cost— is further anchored in peer-reviewed literature
(Theissler et al., 2021, *Reliability Engineering & System Safety*).

---

## 8. The math of the optimum: why a correct investment point exists

The case does not rest on figures alone: it rests on a result from peer-reviewed **reliability theory**.
The *Age Replacement* model (Barlow–Hunter, 1960; Barlow–Proschan, 1965) expresses the cost per unit
time of a policy of replacing at age $T$:

$$C(T) = \frac{c_p\,R(T) + c_f\,F(T)}{\displaystyle\int_0^T R(t)\,dt}$$

where $c_p$ is the cost of the **planned** intervention, $c_f$ the cost of **failure** (the one from
the summary equation), and $R(T)=1-F(T)$ the reliability. The key result: **when the failure rate is
increasing (IFR, increasing failure rate — i.e., there is real deterioration), a unique interior
minimum $T^\star$ exists.** It is not "maintain more" or "maintain less": it is to maintain **at the
optimal point**, and that point exists and is computable.

This is the mathematical justification that the predictive approach is an investment with a
well-defined optimum, not an act of faith. PhAIMaT's engine computes precisely this $T^\star$ per
component: on components with an on-board precursor (brakes, DPF, battery, turbo…) from the **observed
degradation signal**, and on those without one (tire, wheel-end) from the component's **life
statistics**. In both cases the interval shifts dynamically as the asset's real condition changes —
which is what distinguishes the predictive approach from fixed-calendar preventive maintenance.

![**Cumulative cost by policy**, for new (dealer) and used fleets. The optimal $T^\star$ and predictive CBM clearly separate from reactive and fixed-interval; on a new fleet the predictive closes at 37.7 M MXN versus 81.4 M for reactive (4 years, 60 trucks). *PhAIMaT simulation.*](../figures/cost_by_policy.png){width=100%}

![**Total interventions by policy.** $T^\star$ and CBM achieve similar safety (corrective failures 2,112 vs 1,869), but $T^\star$ makes 8,197 preventive replacements against 3,806 for CBM: same protection, far more over-maintenance. It is the difference the cost curve (Figure 4) translates into ~20 % savings of CBM over $T^\star$. *PhAIMaT simulation.*](../figures/total_interventions_by_policy.png){width=90%}

### 8.1 The optimum is per-unit: driver behavior moves $T^\star$

$T^\star$ is not a catalog number: it depends on **how each unit is operated**. Driving style —harsh
braking, high rpm, idling, load— is observable in **OBD/CAN** telemetry and acts as a **covariate** that
speeds up or slows down wear, shifting **that** unit's life distribution and, with it, its optimal
interval. In the reliability model it enters as a scale factor on the characteristic life: two identical
trucks on the same route have different $T^\star$ if one is driven aggressively and the other gently.

The effect is not marginal. For brake pads —the component most sensitive to driving— the optimum shifts
from **~380 to ~208 engine-hours** between a gentle and an aggressive driver (close to a factor of 2). A
**fixed-interval policy is blind to this**: it over-maintains the gentle driver and leaves the aggressive
one under-protected. The predictive approach, estimating $T^\star$ **per unit** from the observed signal,
recovers the saving: on an aggressively-driven unit, scheduling at its own $T^\star$ instead of an average
one is worth on the order of **~2,600 MXN per unit-year** for this component alone.

![**Driving moves per-unit life and cost.** Left: the brake-pad life distribution shifts left under aggressive driving (the part dies younger). Center: the optimal interval $T^\star$ falls monotonically with the driving index. Right: cost per unit-year rises with driving; a **driving-aware** $T^\star$ (per unit) stays below a **blind** one (scheduled at an average interval). The driving index is derived from OBD/CAN telemetry. *PhAIMaT simulation.*](../figures/driving_economics.png){width=100%}

---

## 9. Compliance → insurance and contracts: the cost that doesn't show on the shop invoice

There is a term of $c_f$ that is neither repair nor crash: the **degradation of the compliance
profile** —the $P(\text{OOS})\cdot c_\text{compliance}$ of the equation— which is paid in premiums and
in lost contracts. It is best read broadly: it is not only the probability of a one-off out-of-service
event, but the cumulative effect of violations on the **SMS percentile**, which penalizes for 24
months.

- The **Vehicle Maintenance BASIC penalizes for 24 months**: each maintenance violation (brakes,
  lights, tires, cargo securement) affects the carrier's SMS percentile for two years; time without new
  violations improves it. *(Authoritative — FMCSA SMS.)*
- **Insurers use the CSA score in underwriting**: a clean percentile (<50 %) gives negotiating power;
  near 80 % it raises the price or closes coverage. *(The use of the data is authoritative; the size of
  the penalty —premium increases of 15–30 %— is an insurance-industry estimate.)*
- **Shippers and brokers filter by score**: it is common practice to require percentiles below 60–70 %
  across all BASICs as a condition to contract; SMS data are public by DOT number. *(The publicity of
  the data is authoritative; the 60–70 % thresholds are industry's.)*

And the trend in the insurance market confirms where the risk comes from: in **2023 premiums rose
12.5 %, to 9.9 ¢/mile** (ATRI, *Operational Costs of Trucking 2024* — the largest category increase
that year), with later coverage citing a record near 10.2 ¢/mile in 2024. The decisive point: **the
increase is driven by cost per claim —the nuclear verdicts— not by crash frequency, which has in fact
fallen.** This changes the nature of the saving: it does not come from "having fewer crashes"
(frequency is already low), but from **moving risk quartile** —a clean Vehicle Maintenance BASIC,
backed by verifiable telematics— which improves underwriting and preserves eligibility for contracts.
ATRI further documents a statistically significant correlation between six safety technologies and
lower liability loss per mile.

---

## 10. Mexico context: a bound, and why an aging fleet makes the case worse

The argument above is built on U.S. data, where the public series exist. For Mexico we must be explicit
about what can and cannot be claimed.

**What makes the problem worse locally:** the Mexican cargo fleet averages **~19.3 years of age**
(end-2024 ~19.27 years, per CANACAR over the SICT registry), versus ~6 years in the United States;
**68.8 % —522,517 units— are over 10 years old.** A structurally older fleet sits, by construction,
higher up the increasing-failure-rate (IFR) curve of Section 8: deterioration is greater and the
optimal $T^\star$ is tighter. The predictive case is *stronger*, not weaker, in this fleet.

**What the Mexican data do allow us to claim:** in 2023, INEGI (ATUS) recorded **27,594 heavy cargo
vehicles involved in crashes** in urban and suburban areas (10,907 tractors + 16,687 trucks; −1.8 %
year over year). The IMT documents, on the federal highway network, that failures due to the vehicle's
physical condition are **led by tires and brakes** —the same profile as in the United States.

**The honest gap:** the human factor dominates *frequency* (on the order of 88–94 % depending on source
and denominator), so in Mexico **mechanical failure is a minority by frequency**; the predictive case
here must be argued on **severity/cost and on the effect of the aging fleet**, not on share of
participation. And, above all: **Mexico does not publish a per-crash cost for cargo trucks** analogous
to the FMCSA's. There exists only the IMT macro bound —road crashes cost on the order of **1.4 to 3 %
of GDP** (IMT estimate ~887 billion pesos at end-2022, on the order of 2.4 billion pesos per day)—
which mixes all transport modes. Therefore, **any per-event $c_f$ for Mexico is an extrapolation of the
U.S. figures, which we use as a conservative bound.**

---

## 11. The TCO frame: where maintenance fits in the cost per mile

To place the magnitude, the breakdown of a Class 8's marginal operating cost is useful (ATRI, 2023:
$2.270/mile):

| Line item | $/mile | Comment |
|---|---|---|
| Driver wages | 0.779 | Not controllable by maintenance |
| Fuel | 0.553 | Not controllable by maintenance |
| Equipment payments | 0.360 | Capital |
| **Repair & maintenance (M&R)** | **0.202** | **Controllable** |
| Insurance | 0.099 | Controllable *indirectly* (via CSA) |
| Tires | 0.046 | **Controllable** |
| Tolls | 0.034 | Not controllable |

*(Breakdown verified against ATRI's primary report. The table lists the main line items; the 2023 total
of $2.270/mi also includes driver benefits $0.188 and permits/licenses $0.009, not shown as they are
outside the maintenance decision.)*

M&R represents **~9 % of operating cost** ($0.198–0.202/mile depending on the year; LTL ~$0.222/mile).
The reading is not "maintenance is cheap, ignore it". It's the opposite: **it is one of the very few
lines a maintenance decision can move** —together with tires, the controllable "shop/parts" block is
around 11 %— and, via CSA compliance, it also influences the **insurance premium indirectly**. The
predictive approach does not seek to *minimize* this line; it seeks to **recompose its content**:
shifting dollars from the reactive quadrant (expensive, on-road, with a crash tail) to the planned
quadrant (cheap, in-shop, schedulable). Class 8 TCO frameworks such as NACFE's and NREL/Argonne's break
out M&R precisely to enable this analysis.

---

## 12. Conclusion

The economic case for predictive fleet maintenance is not won on the parts invoice. It is won in the
tail of the failure-cost distribution:

- **The dominant term of $c_f$ is $P(\text{crash}\mid\text{failure})\cdot c_\text{crash}$**, with a
  fatal crash valued at $15.23 M and verdicts with a median of $36 M.
- **The causal chain is quantified**: poor maintenance raises the crash rate +65 % (Vehicle
  Maintenance BASIC), and about one third of truck crashes are attributable to the brake factor at the
  population level (PAF ≈ 0.33).
- **The predictive approach does reduce cost**, with federal evidence: −70–75 % of breakdowns and
  +8–12 % over traditional preventive (DOE/FEMP).
- **An optimal, computable investment point exists** ($T^\star$ under IFR), not an act of faith.
- **M&R is ~9 % of cost per mile but it is controllable**, and the predictive approach recomposes its
  content from reactive-expensive to planned-cheap, while also protecting premiums and contract
  eligibility.

The operational conclusion is simple and robust to parameter uncertainty: **avoiding a single
catastrophic event every few years —a $15.23 M fatal or a $36 M verdict— is enough to pay for decades
of a predictive program across the entire fleet.** And in an aging fleet like Mexico's (~19.3 years
average age), the accumulated deterioration makes the argument stronger, not weaker.

### A return calculation (illustrative)

The figures below are **illustrative** —they serve to fix the order of magnitude; the calibration pilot
replaces them with the fleet's own. Suppose a fleet of **100 Class 8 trucks** running line-haul,
~100,000 mi/year each, and a PdM program at **$40/truck/month = $480/truck/year** ($48,000/year for the
fleet; typical telematics + analytics subscription range $20–50/truck/month).

**Floor of the return — on the breakdown term alone, without counting a single crash.** With the MMBRR
of ~31,638 mi (§4), each truck suffers ~**3.2 on-road breakdowns per year** (100,000 ÷ 31,638). At
~$522 of repair per event (§4) plus a few hours of stopped time at $90.89/h (§6), each event costs on
the order of **~$1,000** conservatively (excludes heavy tow and late-delivery penalty) → **~$3,200/
truck/year** in breakdowns. The predictive approach cuts breakdowns **−70–75 %** (DOE/FEMP, §7):
savings ≈ **$2,200/truck/year**, i.e. **~4.6× the program cost** —and for the fleet, ~$220,000/year in
savings against $48,000/year of cost— **before touching the crash term.**

**The tail is pure additional upside.** A single fatal crash avoided ($15.23 M) equals **more than 300
years** of this fleet's program ($15.23 M ÷ $48,000 ≈ 317); a $36 M verdict, more than double. That's
why "avoid one catastrophic event every few years to pay for decades of program" is, if anything, **a
conservative statement**. And there's no need to avoid *every* crash: since a poor Vehicle Maintenance
BASIC raises the crash rate **+65 %** (§2.3), it's enough for the predictive approach to move the fleet
toward a clean compliance profile to act on that margin in expected value.

The deployment recommendation follows from the analysis: **prioritize the high-severity components
—brakes, tires, wheel-ends—**, where the combination of defect prevalence and tail cost is greatest,
applying **condition-based maintenance (CBM) where there is an on-board precursor** (brakes) and a
**life/statistics-based policy where there isn't** (tires, wheel-ends) —exactly as the engine does
(§8)—, and **calibrate the probability parameters $P$ with the fleet's own data** through an internal
pilot that turns this document's conservative bounds into the fleet's own figures.

---

## Sources and notes

Figures are marked **[A]** authoritative (federal agency / peer-reviewed / official body) or **[C]**
commercial/industry (self-interested; illustrative).

1. **[A]** FMCSA — *Crash Costs Methodology, 2025 Update*, Table 3 (costs by severity, USD 2023).
2. **[A]** FMCSA — *Large Truck Crash Causation Study (LTCCS)*, Report to Congress (RR by associated
   factor; *critical reason*). https://ai.fmcsa.dot.gov/downloadFile.axd?file=LTCCS+reportcongress_11_05.pdf
3. **[A]** FMCSA — *SMS Effectiveness Test* (2014) and *Vehicle Maintenance BASIC* (5.65 vs 3.43
   crashes/100 power units; +79 % with an alert in any BASIC).
   https://csa.fmcsa.dot.gov/documents/fmc_csa_12_009_basics_vehmaint.pdf
4. **[A]** ATRI — *Nuclear Verdicts & Litigation Costs* (median $36 M in 2022; +5.7 %/year; share
   >$50 M +6.4 pts). Via CCJ:
   https://www.ccjdigital.com/business/insurance/article/15773236/atri-report-trucking-nuclear-verdicts-litigation-costs-surge
5. **[A]** ATRI — *An Analysis of the Operational Costs of Trucking* (2024 / 2025 Update): marginal
   cost $2.26/mi = $90.89/h; M&R $0.198–0.202/mi; premiums +12.5 % to 9.9 ¢/mi (2023); MMBRR; dwell.
   https://truckingresearch.org/about-atri/atri-research/operational-costs-of-trucking/
6. **[A]** DOE / FEMP (PNNL) — *Operations & Maintenance Best Practices Guide*, R3.0, §5.4 (Predictive
   Maintenance) — **verified literally**: 10× ROI; −25–30 % cost; −70–75 % breakdowns; −35–45 %
   downtime; +20–25 % production; PdM over PM +8–12 %; §5.3 preventive 12–18 % over reactive.
   https://www.energy.gov/sites/prod/files/2020/04/f74/omguide_complete_w-eo-disclaimer.pdf
   · PNNL-14788: https://www.pnnl.gov/main/publications/external/technical_reports/pnnl-14788.pdf
7. **[A]** TMC (ATA) — *Recommended Practice RP 622B* (wheel-end failure cascade sequence) and
   TMC/FleetNet benchmarking (~$522/event). https://tmc.trucking.org/node/294
8. **[A]** Barlow, R. & Proschan, F. (1965), *Mathematical Theory of Reliability*; Barlow & Hunter
   (1960), *Optimum Preventive Maintenance Policies* — Age Replacement model, $T^\star$ under IFR.
9. **[A]** Theissler, A. *et al.* (2021), "Predictive maintenance enabled by machine learning…",
   *Reliability Engineering & System Safety* 215:107864.
   https://www.sciencedirect.com/science/article/pii/S0951832021003835
10. **[A]** *Insights into motor carrier crashes… FMCSA inspection violations*, *Accident Analysis &
    Prevention* (peer-reviewed). https://www.sciencedirect.com/science/article/abs/pii/S0001457521001366
11. **[A]** CVSA — *2024 International Roadcheck Results* (48,761 inspections; 23.2 % of vehicles OOS;
    service brakes 26.5 % and tires 22.1 % of vehicle OOS violations).
    https://cvsa.org/news/2024-roadcheck-results/
12. **[A]** INEGI — *Statistics of Road Traffic Crashes in Urban and Suburban Areas (ATUS), 2023*
    (27,594 heavy cargo vehicles). https://www.inegi.org.mx/rnm/index.php/catalog/903/
13. **[A]** CANACAR / SICT — age of the cargo trucking fleet (~19.3 years; 68.8 % over 10 years).
    https://canacar.com.mx/stat/antiguedad-la-flota-vehicular-del-autotransporte-carga/
14. **[A]** IMT — *Statistical Yearbook of Crashes on Federal Highways* (failures by physical
    condition; macro bound % of GDP). https://imt.mx/
15. **[A]** 49 CFR §393.95 — mandatory emergency equipment (FMCSA).
16. **[C]** Insurance-industry and vendor estimates (premium penalty 15–30 % for a poor CSA;
    shipper-filtering thresholds 60–70 %; UBI/telematics discounts 15–40 %; heavy tow $4–15/mi +
    hookup; "parked-day cost" $448–760). Useful as illustration; not a substitute for an actual quote.

---

*A PhAIMaT document. The $P(\cdot)$ probabilities of the $c_f$ equation must be calibrated with the
client fleet's data; the figures in this whitepaper are bounds and reference anchors, not a substitute
for a calibration pilot.*
