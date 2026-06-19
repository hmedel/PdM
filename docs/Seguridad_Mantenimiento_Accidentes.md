# Mantenimiento deficiente / reactivo → accidentes, varados y pérdidas

**Propósito:** sustento documental de que el mantenimiento reactivo (run-to-failure) aumenta accidentes,
descomposturas en ruta y pérdidas — **por componente** — y de por qué el **costo de falla `c_f`** del
modelo económico debe incluir mucho más que la reparación. Cierra con cómo alimenta el modelo.

Versión 1.0 — 2026-06-19. Investigación con fuentes (FMCSA, NHTSA, NTSB, CVSA, ATRI, TMC).

> **Aclaración crítica (filosofía "sin sustento no sirve").** El dato popular "29% de los choques de
> camión son por frenos" es una **lectura incorrecta** del FMCSA LTCCS. El estudio asigna la **causa
> crítica al vehículo en ~10%** de los choques (al conductor 87%, entorno 3%). El **29% es la frecuencia
> de los frenos como *factor asociado* DENTRO de ese ~10%** con causa crítica de vehículo — no el 29% de
> todos los choques. Además, frecuencia ≠ riesgo: un camión con problema de frenos tenía **+170%** de
> probabilidad de recibir la causa crítica. (FMCSA LTCCS Analysis Brief.)

---

## Tabla por componente: falla → accidente → evidencia → pérdida

