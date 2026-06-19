"""
Modelo de ahorro: reactivo (run-to-failure) vs preventivo por edad (optimo) vs predictivo (techo).
Todo desde renovacion-recompensa (Barlow-Proschan, Jardine-Tsang). Numeros reales.
"""
import numpy as np
from scipy.integrate import quad
from scipy.special import gamma as G
from scipy.optimize import minimize_scalar
rng = np.random.default_rng(1)

def weibull_R(t, beta, eta): return np.exp(-(t/eta)**beta)
def MTTF(beta, eta): return eta*G(1+1/beta)

def cost_rate_age(T, beta, eta, cp, cf):
    # C(T) = [cp R(T) + cf (1-R(T))] / ∫_0^T R dt
    if T <= 1e-9: return np.inf
    num = cp*weibull_R(T,beta,eta) + cf*(1-weibull_R(T,beta,eta))
    den,_ = quad(weibull_R, 0, T, args=(beta,eta), limit=200)
    return num/den if den>0 else np.inf

def optimal_age(beta, eta, cp, cf):
    # minimiza C(T); si el optimo se va al infinito (β<=1), devuelve T grande
    f = lambda lnT: cost_rate_age(np.exp(lnT), beta, eta, cp, cf)
    r = minimize_scalar(f, bounds=(np.log(1e-3*eta), np.log(50*eta)), method="bounded")
    Tstar = np.exp(r.x); return Tstar, f(r.x)

print("="*78)
print("TABLA 1 — Fraccion de AHORRO vs reactivo, por (beta, rho=cf/cp).  cp=1 (normaliza).")
print("  C_rtf = cf/MTTF (reactivo) ; C* = min_T C(T) (preventivo optimo)")
print("  techo predictivo (prediccion perfecta) = cp/MTTF  -> ahorro = 1 - 1/rho")
print("="*78)
eta=1.0
betas=[0.8,1.0,1.5,2.0,2.3,3.0]
rhos=[2,4,8]
print(f"{'beta':>5} | " + " | ".join(f"rho={r:<2}  T*/η  s_prev  s_techo" for r in rhos))
for b in betas:
    row=f"{b:>5} | "
    cells=[]
    for rho in rhos:
        cp=1.0; cf=rho*cp
        crtf = cf/MTTF(b,eta)
        Tstar, Cstar = optimal_age(b,eta,cp,cf)
        s_prev = 1 - Cstar/crtf
        s_ceil = 1 - 1/rho
        Tn = Tstar/eta if Tstar < 40*eta else np.inf
        Tn_s = f"{Tn:4.2f}" if np.isfinite(Tn) else " inf"
        cells.append(f"{Tn_s}  {s_prev*100:4.0f}%   {s_ceil*100:4.0f}%")
    print(row + " | ".join(cells))

print("\nLectura: beta<=1 (fallas aleatorias) -> T*->inf, ahorro preventivo ~0%.")
print("         El ahorro REQUIERE desgaste (beta>1) Y razon de costos alta.")

# ---------------- Ejemplos con dinero (MXN) ----------------
def report(name, beta, eta_h, cp, cf):
    crtf = cf/MTTF(beta,eta_h)
    Tstar,Cstar = optimal_age(beta,eta_h,cp,cf)
    floor = cp/MTTF(beta,eta_h)
    print(f"\n--- {name}: beta={beta}, eta={eta_h} h, cp={cp:,} cf={cf:,} MXN (rho={cf/cp:.1f}) ---")
    print(f"  MTTF={MTTF(beta,eta_h):.0f} h")
    print(f"  Costo/1000h:  reactivo={1000*crtf:,.0f}  preventivo-optimo={1000*Cstar:,.0f}  techo-predictivo={1000*floor:,.0f} MXN")
    print(f"  T* optimo = {Tstar:.0f} h ({100*Tstar/eta_h:.0f}% de eta)")
    print(f"  Ahorro preventivo vs reactivo = {100*(1-Cstar/crtf):.0f}%   |   techo predictivo = {100*(1-floor/crtf):.0f}%")

print("\n"+"="*78); print("EJEMPLOS CON DINERO (camion pesado, MXN)"); print("="*78)
# Balata: cp=parts+labor programado; cf=+grua+downtime+rotor (falla en ruta)
report("Balata freno", 2.3, 1500, cp=2700, cf=22700)
# DPF/aftertreatment: derate deja varada la unidad
report("DPF/aftertreatment", 2.0, 4000, cp=9000, cf=80000)

# ---------------- Streaming: ramp-up del ahorro conforme llegan fallas ----------------
print("\n"+"="*78)
print("RAMP-UP EN STREAMING: el ahorro se realiza conforme se observan fallas")
print("  (politica plug-in con (beta,eta) estimados de n fallas vs oraculo C*)")
print("="*78)
beta_t, eta_t, cp, cf = 2.3, 1500.0, 2700.0, 22700.0
Tstar_oracle, Cstar_oracle = optimal_age(beta_t,eta_t,cp,cf)
crtf = cf/MTTF(beta_t,eta_t)

def weibull_mle(samples):
    # MLE Weibull (sin censura, para el ramp-up ilustrativo)
    def nll(p):
        b,e=np.exp(p[0]),np.exp(p[1])
        return -np.sum(np.log(b/e)+(b-1)*np.log(samples/e)-(samples/e)**b)
    from scipy.optimize import minimize
    r=minimize(nll,[np.log(2),np.log(np.mean(samples))],method="Nelder-Mead")
    return np.exp(r.x[0]),np.exp(r.x[1])

for n in [5,10,20,50,100,300]:
    reps=200; realized=[]
    for _ in range(reps):
        s = eta_t*(-np.log(rng.random(n)))**(1/beta_t)
        try:
            bh,eh = weibull_mle(s)
            Th,_ = optimal_age(bh,eh,cp,cf)
            realized.append(cost_rate_age(Th,beta_t,eta_t,cp,cf))  # costo REAL de la politica estimada
        except Exception:
            pass
    Cbar=np.mean(realized)
    s_real = 1 - Cbar/crtf
    s_oracle = 1 - Cstar_oracle/crtf
    print(f"  n={n:>3} fallas:  ahorro realizado={100*s_real:4.1f}%   (oraculo={100*s_oracle:.1f}%)   captura={100*s_real/s_oracle:4.0f}% del optimo")
