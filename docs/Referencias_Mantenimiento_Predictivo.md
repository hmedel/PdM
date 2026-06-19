# Referencias — Mantenimiento Predictivo de Flota

**Bibliografía consolidada y categorizada**
Versión 1.0 — Junio 2026

> Nota metodológica: se priorizan **fuentes primarias** (papers seminales, normas, datasets) sobre material secundario. Las fuentes de industria/gris (blogs de proveedores, wikis) se separan explícitamente al final y se usan solo como apoyo de contexto, no como base científica. Donde un dato no pudo verificarse al 100 % en la fuente original se marca *(verificar)*.

---

## A. Estadística de confiabilidad y análisis de vida

1. **Weibull, W. (1939).** *A statistical theory of the strength of materials.* Ingeniörsvetenskapsakademiens Handlingar Nr. 151, Generalstabens Litografiska Anstalts Förlag, Stockholm. — Origen físico de la distribución de Weibull (resistencia de materiales, eslabón más débil).
2. **Weibull, W. (1951).** *A statistical distribution function of wide applicability.* Journal of Applied Mechanics, 18(3), 293–297. — Artículo canónico de la distribución de Weibull.
3. **Cox, D. R. (1972).** *Regression models and life-tables.* Journal of the Royal Statistical Society, Series B, 34(2), 187–220. — Modelo de riesgos proporcionales y verosimilitud parcial.
4. **Kaplan, E. L. & Meier, P. (1958).** *Nonparametric estimation from incomplete observations.* Journal of the American Statistical Association, 53(282), 457–481. — Estimador de supervivencia con censura.
5. **Barlow, R. E. & Proschan, F. (1965).** *Mathematical Theory of Reliability.* Wiley, New York. (Reimpresión SIAM, 1996). — Base de teoría de confiabilidad y políticas de reemplazo.
6. **Lawless, J. F. (2003).** *Statistical Models and Methods for Lifetime Data*, 2nd ed. Wiley. — Tratado de inferencia con datos de vida censurados.
7. **Meeker, W. Q. & Escobar, L. A. (1998).** *Statistical Methods for Reliability Data.* Wiley. — Referencia estándar de métodos de confiabilidad.
8. **Nelson, W. (1982).** *Applied Life Data Analysis.* Wiley. — Análisis aplicado, gráficos de probabilidad, censura.
9. **Fisher, R. A. & Tippett, L. H. C. (1928).** *Limiting forms of the frequency distribution of the largest or smallest member of a sample.* Proc. Cambridge Phil. Soc., 24(2), 180–190. — Teoría de valores extremos (fundamento del porqué emerge Weibull).
10. **Gnedenko, B. (1943).** *Sur la distribution limite du terme maximum d'une série aléatoire.* Annals of Mathematics, 44(3), 423–453. — Teorema límite de extremos.

---

## B. Procesos estocásticos de degradación y RUL

11. **Si, X.-S., Wang, W., Hu, C.-H. & Zhou, D.-H. (2011).** *Remaining useful life estimation — A review on the statistical data driven approaches.* European Journal of Operational Research, 213(1), 1–14. — Revisión de enfoques estadísticos de RUL (Wiener, Gamma, etc.).
12. **van Noortwijk, J. M. (2009).** *A survey of the application of gamma processes in maintenance.* Reliability Engineering & System Safety, 94(1), 2–21. — Procesos Gamma para desgaste monótono.
13. **Whitmore, G. A. (1995).** *Estimating degradation by a Wiener diffusion process subject to measurement error.* Lifetime Data Analysis, 1(3), 307–319. — Degradación tipo Wiener y tiempo de primer cruce.
14. **Lei, Y., Li, N., Guo, L., Li, N., Yan, T. & Lin, J. (2018).** *Machinery health prognostics: A systematic review from data acquisition to RUL prediction.* Mechanical Systems and Signal Processing, 104, 799–834. — Revisión integral de pronóstico (adquisición → RUL).
15. **(2025).** *RUL prediction based on the bivariant two-phase nonlinear Wiener degradation process.* (Modelos de Wiener no lineales bifásicos con punto de cambio vía SIC/AIC). PMC12025624. *(verificar autores/volumen)*

---

## C. Tribología y desgaste por deslizamiento (frenos, embrague)

