# Extensión de componentes PdM — de 4 a 12

**Qué:** se extendió el estimador/simulador de 4 componentes (brake_pad, dpf, scr, battery) a **12**,
añadiendo los más importantes para mantenimiento predictivo/preventivo en flota Clase 8 diésel.
Basado en investigación con fuentes (TMC/FleetNet, CVSA, ATRI, Decisiv, estudios Weibull).

Versión 1.0 — 2026-06-18.

> **Nivel de confianza de los números:** β/η/costos son **[estimación]** salvo donde se cita estudio;
> los umbrales de precursor (SPN) provienen de *snippets* de búsqueda y están marcados **[reconfirmar]**
> en el código (`src/sim/precursor.jl`) contra los PDF OEM (Cummins/Bendix) y el SAE J1939-71 Digital
> Annex antes de fijarlos en producción. El *fetch* de páginas estuvo bloqueado en la investigación.

---

## Componentes añadidos (8)

Definidos en `src/physics/DamageModels.jl` (`COMPONENTS`); precursores en `src/sim/precursor.jl`.
Todo se deriva de `COMPONENTS` automáticamente (verdad, vidas, economía, estimador).

| Componente | β | η_ref (h-motor) | cp / cf (USD) | Mecanismo→ruta | Precursor (SPN) | CBM |
|---|---|---|---|---|---|---|
| cooling (bomba/termostato) | 2.0 | 9000 | 800 / 3200 | `:cooling` (nuevo) | temp refrig. **SPN 110** >110°C | sí |
| turbo (VGT) | 2.9¹ | 5500 | 3000 / 9000 | `:soot` | déficit boost **SPN 103/102** | sí |
| egr (válvula/cooler) | 1.8 | 3500 | 700 / 2800 | `:soot` | temp EGR **SPN 412** >293°C | sí |
| fuel_system | 2.8¹ | 6000 | 1500 / 6000 | `:fatigue` | presión **SPN 94/157** | sí |
| oil (desgaste motor) | 3.0 | 12000 | 1500 / 25000 | `:fatigue` | presión aceite **SPN 100** <110 kPa | sí (+lab) |
| air_system (compresor+secador) | 1.7 | 4500 | 400 / 1600 | `:brake` | presión depósito **SPN 117/118** | sí |
| **tire** | 1.85¹ | 3500 | 400 / 1600 | `:fatigue` | TPMS no mide banda → **sin precursor** | **no (estadístico)** |
| **wheel_end** (rodamiento cubo) | 1.3¹ | 8000 | 600 / 2400 | `:fatigue` | sin SPN estándar → **sin precursor** | **no (estadístico)** |

¹ β con respaldo: turbo≈2.88 e inyector≈2.78 (estudio diésel marino); rodamiento≈1.1–1.5
(Lundberg-Palmgren); tire≈1.85 (valor ilustrativo Reliability Analytics). El resto **[estimación]**.

**Mecanismo nuevo `:cooling`** añadido a los 5 arquetipos de ruta (`RouteNetwork.ARCHETYPES`): alto en
montaña/Appalachia (subidas sostenidas) y desierto (calor ambiente), bajo en llano. Valores [estimación].

**tire y wheel_end** son ESTADÍSTICOS por diseño: su mejor señal (profundidad de banda, salud de
rodamiento) **no está en J1939 estándar**, así que no tienen entrada en `Precursors` ⇒ el estimador
decide por intervalo óptimo T*/IFR (no CBM). Requerirían TPMS/smart-hubs (ConMet/STEMCO) para CBM.

---

## Anclas económicas (de fuente)

- **cf/cp ≈ 4** (reparación roadside vs taller) — TMC/FleetNet (Jim Buell).
- R&M ≈ **$0.20/mi**; neumáticos **$0.047/mi** — ATRI 2024. Usar 3–5× como rango de sensibilidad.

## Frecuencia vs costo (los dos ejes que el set cubre)

- **Frecuencia de varado** (TMC/FleetNet, CVSA 2024): neumáticos > eléctrico/luces > frenos >
  enfriamiento > wheel-end (top-5 ≈ 58–69% de varados).
- **Costo de reparación** (Decisiv/TMC): motor > escape/emisiones (~40% juntos) > enfriamiento >
  frenos > combustible.

## Correcciones a premisas (de la investigación)

- **TMC RP 318C = análisis de aceite usado** (no refrigerante); refrigerante/SCA es **RP 319B**.
- "$448–760/día de downtime" es cifra **light-duty/Michelin** (secundaria); la primaria defendible es
  el **4× roadside/taller**.

## Pendiente de verificación antes de producción

- Conflicto de SPN de TPMS (241/242 vs 929) → confirmar contra J1939-71 Digital Annex.
- Umbrales OEM (Cummins coolant >230°F/oil <16psi; Bendix EAC; FMVSS 121 <60psi) → reconfirmar PDF.
- β de Clase-8 para clutch/driveline/EGR/banda no existe en literatura → ajustar Weibull con **datos
  propios de la flota** cuando estén en la BD.

## Fuentes (selección; lista completa en el registro de investigación)

- TMC/FleetNet benchmarking: https://www.fleetequipmentmag.com/fleetnet-tmc-roadside-truck-repair-benchmarking-study/
- CVSA Roadcheck 2024: https://cvsa.org/news/2024-roadcheck-results/
- Decisiv/TMC service event benchmark: https://tmc.trucking.org/blog/decisivtmc-north-american-service-event-benchmark-report
- ATRI Operational Costs 2025 (datos 2024): https://truckingresearch.org/2025/07/an-analysis-of-the-operational-costs-of-trucking-2025-update/
- Weibull diésel (turbo 2.88 / inyector 2.78): https://www.researchgate.net/publication/346448405
- J1939 PGN/SPN (CSS Electronics): https://www.csselectronics.com/pages/j1939-pgn-list
- Cummins thresholds: https://www.cummins.com/sites/default/files/rv-manuals/0981-0166.pdf
- FMVSS 121 / 49 CFR 393.51: https://www.law.cornell.edu/cfr/text/49/393.51
