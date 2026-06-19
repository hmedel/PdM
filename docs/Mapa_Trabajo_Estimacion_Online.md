# Mapa de Trabajo — Estimación Online y Aprendizaje Secuencial

**Plan de construcción de la máquina de estimación del módulo de mantenimiento**
Versión 1.0 — Junio 2026

> Este documento aterriza la Parte VIII de *Fundamentos Matemáticos* en un plan de ingeniería. Define **workstreams** (paralelizables), su **secuencia**, los **hitos de validación** y los **riesgos específicos** de la estimación. No repite la teoría; remite a la Parte VIII por sección.

---

## 0. Objetivo y principios

**Objetivo:** un motor que asimila eventos en streaming (telemetría OBD/CAN, IMU, GPS, y sobre todo **reparaciones**) y mantiene, para cada unidad y para la flota, distribuciones actualizadas de salud y de vida, sin recalcular todo, y que entrega RUL + decisión con incertidumbre cuantificada.

**Principios rectores:**

1. **La reparación es dato de primera clase.** Cada orden de trabajo actualiza el modelo de la unidad *y* los hiperparámetros de flota. La *calidad* de la reparación se estima (factor $q$, Parte VIII.4).
2. **Capas a distinta cadencia, ninguna recalcula todo** (Parte VIII.7): filtrado rápido por unidad, refit de flota por lotes, inferencia de despliegue amortizada.
3. **La física es el simulador.** El modelo PoF (Parte V) genera datos sintéticos etiquetados ilimitados para entrenar la inferencia amortizada y para validar antes de tener datos propios maduros.
4. **Calibrar, no solo predecir.** El umbral de decisión es sensible al costo (Parte VI.2); la calidad de las *probabilidades* (calibración) importa tanto como el acierto puntual.

---

## 1. Workstreams (paralelizables)

### WS-A — Infraestructura de datos de evento
Fundación. Sin esto nada se entrena.
- Esquema estructurado de **evento de reparación** (componente, modo de falla, fecha/odómetro/horas, acción, costo, causa raíz, IDs jerárquicos) — ver dossier §10.1.
- Ingesta de telemetría (features físicas desde el borde) + eventos a un *store* de series de tiempo (TimescaleDB) con **feature store** y **model registry**.
- Etiquetado de censura (qué piezas siguen vivas) y de exposición real (horas/km por componente).
- **Entregable:** pipeline de datos confiable + esquema de censura. **Bloquea:** todo lo demás.

### WS-B — Filtrado de estado por unidad (Parte VIII.2)
- Implementar la cadena Kalman → UKF → filtro de partículas sobre el modelo de degradación (Parte IV), con la deriva fijada por la física (Parte V).
- Estado aumentado para aprender parámetros por-unidad (p. ej. tasa de desgaste $k$ de *esa* balata).
- Salida: densidad de salud filtrada → RUL como primer cruce, con intervalos.
- **Entregable:** filtro por componente que corre por evento. **Depende de:** WS-A (features).

### WS-C — Modelo de eventos recurrentes (Parte VIII.4)
- Verosimilitud de proceso puntual con intensidad $\lambda(t\mid H_t)$.
- Implementar NHPP (Crow–AMSAA), renovación, y **edad virtual de Kijima / GRP** con factor $q$ estimable.
- Extensión Andersen–Gill para covariables sobre eventos recurrentes.
- **Entregable:** estimación de $q$ por taller/tipo de reparación + intensidad por unidad. **Depende de:** WS-A.

### WS-D — Jerarquía bayesiana de flota + refit por lotes (Partes VII, VIII.3)
- Modelo jerárquico anidado clase → marca → modelo → unidad (Parte VII.2) con covariables físicas.
- **Refit por lotes con HMC** (`Turing.jl`) como primera versión (nocturno/semanal).
- Migrar a **SG-MCMC (SGLD/SGHMC)** o **SVI streaming** cuando el volumen lo exija; factor de olvido para no-estacionariedad.
- **Entregable:** posteriors de hiperparámetros que se refrescan por lotes. **Depende de:** WS-A; consume salidas de WS-B/WS-C como covariables.

### WS-E — Inferencia amortizada / SBI (Parte VIII.5)
- Construir el **simulador** a partir de la física (Parte V) + prior jerárquico (WS-D).
- Entrenar **Neural Posterior Estimation** $q_\psi(\theta\mid x)$ offline; validar contra HMC (debe coincidir en casos donde HMC es factible).
- Desplegar inferencia de unidad nueva como **forward pass**.
- **Entregable:** inferencia instantánea en despliegue. **Depende de:** WS-D (prior) + simulador.

### WS-F — Capa de decisión (Partes VI, VIII.6)
- Empezar con el **intervalo óptimo de costo** (Parte VI.1) y el **umbral sensible al costo** (VI.2) sobre las salidas de WS-B/WS-D.
- Evolucionar a **POMDP** (estado de salud latente, acción óptima) resuelto por programación dinámica o **deep RL** con *domain randomization* sobre el posterior de WS-D/WS-E.
- **Entregable:** política de intervención (cuándo/dónde) con incertidumbre. **Depende de:** WS-B, WS-D.