16. **Archard, J. F. (1953).** *Contact and rubbing of flat surfaces.* Journal of Applied Physics, 24(8), 981–988. DOI: 10.1063/1.1721448. — Ley de Archard del desgaste; derivación desde el área real de contacto.
17. **Holm, R. (1946).** *Electric Contacts.* Almqvist & Wiksells, Stockholm. — Precursor del concepto de área real de contacto/desgaste.
18. **Rabinowicz, E. (1965).** *Friction and Wear of Materials.* Wiley. (Con base en sus trabajos de 1951 sobre formación de partículas de desgaste). — Criterio de formación de partícula de desgaste.
19. **Burwell, J. T. & Strang, C. D. (1952).** *On the empirical law of adhesive wear.* Journal of Applied Physics, 23(1), 18–28. DOI: 10.1063/1.1701970. — Ley empírica de desgaste adhesivo.
20. **Meng, H. C. & Ludema, K. C. (1995).** *Wear models and predictive equations: their form and content.* Wear, 181–183, 443–457. — Catálogo de 182 ecuaciones de desgaste; contexto del modelo de Archard.
21. **Zhang, et al. (2019).** *Simulation study on friction and wear law of brake pad in high-power disc brake.* Mathematical Problems in Engineering, 2019, 6250694. — Archard corregido por presión, velocidad y temperatura interfacial.
22. **Kalhapure, V. A. & Khairnar, H. P. (2020).** *(Modelos lineales/no lineales de desgaste de freno; revisión).* Tribology in Industry, 42(3), 345–362. — Modelos de Rhee (no lineal) vs Archard para materiales de fricción.

---

## D. Fatiga estructural (chasis, suspensión, soportes) — uso del IMU

23. **Basquin, O. H. (1910).** *The exponential law of endurance tests.* Proceedings of ASTM, 10, 625–630. — Curva S–N (relación esfuerzo–vida).
24. **Palmgren, A. (1924).** *Die Lebensdauer von Kugellagern.* Zeitschrift des VDI, 68(14), 339–341. — Primera hipótesis de daño lineal acumulado.
25. **Miner, M. A. (1945).** *Cumulative damage in fatigue.* Journal of Applied Mechanics, 12(3), A159–A164. — Regla de Palmgren–Miner ($D=\sum n_i/N_i=1$).
26. **Coffin, L. F. (1954).** *A study of the effects of cyclic thermal stresses on a ductile metal.* Transactions of the ASME, 76, 931–950. — Fatiga de bajo ciclo (deformación plástica).
27. **Manson, S. S. (1953).** *Behavior of materials under conditions of thermal stress.* NACA TN-2933. — Relación Coffin–Manson (independiente).
28. **Matsuishi, M. & Endo, T. (1968).** *Fatigue of metals subjected to varying stress.* Japan Society of Mechanical Engineers, Fukuoka. — Algoritmo de conteo rainflow.
29. **ASTM E1049-85 (2017).** *Standard Practices for Cycle Counting in Fatigue Analysis.* — Norma de conteo de ciclos (rainflow y métodos relacionados).
30. **Fatemi, A. & Yang, L. (1998).** *Cumulative fatigue damage and life prediction theories: a survey of the state of the art.* International Journal of Fatigue, 20(1), 9–34. — Revisión de teorías de daño acumulado y límites de Miner.
31. **Johannesson, P. & Speckert, M. (eds.) (2013).** *Guide to Load Analysis for Durability in Vehicle Engineering.* Wiley. — Análisis de cargas y daño por fatiga aplicado a vehículos.
32. **(2016).** *Online estimation of driving events and fatigue damage on vehicles.* arXiv:1603.06455. — Estimación online de daño por fatiga vía rainflow + Palmgren–Miner en datos vehiculares (referencia directa para el pipeline IMU→fatiga).

---

## E. Vida de rodamientos y fatiga de contacto

