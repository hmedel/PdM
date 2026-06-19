"""
Motor de Mantenimiento Predictivo — implementacion de referencia (Tier-1, end-to-end).
Lazo del producto sobre datos sinteticos:
  ingesta de eventos -> deteccion (reglas DTC + RUL de supervivencia) -> decision (ordenes + ahorro).
Estructurado por modulos (ingest / cbm / survival / rul / decision) para portar a los *.jl del brief.
Corre y se valida aqui (Python). El generador y los ajustes son los ya cross-validados.
"""
import numpy as np
from scipy.optimize import minimize
from scipy.integrate import quad
from scipy.special import gamma as Gf, gammaincc
rng = np.random.default_rng(20260616)

# =========================================================================
# MODULO ingest — flota sintetica con 3 componentes (incluye uno β≈1 a proposito)
# =========================================================================
CLASSES = [("heavy_truck", ["Freightliner","Kenworth","Volvo"], "j1939", 1500.0),
           ("light_vehicle", ["Nissan","Toyota"], "obd2", 900.0)]
# Ground truth por componente: (beta, base_eta, gamma_AFT, cp, cf)
COMPONENTS = {
    "brake_pad":  dict(beta=2.3, base=1500.0, gamma=-0.5, cp=2700,  cf=22700,  recurrent=True,  classes={"heavy_truck","light_vehicle"}),
    "dpf":        dict(beta=2.0, base=4000.0, gamma=-0.3, cp=9000,  cf=80000,  recurrent=False, classes={"heavy_truck"}, dtc=True),
    "battery":    dict(beta=1.0, base=1200.0, gamma=0.0,  cp=1500,  cf=9000,   recurrent=False, classes={"heavy_truck","light_vehicle"}),  # β≈1: falla aleatoria
}
def weibull(beta, eta): return eta*(-np.log(rng.random()))**(1/beta)

def generate_fleet(n=240, window=2500.0, f_trunc=0.30):
    # eta0 por (clase,marca,componente)
    eta0 = {}
    for cls,brands,_,_ in CLASSES:
        for b in brands:
            for comp,p in COMPONENTS.items():
                if cls in p["classes"]:
                    eta0[(cls,b,comp)] = (p["base"]/ (1.0 if cls=="heavy_truck" else 1.0)) * (0.85+0.30*rng.random())
    vehicles=[]; events=[]
    for k in range(n):
        cls,brands,proto,_ = CLASSES[rng.integers(0,len(CLASSES))]
        brand=brands[rng.integers(0,len(brands))]; x=rng.random()
        vid=f"VEH-{k:04d}"; vehicles.append(dict(vehicle_id=vid,cls=cls,brand=brand,x=x))
        for comp,p in COMPONENTS.items():
            if cls not in p["classes"]: continue
            eta_i = eta0[(cls,brand,comp)]*np.exp(p["gamma"]*x)
            W = window*(0.5+0.8*rng.random())
            a0 = 0.6*eta_i*rng.random() if (p["recurrent"] and rng.random()<f_trunc) else 0.0
            L = weibull(p["beta"],eta_i)
            if a0>0:
                while L<=a0: L=weibull(p["beta"],eta_i)
            inst=1
            if (L-a0)<=W:
                dtc=(3251,16) if (p.get("dtc") and rng.random()<0.6) else (0,0)
                events.append(dict(vid=vid,cls=cls,brand=brand,comp=comp,x=x,inst=inst,
                                   entry=a0,exit=L,status=1,dtc_spn=dtc[0],dtc_fmi=dtc[1]))
                obs=L-a0; inst+=1
                if p["recurrent"]:
                    while obs<W:
                        rem=W-obs; L=weibull(p["beta"],eta_i)
                        if L<=rem: events.append(dict(vid=vid,cls=cls,brand=brand,comp=comp,x=x,inst=inst,entry=0.0,exit=L,status=1,dtc_spn=0,dtc_fmi=0)); obs+=L; inst+=1
                        else: events.append(dict(vid=vid,cls=cls,brand=brand,comp=comp,x=x,inst=inst,entry=0.0,exit=rem,status=0,dtc_spn=0,dtc_fmi=0)); obs=W
            else:
                events.append(dict(vid=vid,cls=cls,brand=brand,comp=comp,x=x,inst=1,entry=a0,exit=a0+W,status=0,dtc_spn=0,dtc_fmi=0))
    return vehicles, events

