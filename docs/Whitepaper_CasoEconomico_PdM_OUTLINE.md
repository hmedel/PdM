> **INTERNO — esqueleto del whitepaper del caso económico del PdM.** Cada sección apunta a su evidencia
> en `Hallazgos_Investigacion_Economica_INTERNO.md` (B1–B5,B8) y `Hallazgos_Bloques_6_7_INTERNO.md` (B6,B7).
> Próxima sesión: rellenar números, hacer verificación literal de PDFs, y redactar. Marcar [AUTORITATIVO]/[COMERCIAL].

# El caso económico del mantenimiento predictivo de flota (esqueleto)

**Tesis:** el ROI del PdM NO está en refacciones, sino en reducir el **costo esperado de falla**
$c_f = c_\text{repar} + c_\text{varado} + P(\text{accidente}|\text{falla})\cdot c_\text{accidente} + P(\text{OOS})\cdot c_\text{cumplimiento}$,
dominado por el término de accidente/responsabilidad civil.

1. **El problema: una fracción de dos dígitos de la flota circula con defectos.** → CVSA (OOS frenos ~12–13%, llantas ~34%). [B1/seguridad]
2. **Falla → accidente (cuantificado).** RR LTCCS frenos 2.7 / llantas 2.5 / cargo 56.3; **PAF≈0.33** poblacional (no AF 0.63). Vehicle Maintenance BASIC → **+65%** tasa de choque. [B1, AUTORITATIVO; separar RR publicado de AF/PAF derivado]
3. **El costo del accidente.** FMCSA: sin lesión $49,398 / lesión $326,810 / **fatal $15.23 M** (Tabla 3, CONFIRMADO). ATRI nuclear verdicts mediana **$36 M (2022)**. [seguridad, CONFIRMADO]
4. **Falla → descompostura (c_varado).** ATRI **$91.27/h** (valor del tiempo parado) + TMC/FleetNet **~$522/evento** + MMBRR ~31,638 mi; grúa pesada [COMERCIAL]; premium emergencia ~2–3×. [B2]
5. **Daño secundario / cascada.** Reactivo **3–5×** el planeado (DOE/PNNL, cross-industry — declarar); cascada física TMC RP 622B. [B3]
6. **Uptime como ingreso, no solo costo.** Costo de día parado derivado de $2.26/mi; "mileage between breakdowns" como puente con el modelo de fallas. [B4]
7. **El preventivo/predictivo SÍ ahorra — evidencia federal (no proveedor).** DOE/FEMP O&M BPG Cap.5: **ROI 10×, −25–30% costo, −70–75% fallas, −35–45% downtime, PdM/PM +8–12%**. [B5, HUECO #1 CUBIERTO]
8. **La matemática del óptimo.** Frontera $c_p$ vs $c_f$: $T^\star$ único bajo IFR (Barlow-Proschan) — ata con `optimal_interval.jl`/`Estudio_Convergencia_Economica.md`. [B8, peer-reviewed]
9. **Cumplimiento → seguro y contratos.** CSA/SMS → underwriting + filtrado de shippers; primas +12.5% (2023) por costo/siniestro; ahorro = mover de cuartil de riesgo + elegibilidad. [B6]
10. **Contexto México (cota).** Flota ~19.3 años (68.8% >10), fallas lideradas por neumáticos/frenos; siniestros ~1.4–3% del PIB. **No hay c_f de carga publicado → extrapolar US como cota conservadora.** [B7]
11. **Marco TCO.** M&R ~9% del costo operativo ($0.198–0.202/mi) pero **controlable**; el PdM mueve $ de reactivo (caro, en ruta) a programado. [B8]
12. **Conclusión.** Basta evitar **un** evento catastrófico cada varios años (fatal $15.2 M / verdict $36 M) para pagar décadas de programa predictivo. Priorizar CBM en alta severidad (frenos, llantas, wheel-end); validar % de reducción con piloto interno.

**Pendiente antes de publicar:** verificación literal de PDFs (FEMP Cap.5, ATRI/TMC 2024) o descargar a `References/`;
calibrar las $P$ con datos de flota propia; conseguir cotizaciones Clase 8 reales para los dólares de cascada (B3).