33. **Lundberg, G. & Palmgren, A. (1947).** *Dynamic capacity of rolling bearings.* Acta Polytechnica Scandinavica, Mechanical Engineering Series, 1(3), 1–52, Stockholm. — Teoría L10 (Weibull de eslabón más débil sobre volumen esforzado).
34. **Lundberg, G. & Palmgren, A. (1952).** *Dynamic capacity of roller bearings.* Acta Polytechnica Scandinavica, Mechanical Engineering Series, 2(4), 96–127. — Extensión a rodillos.
35. **Ioannides, E. & Harris, T. A. (1985).** *A new fatigue life model for rolling bearings.* Journal of Tribology, 107(3), 367–378. — Modelo con límite de fatiga (refinamiento de L–P).
36. **ISO 281 (2007).** *Rolling bearings — Dynamic load ratings and rating life.* — Norma de vida nominal de rodamientos (codifica L–P/I–H).
37. **Zaretsky, E. V. (1997).** *STLE Life Factors for Rolling Bearings*, 2nd ed. STLE. — Factores de vida y comparación de teorías.
38. **Harris, T. A. & Kotzalas, M. N. (2006).** *Rolling Bearing Analysis*, 5th ed. CRC Press. — Tratado de referencia.

---

## F. Desgaste de neumáticos

39. **(2025).** *Tire wear, tread depth reduction, and service life.* Vehicles (MDPI), 7(2), 29. — Predicción de vida de banda por energía de fricción, slip y abrasividad; proyección desde break-in.
40. **(2025).** *Development of an advanced wear simulation model for a racing slick tire under dynamic acceleration loading.* Machines (MDPI), 13(8), 635. — Modelo de desgaste por energía de fricción dependiente de temperatura.
41. **Veith, A. G. (1992).** *Tire tread wear — The joint influence of compound properties and environmental factors.* Tire Science and Technology, 20(2), 124–196. — Modelo clásico de desgaste por energía/abrasión. *(verificar paginación)*
42. **Patente US 12128714.** *Model for predicting wear and the end of life of a tire.* — Estimación de rigidez longitudinal y desgaste vía $F_x$–slip a partir de datos del vehículo.

---

## G. PHM, machine learning y datasets de mantenimiento predictivo

43. **Saxena, A., Goebel, K., Simon, D. & Eklund, N. (2008).** *Damage propagation modeling for aircraft engine run-to-failure simulation* (C-MAPSS / dataset Turbofan). IEEE Int. Conf. on Prognostics and Health Management (PHM). — Benchmark clásico de RUL.
44. **UCI Machine Learning Repository (2017).** *APS Failure at Scania Trucks Data Set.* (Reto IDA 2016, 15th Int. Symp. on Intelligent Data Analysis, Stockholm University). — Clasificación de fallas del sistema de aire con matriz de costo asimétrica.
45. **Kharazian, Z., et al. (2025).** *SCANIA Component X dataset: a real-world multivariate time series dataset for predictive maintenance.* Scientific Data (Nature), 12. DOI: 10.1038/s41597-025-04802-6. (arXiv:2401.15199). — Dataset de series de tiempo a nivel flota con registros de reparación; apto para clasificación, regresión RUL, supervivencia y anomalía.
46. **(2025).** *Attention-enhanced multi-head LSTM (MH-LSTM) for RUL on SCANIA Component X.* — Benchmark MH-LSTM (RMSE ≈ 1.0 día) vs LSTM/RF/LR. *(verificar referencia formal)*
47. **Nascimento, R. G. & Viana, F. A. C. (2019).** *Fleet prognosis with physics-informed recurrent neural networks.* arXiv:1901.05512. — RNN informada por física para pronóstico de flota.
48. **Theissler, A., Pérez-Velázquez, J., Kettelgerdes, M. & Elger, G. (2021).** *Predictive maintenance enabled by machine learning: Use cases and challenges in the automotive industry.* Reliability Engineering & System Safety, 215, 107864. DOI: 10.1016/j.ress.2021.107864. — Revisión de PdM automotriz con ML.
49. **(2024).** *Remaining useful life prediction based on physics-informed data augmentation.* Reliability Engineering & System Safety (RESS). DOI: 10.1016/j.ress.2024.110... — Aborda explícitamente el gap entre confiabilidad a nivel flota y pronóstico a nivel individual, y el requisito de grandes datos etiquetados. *(verificar DOI completo)*
50. **Bellani, L., Compare, M. & Zio, E. (2021).** *A physics-informed machine learning framework for predictive maintenance applied to turbomachinery assets.* J. Global Power and Propulsion Society, SI, 1–15. DOI: 10.33737/jgpps/134845. — Marco PoF+ML multinivel (Baker Hughes).
51. **Lundgren, A., et al. (2024).** *SurvLoss: A new survival loss function for neural networks to process censored data.* PHM Society European Conference, 8. — Función de pérdida de supervivencia para redes con datos censurados.
52. **(2025).** *Application-wise review of ML-based predictive maintenance.* Applied Sciences (MDPI), 15, 4898. — Revisión reciente; señala escasez de datos, costo de etiquetado y falta de benchmarks estándar.