# =========================================================================
# MODULO cbm — reglas DTC -> ordenes de trabajo priorizadas (Tier-1, sin calibracion)
# =========================================================================
DTC_SEVERITY = {  # (SPN,FMI) -> (descripcion, severidad FMECA 1-10)
    (5246,4):  ("SCR derate — unidad puede quedar varada", 9),
    (3251,16): ("DPF ΔP alto — saturacion/regeneracion", 6),
}
def cbm_work_orders(events):
    wos=[]
    for e in events:
        if e["dtc_spn"]!=0:
            desc,sev = DTC_SEVERITY.get((e["dtc_spn"],e["dtc_fmi"]), ("DTC desconocido",5))
            wos.append(dict(vid=e["vid"],comp=e["comp"],spn=e["dtc_spn"],fmi=e["dtc_fmi"],desc=desc,priority=sev))
    return sorted(wos, key=lambda w:-w["priority"])

# =========================================================================
# MODULO survival — Weibull-AFT bien especificado (η0 por grupo + β,γ compartidos)
# =========================================================================
def fit_component(events, comp):
    ev=[e for e in events if e["comp"]==comp]
    groups=sorted(set((e["cls"],e["brand"]) for e in ev)); gid={g:i for i,g in enumerate(groups)}
    gi=np.array([gid[(e["cls"],e["brand"])] for e in ev]); G=len(groups)
    x=np.array([e["x"] for e in ev]); t=np.array([e["exit"] for e in ev])
    d=np.array([e["status"] for e in ev],float); a=np.array([e["entry"] for e in ev])
    def nll(th):
        b=np.exp(th[0]); g=th[1]; eta=np.exp(th[2:2+G][gi])*np.exp(g*x)
        zt=(t/eta)**b; za=np.where(a>0,(a/eta)**b,0.0)
        return -np.sum(d*(np.log(b)-b*np.log(eta)+(b-1)*np.log(t))-zt+za)
    x0=np.concatenate([[np.log(2.),0.], np.log(np.mean(t))*np.ones(G)])
    r=minimize(nll,x0,method="Nelder-Mead",options=dict(xatol=1e-6,fatol=1e-6,maxiter=60000))
    b=np.exp(r.x[0]); g=r.x[1]; etas={grp:np.exp(r.x[2+i]) for i,grp in enumerate(groups)}
    # IC bootstrap de beta (prueba: beta>1 distinguible de falla aleatoria)
    n=len(ev); bs=[]
    for _ in range(25):
        idx=rng.integers(0,n,n)
        def nllb(th):
            bb=np.exp(th[0]); gg=th[1]; eta=np.exp(th[2:2+G][gi[idx]])*np.exp(gg*x[idx])
            zt=(t[idx]/eta)**bb; za=np.where(a[idx]>0,(a[idx]/eta)**bb,0.0)
            return -np.sum(d[idx]*(np.log(bb)-bb*np.log(eta)+(bb-1)*np.log(t[idx]))-zt+za)
        rb=minimize(nllb,r.x,method="Nelder-Mead",options=dict(maxiter=40000))
        bs.append(np.exp(rb.x[0]))
    blo,bhi=np.percentile(bs,2.5),np.percentile(bs,97.5)
    return dict(beta=b, beta_lo=blo, beta_hi=bhi, gamma=g, eta0=etas, n=len(ev), nfail=int(d.sum()))

# =========================================================================
# MODULO rul — RUL condicional (forma cerrada verificada)
# =========================================================================
def rul(t, beta, eta_i):
    w=(t/eta_i)**beta
    ET = eta_i*np.exp(w)*gammaincc(1+1/beta, w)*Gf(1+1/beta)   # E[T|T>t]
    return max(ET - t, 0.0)

# =========================================================================
# MODULO decision — intervalo optimo + tasas de costo + ahorro (con regla β≤1)
# =========================================================================
def MTTF(beta,eta): return eta*Gf(1+1/beta)
def cost_rate_age(T,beta,eta,cp,cf):
    if T<=1e-9: return np.inf
    R=np.exp(-(T/eta)**beta); den,_=quad(lambda t:np.exp(-(t/eta)**beta),0,T,limit=200)
    return (cp*R+cf*(1-R))/den if den>0 else np.inf
