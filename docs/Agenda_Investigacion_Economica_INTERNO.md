> **DOCUMENTO INTERNO.** Agenda de investigación exhaustiva del caso económico del mantenimiento
> preventivo/predictivo. Complementa `Investigacion_Seguridad_Mantenimiento_INTERNO.md` (cifras ancla ya
> blindadas). Ejecutar en próxima sesión con WebFetch autenticado o PDFs en `References/`.

# Agenda — argumento económico exhaustivo: fallas → accidentes/descomposturas → impacto económico, y mantenimiento (preventivo) → ahorro

**Tesis a sostener ante dirección:** el ROI del mantenimiento preventivo/predictivo NO está en el ahorro
de refacciones, sino en la **reducción del costo esperado de falla** $c_f$, dominado por el término de
accidente/responsabilidad civil — y eso debe quedar cuantificado y citado a fuente primaria, eslabón por eslabón.

## Bloques pendientes (pregunta · hueco actual · dónde buscar)

1. **P(accidente | falla) por componente — cuantificación dura.** Hoy `[estimación]`. Derivar la
   *attributable fraction* del relative risk LTCCS: AF = (RR−1)/RR ⇒ frenos 0.63, llantas 0.60 del exceso de
   riesgo en vehículos CON el factor. Cruzar con violaciones→siniestros de CSA/SafetyStat. Fuentes: FMCSA
   CSA/SMS, epidemiología de choques de camión (TRB, Accident Analysis & Prevention).
2. **Economía del varado ($c_\text{varado}$) rigurosa.** Downtime/día, grúa pesada, daño a carga, penalización
   por entrega tardía, costo de oportunidad. Fuentes: ATRI *Operational Costs* (detalle por categoría), encuestas de flota.
3. **Daño secundario (cascada de "correr hasta fallar").** Balero→maza/flecha; balata al metal→disco;
   sobrecalentamiento→motor. Multiplicador de costo reactivo vs programado. Fuentes: TMC Recommended Practices, OEM/talleres.
4. **Disponibilidad/uptime como activo (lado ingreso, no solo costo).** Costo de camión parado/día; impacto en
   utilización e ingresos. Fuentes: ATRI, benchmarks de flota.
5. **Efectividad del preventivo/predictivo sobre COSTO — evidencia NO comercial (HUECO DE CREDIBILIDAD #1).**
   Hoy −35–62% / 75–85% predecible son `[fuente comercial]`. Buscar federal/peer-reviewed: DOE/FEMP O&M Best
   Practices (PdM −25–30% costo, ROI ~10×, paros −70–75%), estudios académicos CBM ROI (RESS, IISE, Reliability Eng.).
6. **Cumplimiento/CSA → seguro y contratos.** OOS, multas, deterioro de CSA score → primas más altas (ligar con
   primas +12.5% 2023, ATRI) y pérdida de contratos; seguros basados en telemática (UBI). Fuentes: FMCSA, aseguradoras.
7. **Datos México (cota real, no extrapolación US).** INEGI, SICT/IMT, CANACAR, ANTP: siniestralidad, antigüedad
   de flota, costos locales de accidente/varado. Hoy todo es `[estimación]` desde EE. UU.
8. **Marco TCO y curva de trade-off.** Mantenimiento como % del costo total de propiedad; frontera
   costo-de-mantenimiento vs costo-esperado-de-falla y dónde el predictivo minimiza el total. Conecta con
   `Estudio_Convergencia_Economica.md` (break-even, EUAC) y `Estudio_Ahorro`.

## Entregable objetivo
Un whitepaper interno con **cada eslabón cuantificado y citado a fuente primaria**, que cierre la cadena
fallas→accidentes/descomposturas→$ y mantenimiento(preventivo)→ahorro, con el ROI dominado por el término de
accidente/responsabilidad civil. **Método:** las fuentes `.gov` dan HTTP 403 al fetcher → descargar los PDF a
`References/` (como ya se hizo con FMCSA/LTCCS/ATRI) o usar un fetch autenticado/MCP.