---

## H. Adquisición de datos vehiculares (protocolos)

53. **SAE J1939 (familia).** *Serial Control and Communications Heavy Duty Vehicle Network.* SAE International. — En particular: **J1939-21** (capa de enlace), **J1939-71** (capa de aplicación / SPN), **J1939-73** (diagnósticos / DM1, DM2, FMI).
54. **SAE J1979 / ISO 15031.** *E/E Diagnostic Test Modes (OBD-II).* — Diagnóstico de vehículos ligeros (códigos P/C/B/U).
55. **SAE J1708 / J1587.** — Protocolos heredados de vehículos pesados (anteriores a J1939).
56. **ISO 11898.** *Road vehicles — Controller Area Network (CAN).* — Capa física/enlace sobre la que corre J1939.

---

## I. Normas de gestión de activos y mantenimiento

57. **ISO 55000 / 55001 / 55002 (2014, rev. 2024).** *Asset management — Overview/principles; Management systems — Requirements; Guidelines for application.* — Marco de gestión de activos.
58. **SAE JA1011 (2009).** *Evaluation Criteria for Reliability-Centered Maintenance (RCM) Processes.* — Define qué constituye RCM legítimo.
59. **SAE JA1012 (2011).** *A Guide to the Reliability-Centered Maintenance (RCM) Standard.* — Guía complementaria de JA1011.
60. **IEC 60300-3-11 (2009).** *Dependability management — Application guide — Reliability centred maintenance.* — RCM normalizado.
61. **MIL-STD-1629A (1980).** *Procedures for Performing a Failure Mode, Effects and Criticality Analysis (FMECA).* — Base del FMECA / RPN.
62. **ISO 13374 (series).** *Condition monitoring and diagnostics of machines — Data processing, communication and presentation.* — Arquitectura por capas de un sistema PHM/CBM.
63. **ISO 17359 (2018).** *Condition monitoring and diagnostics of machines — General guidelines.* — Lineamientos generales de monitoreo de condición.
64. **Moubray, J. (1997).** *Reliability-Centered Maintenance (RCM II)*, 2nd ed. Industrial Press. — Texto de referencia práctico de RCM.

---

## J. Mantenimiento basado en condición y decisión óptima

65. **Jardine, A. K. S., Lin, D. & Banjevic, D. (2006).** *A review on machinery diagnostics and prognostics implementing condition-based maintenance.* Mechanical Systems and Signal Processing, 20(7), 1483–1510. — Revisión fundacional de CBM.
66. **Jardine, A. K. S. & Tsang, A. H. C. (2013).** *Maintenance, Replacement, and Reliability: Theory and Applications*, 2nd ed. CRC Press. — Optimización de reemplazo (incluye intervalo óptimo de costo).
67. **Wang, H. (2002).** *A survey of maintenance policies of deteriorating systems.* European Journal of Operational Research, 139(3), 469–489. — Catálogo de políticas de mantenimiento.
68. **Stamatis, D. H. (2003).** *Failure Mode and Effect Analysis: FMEA from Theory to Execution*, 2nd ed. ASQ Quality Press. — FMEA/FMECA aplicado.

---

## K. Protección de datos, privacidad y gobernanza (México)

69. **LFPDPPP (2025).** *Ley Federal de Protección de Datos Personales en Posesión de los Particulares.* Publicada en el DOF el 20 de marzo de 2025; en vigor el 21 de marzo de 2025; **abroga la LFPDPPP de 2010**. — Marco vigente para datos personales en el sector privado (ubicación, conductor, video en cabina). Disponible en diputados.gob.mx/LeyesBiblio.
70. **Reforma constitucional en materia de simplificación orgánica (DOF 20-12-2024).** — Extingue el INAI; transfiere la autoridad de protección de datos a la **Secretaría Anticorrupción y Buen Gobierno (SABG)**.
71. **Ley General de Protección de Datos Personales en Posesión de Sujetos Obligados (2025).** DOF 20-03-2025. — Marco para entes públicos (referencia, por si hay clientes gubernamentales).
72. **Reglamento de la LFPDPPP (2025).** — Reglamento de la nueva ley (verificar emisión y contenido vigente; detalla aviso de privacidad, transferencias, derechos ARCO).
73. **Derechos ARCO.** Acceso, Rectificación, Cancelación y Oposición — derechos del titular que el sistema debe poder atender operativamente.

