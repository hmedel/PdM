# Modalidad de análisis de aceite — contrato de datos y mapeo (INTERNO)

**Qué:** análisis de aceite usado (*used-oil analysis*, UOA) como **modalidad de monitoreo de condición
OFF-BOARD** que alimenta el estimador PdM para motor, **diferencial** y transmisión — los sistemas
lubricados cuyo mejor precursor NO está en J1939/OBD (el diferencial no tiene SPN on-board). Input del
experto de mantenimiento (2026-06-23). Distinta de la telemetría: llega como **muestras periódicas de
laboratorio**, no como flujo de sensor.

> **INTERNO:** este doc detalla el mapeo precursor↔degradación (IP). No exponer en materiales de cliente
> ni en la API pública. La parte pública es solo "se incorpora análisis de aceite como señal de condición".

Referencia de método: **TMC RP 318C** (análisis de aceite usado), ISO 4406 (conteo de partículas),
límites condenatorios OEM (Cummins/Detroit/Eaton) y tendencias por laboratorio (Blackstone/POLARIS/CAT SOS).

---

## 1. Por qué es una modalidad aparte (no un SPN más)

| | Telemetría OBD/J1939 (`obd_data`) | Análisis de aceite (UOA) |
|---|---|---|
| Origen | sensor on-board, continuo | muestra de lab, **periódica** (cada cambio de aceite) |
| Cadencia | segundos | ~cada 250–500 h / 20–40k km |
| Censura | snapshot | **intervalo-censurada** entre muestras |
| Señal | presión/temperatura/voltaje | **metales de desgaste**, viscosidad, hollín, TBN |
| Sistemas | motor, combustible, frenos… | **motor, diferencial, transmisión** (lubricados) |

⇒ Necesita su **propio contrato** (`OilSample`) y su propia tabla (`pdm_oil_sample`, estilo
`maintenance_records`), NO una columna de la hypertable `obd_data`.

## 2. Contrato `OilSample` (una muestra = una fila)

Identidad y reloj:
- `vehicle_id`, `tenant_id` (UUID/RLS, como el resto)
- `system` ∈ {`:engine`, `:differential`, `:transmission`} — sistema lubricado muestreado
- `sample_date`, `engine_hours`, `odometer_km` — reloj de uso del vehículo a la muestra
- `oil_hours`, `oil_km` — **horas/km sobre ESTA carga de aceite** (desde el último cambio) ⇒ normaliza
  el desgaste: lo que importa es **ppm por hora de aceite**, no ppm absolutos

Metales de desgaste (ppm) — cada uno apunta a una superficie:
- `iron_fe` (camisas/cigüeñal/engranes), `copper_cu` (bujes/cojinetes/enfriador de aceite),
  `chromium_cr` (anillos), `aluminum_al` (pistones/cojinetes), `lead_pb`+`tin_sn` (metal antifricción
  de cojinetes), `silicon_si` (tierra/sello de admisión — **contaminante**, no desgaste),
  `sodium_na`+`potassium_k`+`boron_b` (fuga de refrigerante)

Condición del lubricante:
- `viscosity_cst_100c` (cizalla/dilución), `soot_pct` (hollín — combustión/EGR),
  `tbn` (reserva alcalina — agotamiento de aditivo), `oxidation_ab`, `water_pct`, `fuel_dilution_pct`

Metadatos: `lab`, `method` (RP 318C), `sample_quality` (representatividad).

## 3. Mapeo a señal de degradación (el precursor)

Para un indicador de desgaste `m` (p. ej. Fe), con **línea base** `b` (aceite/componente nuevos) y
**límite condenatorio** `L` (OEM/RP 318C), la **fracción de desgaste** normalizada es

    f_m = clamp( (m_norm − b) / (L − b), 0, 1) ,     con  m_norm = m / oil_hours · h_ref

— el análogo off-board del precursor on-board `f = Dcum/Θ` (ver `Precursors`): `Θ` ↔ límite condenatorio
`L`, `Dcum` ↔ metal acumulado normalizado por edad de aceite. La **fracción del sistema** es

    f_sistema = max_m  w_m · f_m

(Fe/Cu/Pb dominan motor; Fe/Cu el diferencial). Lo **leading** es la **pendiente** `df/d(oil_hours)`
(tendencia ppm/hora), no el valor absoluto: una tendencia que se empina anticipa la falla.

Señales de **condición** (viscosidad, hollín, TBN, oxidación) NO son desgaste de pieza: alimentan
(a) la **optimización del intervalo de cambio de aceite** y (b) un **estresor/covariable** (hollín alto
acelera el desgaste — coherente con la covariable de manejo: ralentí/agresividad → más hollín).

## 4. Integración con el estimador

- **Entrada:** tabla `pdm_oil_sample` (UUID/tenant/RLS); vista `pdm_oil_signal` que entrega, por
  (vehicle, system), la serie `(oil_hours, f_sistema, pendiente)` — interválo-censurada.
- **Como precursor CBM:** habilita CBM para `oil`/`differential`/`transmission` (hoy `differential`
  tiene `dtc_spn=0` ⇒ decidía solo por T*/estadística). La fracción `f_sistema` entra al **mismo**
  pipeline precursor→RUL→IFR que los SPN on-board; el `alarm_fraction`/`sensor_cv` se calibran al CV del
  método de lab (mayor que un sensor, así que el RUL es más ancho — honesto).
- **Covariables:** ruta y **manejo** (OBD/CAN) siguen aplicando — manejo agresivo ⇒ más hollín y mayor
  pendiente de metales. El AFT puede usar `f_sistema`/pendiente como covariable dependiente del tiempo.

## 5. Validación por recuperación (próximo build, F-oil)

Espejo del backbone simulador↔estimador (Brief §4): extender el simulador para **emitir muestras** desde
el `Dcum` físico ya existente de motor/diferencial:

    m(oil_hours) = b + k · (Dcum/Θ) · oil_hours + ruido_lab

de modo que `f_sistema` recuperado ≈ fracción de daño verdadera, y un estimador independiente recupere la
posición relativa al límite y el RUL. Censura por intervalo entre muestras como ciudadano de primera
clase. **Criterio de aceptación:** recuperar la fracción de daño y el RUL dentro de IC contra la verdad
del generador; en datos delgados, ensanchar IC y **abstenerse** (igual que el resto del estimador).

## 6. Estado y pendientes

- **Hecho:** contrato `OilSample` + mapeo `wear_fraction` puro y testeado (`src/io/oil_sample.jl`).
- **Pendiente:** SQL `pdm_oil_sample` + vista `pdm_oil_signal` (cuando exista la fuente de lab);
  emisor en el simulador + estimador CBM por aceite (F-oil); calibrar límites `L` por sistema/OEM
  (RP 318C) y línea base `b`; decidir cadencia de muestreo con el cliente.
- **[reconfirmar]** límites condenatorios por OEM y los pesos `w_m` por sistema contra RP 318C / lab.
