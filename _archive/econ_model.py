# Modelo economico de mantenimiento: costo de renovacion-recompensa para
# reactiva / preventiva / predictiva, con termino catastrofico (pieza + unidad),
# ahorro como funcion de la calidad de prediccion, y curva de aprendizaje (streaming).
import numpy as np
from math import gamma as Gamma
from scipy.optimize import minimize_scalar
from scipy.stats import norm

# ---- Componente que se desgasta (Weibull beta>1) ----
beta, eta = 2.5, 1800.0                 # horas-motor
mu = eta*Gamma(1+1/beta)                # MTTF
R = lambda t: np.exp(-(t/eta)**beta)    # confiabilidad

# ---- Costos (MXN, ilustrativos; el equipo mete los reales) ----
c_p   = 2500.0                          # intervencion planeada (pieza + mano de obra)
rho   = 4.0                             # c_f/c_p (consecuencial: downtime, grua, en-ruta)
c_f   = rho*c_p
phi   = 0.05                            # fraccion de fallas que escalan a catastrofica
c_cat = 80000.0                         # costo catastrofico (dano mayor / perdida de unidad / carga)
c_f_eff = (1-phi)*c_f + phi*c_cat       # costo esperado de una FALLA (incluye escalamiento)

print(f"mu (MTTF) = {mu:.0f} h | c_p={c_p:.0f} | c_f={c_f:.0f} | c_f_eff={c_f_eff:.0f} | rho={rho}")

# ---- Politica REACTIVA: reemplazo a la falla ----
C_R = c_f_eff/mu
print(f"\n[Reactiva]   tasa de costo = {C_R:.3f} MXN/h")

# ---- Politica PREVENTIVA por edad T_p (renovacion-recompensa) ----
from scipy.integrate import quad
def C_PM(Tp):
    num = c_p*R(Tp) + c_f_eff*(1-R(Tp))
    den, _ = quad(R, 0, Tp)
    return num/den
opt = minimize_scalar(C_PM, bounds=(50, 5*mu), method='bounded')
Tp_star = opt.x; C_PM_star = opt.fun
print(f"[Preventiva] T_p* = {Tp_star:.0f} h ({Tp_star/mu:.2f}*MTTF) | tasa = {C_PM_star:.3f} MXN/h"
      f" | ahorro vs reactiva = {100*(C_R-C_PM_star)/C_R:.1f}%")

# ---- Politica PREDICTIVA: captura fraccion kappa de la vida, falla con prob q ----
# Frontera por calidad de prediccion: fijamos objetivo q=alpha; el buffer cuesta z_alpha*sigma_RUL
# de vida sacrificada -> kappa = 1 - CV_RUL * z_{1-alpha}. CV_RUL = sigma_RUL/mu.
alpha = 0.05
z = norm.ppf(1-alpha)
def C_PdM(CV_RUL, q=alpha):
    kappa = max(1e-3, 1 - CV_RUL*z)          # fraccion de vida capturada
    num = c_p*(1-q) + c_f_eff*q
    den = mu*((1-q)*kappa + q)
    return num/den, kappa
print("\n[Predictiva] segun calidad de prediccion (CV_RUL = sigma_RUL/MTTF):")
print("  CV_RUL  kappa   tasa     ahorro_vs_React  ahorro_vs_Prev")
for CV in [0.40, 0.30, 0.20, 0.10, 0.05, 0.01]:
    c, k = C_PdM(CV)
    print(f"  {CV:4.2f}   {k:5.3f}  {c:6.3f}    {100*(C_R-c)/C_R:6.1f}%        {100*(C_PM_star-c)/C_PM_star:6.1f}%")

# limite ideal (prediccion perfecta)
C_ideal = c_p/mu
print(f"\n[Ideal]  prediccion perfecta: tasa = {C_ideal:.3f} | ahorro vs reactiva = {100*(C_R-C_ideal)/C_R:.1f}% (= 1 - c_p/c_f_eff = {100*(1-c_p/c_f_eff):.1f}%)")

# ---- Curva de aprendizaje (streaming): sigma_RUL baja con fallas observadas N ----
# CV_RUL(N) = CV_inf + A/sqrt(N).  Asintota CV_inf (ruido irreducible) + termino ~1/sqrt(N).
CV_inf, A = 0.06, 1.2
print("\n[Streaming] ahorro vs reactiva conforme la flota acumula fallas observadas N:")
print("  N      CV_RUL  ahorro_vs_React")
for N in [5, 20, 50, 100, 300, 1000]:
    CV = CV_inf + A/np.sqrt(N)
    c,_ = C_PdM(CV)
    print(f"  {N:4d}   {CV:5.3f}   {100*(C_R-c)/C_R:6.1f}%")

# ---- Agregado de flota (anual) ----
n_units = 200          # unidades con esta posicion
H = 3000.0             # horas-motor/anio por unidad
CV_op = 0.15           # calidad de prediccion en operacion (madura)
c_op,_ = C_PdM(CV_op)
annual_React = C_R   * H * n_units
annual_PdM   = c_op  * H * n_units
print(f"\n[Flota] {n_units} unidades x {H:.0f} h/anio, CV_RUL={CV_op} (maduro):")
print(f"  costo anual reactiva   = {annual_React/1e6:.2f} M MXN")
print(f"  costo anual predictiva = {annual_PdM/1e6:.2f} M MXN")
print(f"  AHORRO ANUAL = {(annual_React-annual_PdM)/1e6:.2f} M MXN ({100*(annual_React-annual_PdM)/annual_React:.1f}%)")

# Descomposicion piezas vs unidades (consecuencial/catastrofico)
# parts rate: reactiva 1/mu ; predictiva 1/(kappa*mu) aprox (mas piezas, pero captura ~toda la vida)
_,k_op = C_PdM(CV_op)
parts_React = (1/mu)*H*n_units                 # piezas/anio
parts_PdM   = (1/(k_op*mu))*H*n_units
fail_React  = (1/mu)*H*n_units                 # fallas/anio (toda renovacion es por falla)
fail_PdM    = (alpha/( (1-alpha)*k_op+alpha ))*(H/mu)*n_units  # fracc. que aun falla
cat_avoided = phi*(fail_React-fail_PdM)*(c_cat-c_f)            # ahorro catastrofico ~unidades
print(f"\n  piezas/anio: reactiva={parts_React:.0f}  predictiva={parts_PdM:.0f}  (predictiva usa ~{100*(parts_PdM/parts_React-1):+.0f}% piezas)")
print(f"  fallas/anio: reactiva={fail_React:.0f}  predictiva={fail_PdM:.0f}  (evita {fail_React-fail_PdM:.0f} fallas)")
print(f"  ahorro catastrofico (~unidades): {cat_avoided/1e6:.2f} M MXN/anio")