---

## L. Contexto regulatorio del autotransporte (México / EE. UU.)

74. **SICT/SCT (México).** Normas Oficiales Mexicanas aplicables a condiciones físico-mecánicas y seguridad del autotransporte federal de carga (verificar numeración y vigencia al momento de implementar; p. ej. NOM aplicable a condiciones físico-mecánicas, NOM de pesos y dimensiones, NOM de llantas). *(verificar versión vigente)*
75. **FMCSA (EE. UU.) — 49 CFR Parts 393, 396.** *Parts and Accessories Necessary for Safe Operation; Inspection, Repair, and Maintenance.* — Referencia comparativa (DVIR, inspecciones), útil para rutas transfronterizas.

---

## M. Fuentes de industria / literatura gris (apoyo de contexto, no base científica)

> Estas fuentes se usaron para mapear el estado del mercado y la práctica industrial; no constituyen evidencia científica primaria.

76. Geotab — *Predictive maintenance for truckload fleets* (blog técnico, 2025).
77. KEBA Digital — *Predictive maintenance for truck fleets* (caso de uso, sistema de aire).
78. FleetRabbit — *Predictive maintenance for trucking fleets* / *J1939 vs J1708 heavy truck diagnostics* (2026).
79. AutoPi — *J1939 explained: PGNs, SPNs & heavy-duty diagnostics* (2025).
80. Diesel Laptops — *Truck SAE codes: J1939, J1708, SPN, FMI, MID explained* (2025).
81. Tribonet / *About Tribology* — *Archard wear equation* (wiki técnica, 2025).
82. Patentes de PdM consultadas (USPTO): 11574508, 11385950, 12189383, 11761858 — métodos de predicción de falla de componentes y de desgaste de neumáticos (referencia de prior art / diseño industrial).

---

## N. Estimación secuencial, filtrado y aprendizaje online (referenciada en Parte VIII de Fundamentos)

**Filtrado y Monte Carlo secuencial**
83. **Kalman, R. E. (1960).** *A new approach to linear filtering and prediction problems.* Journal of Basic Engineering, 82(1), 35–45. — Filtro de Kalman.
84. **Gordon, N. J., Salmond, D. J. & Smith, A. F. M. (1993).** *Novel approach to nonlinear/non-Gaussian Bayesian state estimation.* IEE Proceedings-F, 140(2), 107–113. — Filtro de partículas (bootstrap).
85. **Doucet, A., de Freitas, N. & Gordon, N. (eds.) (2001).** *Sequential Monte Carlo Methods in Practice.* Springer. — Tratado de SMC.
86. **Arulampalam, M. S., Maskell, S., Gordon, N. & Clapp, T. (2002).** *A tutorial on particle filters for online nonlinear/non-Gaussian Bayesian tracking.* IEEE Trans. Signal Processing, 50(2), 174–188. — Tutorial canónico.
   - *(Aplicación a RUL/prognosis: Cadini, Zio et al., RESS 2009; PHM Society — filtro de partículas para crecimiento de grieta y RUL.)*

**MCMC e inferencia escalable / streaming**
87. **Welling, M. & Teh, Y. W. (2011).** *Bayesian learning via stochastic gradient Langevin dynamics (SGLD).* ICML. — MCMC con gradiente estocástico.
88. **Chen, T., Fox, E. & Guestrin, C. (2014).** *Stochastic gradient Hamiltonian Monte Carlo (SGHMC).* ICML. — SG-MCMC con momento.
89. **Hoffman, M., Blei, D., Wang, C. & Paisley, J. (2013).** *Stochastic variational inference.* Journal of Machine Learning Research, 14, 1303–1347. — SVI.
90. **Broderick, T., Boyd, N., Wibisono, A., Wilson, A. C. & Jordan, M. I. (2013).** *Streaming variational Bayes.* NeurIPS. — Actualización variacional en streaming.
91. **Andrieu, C., Doucet, A. & Holenstein, R. (2010).** *Particle Markov chain Monte Carlo methods.* Journal of the Royal Statistical Society, Series B, 72(3), 269–342. — Particle MCMC.