### WS-G — Validación, backtesting y calibración (transversal)
- Backtesting temporal (entrenar hasta $t$, predecir $t{+}\Delta$) sobre datos públicos (Scania APS y Component X, NASA C-MAPSS) **antes** de datos propios.
- Métricas: **costo monetario esperado** (no accuracy), recall de falla, error de RUL (RMSE/MAE), **calibración** (reliability diagrams), y cobertura de los intervalos.
- Detección de drift / cambio de régimen.
- **Entregable:** arnés de evaluación reproducible. **Transversal a todos los WS.**

---

## 2. Secuencia por fases (qué primero)

| Fase | Contenido | Workstreams | Sale a producción |
|---|---|---|---|
| **E0** | Datos de evento + censura + arnés de validación en datasets públicos | WS-A, WS-G | — |
| **E1** | Vida estadística por lotes (Weibull/Cox jerárquico, HMC) + RUL condicional | WS-D | RUL poblacional + alertas por umbral |
| **E2** | Filtrado de estado por unidad (Kalman→partículas) | WS-B | RUL por unidad al vuelo |
| **E3** | Eventos recurrentes + factor de reparación $q$ | WS-C | "salud" tras cada reparación; scorecard de taller |
| **E4** | Streaming a escala (SG-MCMC/SVI) + no-estacionariedad | WS-D (v2) | refit continuo sin recálculo total |
| **E5** | Inferencia amortizada (SBI) | WS-E | inferencia instantánea para unidad/cliente nuevo |
| **E6** | Decisión secuencial (POMDP/RL) | WS-F | política prescriptiva de intervención |

Cada fase produce valor por sí sola. E1 ya da pronóstico útil; no hay que llegar a E6 para tener retorno. E0 y la disciplina de WS-G son lo más importante y lo menos glamoroso.

---

## 3. Dependencias (resumen)

```
WS-A (datos)  ──►  WS-B (filtro)  ──►  WS-F (decisión)
   │                  │                   ▲
   ├──►  WS-C (eventos, q) ───────────────┤
   │                  │                   │
   └──►  WS-D (flota, HMC→SG-MCMC) ──► WS-E (amortizada)
WS-G (validación) rodea todo, desde E0.
```

---

## 4. Hitos de validación (criterios de "hecho")

1. **H1 (E0):** reproducir un baseline publicado en Scania APS con la métrica de **costo asimétrico** del reto (FN ≫ FP). Si no se reproduce, el pipeline está mal.
2. **H2 (E1):** el Weibull/Cox jerárquico predice mejor que reglas OEM en backtesting temporal, y los intervalos están **calibrados** (cobertura ≈ nominal).
3. **H3 (E2):** el filtro de partículas mejora la RUL por-unidad sobre el modelo poblacional cuando hay señal de degradación medida.
4. **H4 (E3):** el factor $q$ es **identificable** y distingue reparaciones que restauran de las que no (validar contra reincidencia observada).
5. **H5 (E5):** la inferencia amortizada coincide con HMC (divergencia baja) en casos donde HMC es factible, a una fracción del costo.
6. **H6 (E6):** la política POMDP/RL reduce el **costo total esperado** vs. la política de umbral en simulación honesta.

---

## 5. Stack sugerido

- **Modelado (servidor):** Julia — `Turing.jl` (HMC/jerárquico), `AdvancedHMC.jl`, `Survival.jl`, `Distributions.jl`, `DifferentialEquations.jl` (degradación/Fokker–Planck), `Flux.jl`/`Lux.jl` (amortizada/LSTM), `LowLevelParticleFilters.jl` o equivalente (filtrado).
- **Edge (captura + filtrado ligero):** Python (ya en el bridge) — filtros KF/UKF en tiempo real; features físicas (rainflow, energía de frenado).
- **SBI:** entrenamiento offline (Julia/Python); despliegue como forward pass.
- **Datos:** PostgreSQL + TimescaleDB; feature store + model registry.

---

## 6. Riesgos específicos de la estimación

- **Identificabilidad de $q$:** separar "reparación mala" de "unidad intrínsecamente débil" requiere suficientes ciclos por unidad; mitigar con prior jerárquico sobre $q$ por taller y validación contra reincidencia.
- **Mezcla del MCMC jerárquico:** los modelos anidados sufren geometrías difíciles (embudos de Neal); usar parametrización no-centrada y diagnósticos ($\hat R$, ESS, divergencias de HMC).
- **Drift / no-estacionariedad:** si la flota cambia y el modelo no olvida, predice mal; instrumentar detección de cambio + factor de olvido desde E4.
- **Degeneración de partículas:** en horizontes largos el filtro colapsa; remuestreo adaptativo, jittering, o surrogate en la verosimilitud.
- **Calibración bajo desbalance:** las fallas son raras; las probabilidades deben calibrarse o el umbral sensible al costo (Parte VI.2) falla. WS-G lo vigila.
- **Sobre-confianza de la red amortizada fuera de distribución:** validar SBI contra HMC y marcar entradas atípicas (la amortización es válida dentro del soporte del simulador).
- **Gobernanza:** todo refit consume datos bajo consentimiento; el registro de consentimiento (dossier §10.4) debe poder excluir unidades de los sets de entrenamiento de forma reproducible.

---

*Mapa de trabajo. La teoría correspondiente está en Fundamentos Matemáticos, Parte VIII; las fuentes en Referencias, sección N.*