| Componente | Falla (mal mantenimiento) | Accidente / descompostura | Evidencia / estadística | Pérdida |
|---|---|---|---|---|
| **Frenos / balatas** | Balatas gastadas, tambores OOS, ABS off | ↑ distancia de frenado → colisión trasera; runaway en pendiente | Frenos = factor asociado #1 (~29% de camiones con causa crítica de vehículo); 32.7% en run-off-road | crash + OOS |
| **Sistema neumático (aire)** | Pushrod fuera de stroke, fugas | Pérdida de fuerza de frenado "hasta cero"; frenado de emergencia | "Defective service brakes" = **violación OOS #1** CVSA 2024 | camión OOS en ruta |
| **Neumáticos** | Subinflado, desgaste, separación | Reventón → pérdida de control / vuelco; restos como proyectil | Tires = OOS #2; frenos+llantas = **45.8%** de OOS vehiculares 2024; ~11,000 choques/año por llantas (NHTSA), 563 muertes 2022 | crash + varado |
| **Wheel-end / rodamientos** | Tuercas sin re-torquear, rodamiento sin lubricar | **Wheel-off** → rueda (>300 lb) como proyectil; pérdida de eje | NTSB ~**750–1,050 separaciones/año** [verificar fuente primaria]; causa principal: sujetadores | responsabilidad alta |
| **Dirección / suspensión** | Componentes desgastados | Pérdida de control, run-off-road | "steering/susp/trans/engine failed" = **19.1%** factores críticos run-off-road | crash |
| **Enfriamiento** | Fuga/nivel bajo, sobrecalentamiento | Cabeza agrietada, aceite → **incendio**; varado | Recalls NHTSA por refrigerante bajo (incendios de motor); Peterbilt/Thomas (pesados) | pérdida total + carga |
| **Batería / eléctrico** | Batería/alternador/cableado | No arranca / sin carga → road call | Baterías/carga = **>60%** de service calls eléctricos [#1 absoluto no confirmado] | road call evitable |
| **Luces / cinta retrorreflejante** | Luces fundidas, cinta sucia | Colisión trasera/lateral nocturna | Cinta reduce impactos **29%** (oscuridad) / **41%** (total); lodo reduce reflectividad ≥50% | crash + multa |
| **DPF / SCR** | Sensor ΔP, DEF cristalizado, regen fallida | **Derate / limp (5 mph)** → inmovilizado hasta corregir | Etapa final limita a ~5 mph, no rearranca | repuesto $3k–6k + varado |
| **Combustible** | Filtros tapados, contaminación | Pérdida de potencia / varado | Road calls de combustible (FleetNet) | varado |

### Magnitudes de pérdida (transversales)
| Métrica | Valor | Fuente |
|---|---|---|
| Crash sin lesión (large truck, USD 2023) | **$49,398** | FMCSA Crash Cost Methodology 2025 |
| Crash con lesión | **$326,810** | idem |
| Crash fatal | **$15,230,414** | idem |
| Reparación en ruta vs taller | $400–650 (taller) → **$2,800–4,500** (emergencia) + 1–3 días downtime | FleetHD |
| Remolque pesado | $2,500–$5,000+ | Logrock |
| Mantenimiento por milla | **$0.202/mi** (ATRI 2025) | ATRI |
| Nuclear verdicts (≥$10M) | mediana **$21M (2020) → $51M (2024)** | ATRI/CCJ |
| Primas de seguro | +36% en 8 años; +12.5% en 2023 | ATRI |

---

## Cómo alimenta el modelo: descomposición de `c_f`

La evidencia justifica que **`c_f` ≠ costo de reparación**. Una falla reactiva dispara una cascada:

$$c_f \;=\; c_{\text{reparación}} \;+\; c_{\text{varado}} \;+\; P(\text{accidente}\mid\text{falla})\cdot c_{\text{accidente}} \;+\; P(\text{OOS/multa})\cdot c_{\text{cumplimiento}}.$$

- La misma reparación cuesta **5–7×** como emergencia en ruta vs taller (+ downtime + remolque).
- Cuando la falla contribuye a un choque, el costo esperado salta a **$49k / $327k / $15.2M** (sin lesión
  / lesión / fatal), con cola de *nuclear verdicts* (mediana $51M) que además sube las primas de TODA la flota.
- Componentes con vínculo causal documentado a accidentes severos —**frenos, llantas, wheel-end,
  enfriamiento→incendio**— deben llevar `c_f` con el término de accidente; esto **justifica umbrales
  predictivos más conservadores** justo donde la consecuencia es peor. Es coherente con el ancla `c_f/c_p≈4`
  que ya usa el modelo, y sugiere que para esos componentes el múltiplo real puede ser mayor.

**Acción para el modelo:** al calibrar con datos de Tracker, fijar `c_f` por componente sumando el término
`P(accidente|falla)·c_accidente`. Hoy los `c_f` son [estimación]; este documento da el sustento y el orden
de magnitud (de $50k a $15M por evento de accidente) para esa calibración.

---

## Caveats de verificación (honestidad)
- "29% de choques por frenos" → es factor asociado dentro del ~10% con causa crítica de vehículo, NO del total.
- Costos antiguos ($200k/$3.6M) están **desactualizados**; usar $326,810 / $15.23M (USD 2023).
- Batería como "road call #1 absoluto": no confirmado en fuente primaria (sí >60% de los *eléctricos*).
- NTSB 750–1,050 wheel-offs/año: citado vía medio de industria; verificar documento NTSB primario.
- Recalls de enfriamiento Ford son de vehículos ligeros (mecanismo ilustrativo); Peterbilt/Thomas sí pesados.
- El fetch de PDFs primarios estuvo bloqueado; cifras de resúmenes de búsqueda + URLs primarias. Para el
  expediente, abrir manualmente LTCCS y Crash Cost Methodology 2025 para fijar tablas exactas.

## Fuentes (selección)
- FMCSA LTCCS Analysis Brief: https://www.fmcsa.dot.gov/safety/research-and-analysis/large-truck-crash-causation-study-analysis-brief
- FMCSA Crash Cost Methodology 2025: https://www.fmcsa.dot.gov/sites/fmcsa.dot.gov/files/2026-02/Crash%20Costs%20Methodology%202025%20Update_0.pdf
- NHTSA Run-Off-Road DOT HS 811 500: https://crashstats.nhtsa.dot.gov/Api/Public/Publication/811500
- NHTSA Tire-Related DOT HS 811 617: https://crashstats.nhtsa.dot.gov/Api/Public/ViewPublication/811617
- NHTSA Retroreflective Tape 809222: https://www.nhtsa.gov/sites/nhtsa.gov/files/809222.pdf
- CVSA 2024 Roadcheck: https://cvsa.org/news/2024-roadcheck-results/ · 2023: https://cvsa.org/news/2023-roadcheck-results/
- CVSA Air Brake Pushrod Stroke: https://cvsa.org/programs/operation-airbrake/air-brake-chamber-pushrod-stroke/
- ATRI Operational Costs 2025 (vía Fleet Maintenance): https://www.fleetmaintenance.com/equipment/article/55301363/
- ATRI Nuclear Verdicts (CCJ): https://www.ccjdigital.com/business/insurance/article/15773236/
- FleetHD (roadside vs shop): https://www.fleethd.com/the-real-cost-of-fleet-maintenance-how-predictive-maintenance-reduces-expenses/
- Trucking Info wheel-offs: https://www.truckinginfo.com/153237/why-do-wheels-come-off-trucks
- FMVSS 121 (stopping distance −30%): https://www.fullbay.com/blog/fmvss-121-rsd-requirements/