**Sistemas reparables y eventos recurrentes**
92. **Kijima, M. & Sumita, U. (1986).** *A useful generalization of renewal theory: counting processes governed by non-negative Markovian increments.* Journal of Applied Probability, 23(1), 71–88. — Proceso de renovación generalizado / edad virtual.
93. **Crow, L. H. (1974).** *Reliability analysis for complex, repairable systems.* (Modelo de potencia-ley / AMSAA). En *Reliability and Biometry*, SIAM. — NHPP de potencia-ley (Crow–AMSAA).
94. **Andersen, P. K. & Gill, R. D. (1982).** *Cox's regression model for counting processes: a large sample study.* Annals of Statistics, 10(4), 1100–1120. — Cox para eventos recurrentes.
   - *Kaminskiy, M. P. & Krivtsov, V. V. — solución Monte Carlo de la ecuación g-renewal (verificar referencia exacta).*

**Inferencia amortizada / basada en simulación (SBI)**
95. **Papamakarios, G. & Murray, I. (2016).** *Fast ε-free inference of simulation models with Bayesian conditional density estimation.* NeurIPS. — Neural Posterior Estimation.
96. **Cranmer, K., Brehmer, J. & Louppe, G. (2020).** *The frontier of simulation-based inference.* Proceedings of the National Academy of Sciences, 117(48), 30055–30062. — Revisión de SBI / inferencia amortizada.

**Decisión secuencial bajo incertidumbre (POMDP / RL)**
97. **Andriotis, C. P. & Papakonstantinou, K. G. (2019).** *Managing engineering systems with large state and action spaces through deep reinforcement learning.* Reliability Engineering & System Safety, 191, 106483. — Deep RL para inspección/mantenimiento (POMDP). *(verificar volumen)*
98. **Arcieri, G., et al. (2023).** *POMDP inference and robust solution via deep reinforcement learning: an application to railway optimal maintenance.* arXiv:2307.08082. — Inferencia HMC de un HMM + solución POMDP por deep RL con *domain randomization*.

---

## O. Métodos geométricos, espectrales y topológicos (referenciada en Apéndice B de Fundamentos)

**PCA y reducción / geometría**
99. **Jolliffe, I. T. (2002).** *Principal Component Analysis*, 2nd ed. Springer. — PCA clásico.
100. **Belkin, M. & Niyogi, P. (2003).** *Laplacian eigenmaps for dimensionality reduction and data representation.* Neural Computation, 15(6), 1373–1396. — Embedding por Laplaciano de grafo.
101. **Coifman, R. R. & Lafon, S. (2006).** *Diffusion maps.* Applied and Computational Harmonic Analysis, 21(1), 5–30. — Difusión / geometría intrínseca.
102. **von Luxburg, U. (2007).** *A tutorial on spectral clustering.* Statistics and Computing, 17(4), 395–416. — Clustering espectral.

**Koopman / Dynamic Mode Decomposition**
103. **Koopman, B. O. (1931).** *Hamiltonian systems and transformation in Hilbert space.* PNAS, 17(5), 315–318. — Operador de Koopman.
104. **Schmid, P. J. (2010).** *Dynamic mode decomposition of numerical and experimental data.* Journal of Fluid Mechanics, 656, 5–28. — DMD.
105. **Williams, M. O., Kevrekidis, I. G. & Rowley, C. W. (2015).** *A data-driven approximation of the Koopman operator: extending dynamic mode decomposition.* Journal of Nonlinear Science, 25, 1307–1346. — EDMD.
106. **Lusch, B., Kutz, J. N. & Brunton, S. L. (2018).** *Deep learning for universal linear embeddings of nonlinear dynamics.* Nature Communications, 9, 4950. — Deep Koopman.
107. **(2020).** *A Koopman operator approach for machinery health monitoring and prediction with noisy and low-dimensional industrial time series.* Neurocomputing. — Koopman/DMD para diagnóstico y RUL.
108. **(2024).** *Deep Koopman operator-based degradation modelling.* Reliability Engineering & System Safety. — RUL en cortadores CNC y baterías Li-ion.