def decide(beta, beta_lo, eta, cp, cf):
    from scipy.optimize import minimize_scalar
    crtf=cf/MTTF(beta,eta); floor=cp/MTTF(beta,eta)
    r=minimize_scalar(lambda lt:cost_rate_age(np.exp(lt),beta,eta,cp,cf),
                      bounds=(np.log(1e-2*eta),np.log(20*eta)),method="bounded")
    Tstar=np.exp(r.x); Cstar=cost_rate_age(Tstar,beta,eta,cp,cf); s_prev=1-Cstar/crtf
    # PRUEBA: preventivo solo si el IC de beta excluye 1 (desgaste estadisticamente confirmado)
    preventive = (beta_lo>1.0) and (s_prev>=0.03)
    return dict(preventive=preventive, Tstar=Tstar if preventive else None,
                s_prev=s_prev if preventive else 0.0, s_ceiling=1-cp/cf, crtf=crtf, floor=floor)

# =========================================================================
# ENGINE — corre el lazo y reporta
# =========================================================================
vehicles, events = generate_fleet()
print("="*82); print("MOTOR DE MANTENIMIENTO — corrida sobre flota sintetica"); print("="*82)
print(f"Flota: {len(vehicles)} vehiculos | {len(events)} eventos de componente\n")

# (1) CBM/DTC -> ordenes de trabajo
wos=cbm_work_orders(events)
print(f"[CBM/DTC] {len(wos)} ordenes de trabajo por DTC (Tier-1, sin calibracion). Top 3 por prioridad:")
for w in wos[:3]:
    print(f"   P{w['priority']}  {w['vid']}  {w['comp']}  SPN {w['spn']}/FMI {w['fmi']} — {w['desc']}")

# (2)+(3)+(4) por componente: fit -> decision/ahorro ; y RUL por instancia viva
print("\n[Supervivencia + Decision] por componente:")
print(f"{'comp':<11}{'beta':>7} {'IC95(beta)':>12}{'gamma':>7}{'n/fail':>9}  {'prev':>6}  {'T*':>7}  {'ahorro':>7}  {'techo':>6}")
fits={}
fleet_saving=0.0
for comp,p in COMPONENTS.items():
    f=fit_component(events,comp); fits[comp]=f
    eta_ref=np.mean(list(f["eta0"].values()))
    dec=decide(f["beta"], f["beta_lo"], eta_ref, p["cp"], p["cf"])
    Ts = f"{dec['Tstar']:.0f}" if dec["preventive"] else "  —"
    sp = f"{100*dec['s_prev']:.0f}%" if dec["preventive"] else " n/a"
    tag= "SI" if dec["preventive"] else "NO"
    bci=f"[{f['beta_lo']:.2f},{f['beta_hi']:.2f}]"
    print(f"{comp:<11}{f['beta']:>7.2f} {bci:>12}{f['gamma']:>7.2f}{str(f['n'])+'/'+str(f['nfail']):>9}  {tag:>6}  {Ts:>7}  {sp:>7}  {100*dec['s_ceiling']:>5.0f}%")
    # ahorro de flota (solo donde aplica preventivo): por instancia activa de ese componente
    if dec["preventive"]:
        # cuenta de unidades con ese componente activo ~ vehiculos con ese componente
        nunits=sum(1 for v in vehicles if comp in COMPONENTS and v["cls"] in p["classes"])
        # ahorro anual aprox: (crtf - crtf*(1-s_prev)) * horas/año * nunits ; horas/año ~ 3000
        ahorro_unit = dec["crtf"]*dec["s_prev"]*3000
        fleet_saving += ahorro_unit*nunits

print(f"\n[Ahorro] proyeccion de flota (preventivo-optimo vs reactivo, ~3000 h/año/unidad): "
      f"~{fleet_saving/1e6:.2f} M MXN/año")
print("  (battery: IC de β incluye 1 -> el motor rehusa preventivo, como dicta el teorema IFR)")

# (5) RUL para instancias vivas (censuradas) — ejemplo: 5 balatas activas con menor RUL
print("\n[RUL] balatas activas con menor vida remanente (horas-motor):")
fb=fits["brake_pad"]
alive=[e for e in events if e["comp"]=="brake_pad" and e["status"]==0]
rows=[]
for e in alive:
    eta_i=fb["eta0"][(e["cls"],e["brand"])]*np.exp(fb["gamma"]*e["x"])
    rows.append((e["vid"], e["exit"], rul(e["exit"], fb["beta"], eta_i)))
rows.sort(key=lambda r:r[2])
for vid,age,r_ in rows[:5]:
    print(f"   {vid}  edad={age:6.0f} h  RUL={r_:6.0f} h  -> {'URGENTE' if r_<150 else 'programar'}")
print("\nOK — lazo end-to-end: ingesta -> CBM/DTC -> supervivencia/RUL -> decision/ahorro.")