**Análisis topológico de datos (TDA)**
109. **Carlsson, G. (2009).** *Topology and data.* Bulletin of the AMS, 46(2), 255–308. — Manifiesto de TDA.
110. **Edelsbrunner, H. & Harer, J. (2010).** *Computational Topology: An Introduction.* AMS. — Texto de homología persistente.
111. **Ghrist, R. (2008).** *Barcodes: the persistent topology of data.* Bulletin of the AMS, 45(1), 61–75. — Barcodes/persistencia.
112. **Singh, G., Mémoli, F. & Carlsson, G. (2007).** *Topological methods for the analysis of high dimensional data sets and 3D object recognition* (algoritmo Mapper). Eurographics SPBG.
113. **Takens, F. (1981).** *Detecting strange attractors in turbulence.* Lecture Notes in Mathematics, 898, 366–381. — Teorema de embedding por retardos (Takens).
114. **Bubenik, P. (2015).** *Statistical topological data analysis using persistence landscapes.* JMLR, 16, 77–102. — Vectorización (landscapes).
115. **Otter, N., et al. (2017).** *A roadmap for the computation of persistent homology.* EPJ Data Science, 6, 17. — Costos de cómputo (peor caso $\sim 2^{3n}$).
116. **Chazal, F. & Michel, B. (2021).** *An introduction to topological data analysis: fundamental and practical aspects for data scientists.* Frontiers in Artificial Intelligence, 4, 667963. — Introducción práctica.
117. **Casolo, S., et al. (2024).** *Testing topological data analysis for condition monitoring of wind turbines.* PHM Society European Conference, 8(1). (arXiv:2406.16380). — TDA sobre vibración; "complementario" a lo espectral.
118. **(2024).** *A robust topological framework for detecting regime changes in multi-trial experiments with application to predictive maintenance.* arXiv:2410.20443. — Persistencia sobre representaciones tiempo-frecuencia; dataset NASA bearing.

**Unificación por operadores (geometría ↔ Fokker–Planck ↔ Koopman; Apéndice B.5)**
119. **Nadler, B., Lafon, S., Coifman, R. R. & Kevrekidis, I. G. (2006).** *Diffusion maps, spectral clustering and reaction coordinates of dynamical systems.* Applied and Computational Harmonic Analysis, 21(1), 113–127. — Convergencia de diffusion maps a operadores de Fokker–Planck / Laplace–Beltrami según la normalización $\alpha$; el puente con la ecuación maestra.
120. **Klus, S., et al. (2020).** *Data-driven approximation of the Koopman generator: model reduction, system identification, and control.* Physica D / arXiv:1909.10638. — Generador de Koopman y su adjunto (Perron–Frobenius) vía EDMD; dualidad observables/densidades.

---

## P. Economía del mantenimiento y estudios de ahorro (referenciada en Fundamentos VI.3 y Dossier §6.4)

121. **US DOE / FEMP (2010).** *Operations & Maintenance Best Practices Guide, Release 3.0.* — Cifras célebres predictivo vs reactivo: ROI ~10×, costo de mantenimiento −25–30%, paros −70–75%, downtime −35–45%; predictivo sobre preventivo +8–12%. **Programa federal + encuestas de industria, no RCTs**; usar como orden de magnitud. https://www.energy.gov/femp
122. **PNNL — O&M Best Practices (FEMP).** *Maintenance Approaches.* — Detalle de los ahorros 8–12% (PdM sobre PM) y >30–40% donde domina reactivo; advierte costo de arranque alto. https://www.pnnl.gov/projects/om-best-practices/maintenance-approaches
123. **EPRI** (citado en surveys de PdM). — Predictivo: −30% vs periódico, −50% vs reactivo. Investigación de industria.
124. **Theissler, A., et al. (2021).** *Predictive maintenance enabled by ML: use cases and challenges in the automotive industry.* RESS 215, 107864. (también en sección G47) — Revisión peer-reviewed con discusión de ROI automotriz.

> Nota de evidencia: las cifras de DOE/FEMP y EPRI provienen de literatura gris/programa federal y encuestas, no de ensayos controlados. Los blogs de proveedores (no listados) inflan las cifras y se excluyen como evidencia. El argumento defendible combina estas cotas con la teoría de renovación-recompensa (refs 5, 66, 67) y validación con datos propios.

---

## Cómo citar este proyecto internamente

Sugerencia de estilo: numeración por categoría (A1, C16, etc.) en los documentos técnicos, para trazar cada ecuación o decisión de diseño a su fuente. El documento de *Fundamentos Matemáticos* referencia esta lista por número.

*Última verificación de fuentes web: junio 2026. Verificar vigencia de normas (ISO/SAE/NOM) y DOIs marcados antes de citar en una publicación formal.*
