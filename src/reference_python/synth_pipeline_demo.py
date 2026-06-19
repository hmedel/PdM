"""
Demo funcional end-to-end sobre datos SINTETICOS, con verdad conocida.
Cadena: (1) frame J1939 -> decode (logica verificada) -> reloj de uso (horas-motor)
        (2) modelo forward independiente (Weibull-AFT + censura + truncamiento) -> eventos WS-A
        (3) pipeline bajo prueba: construir registros de supervivencia -> ajustar -> RECUPERAR params
        (4) demostrar el SESGO si se ignora censura o truncamiento.
Criterio de exito: recuperar (beta, eta0, gamma) dentro de IC bootstrap.
"""
import numpy as np
from scipy.optimize import minimize
rng = np.random.default_rng(20260615)

# ----------------------------------------------------------------------
# (1) Decoder J1939 (mismas funciones verificadas) — exercita decode->uso
# ----------------------------------------------------------------------
def extract_le(data, start_byte0, n):
    raw = 0
    for i in range(n):
        raw |= data[start_byte0 + i] << (8*i)
    return raw

def decode_hours(frame8):
    # HOURS PGN 65253: SPN 247 total engine hours, bytes 1-4, 0.05 h/bit
    raw = extract_le(frame8, 0, 4)
    if raw >= 0xFFFFFFFE: return None
    return 0.05 * raw

# sanity: 1500 h -> raw=30000=0x7530 -> LE bytes
h = 1500.0; raw = int(round(h/0.05))
frame = [raw & 0xFF, (raw>>8)&0xFF, (raw>>16)&0xFF, (raw>>24)&0xFF, 0,0,0,0]
assert abs(decode_hours(frame) - 1500.0) < 1e-9
print(f"[decode] HOURS frame {['0x%02X'%b for b in frame[:4]]} -> {decode_hours(frame)} h  (reloj de uso OK)")

# ----------------------------------------------------------------------
# (2) Modelo forward INDEPENDIENTE (ground truth)
#     Vida de balata ~ Weibull(beta, eta_i), AFT: eta_i = eta0 * exp(gamma * x)
#     x = severidad de ruta en [0,1]. Censura por ventana. Truncamiento izq. en fraccion.
# ----------------------------------------------------------------------
BETA_T, ETA0_T, GAMMA_T = 2.3, 1500.0, -0.5     # VERDAD (horas-motor)
M = 4000                                         # instancias de componente
f_trunc = 0.30                                   # fraccion con truncamiento por la izquierda

x = rng.uniform(0, 1, M)                          # severidad de ruta (covariable)
eta = ETA0_T * np.exp(GAMMA_T * x)
L = eta * rng.weibull(BETA_T, M)                  # vida real (Weibull) por instancia
C = rng.uniform(500, 3500, M)                     # tiempo de censura (ventana de obs.)

# truncamiento por la izquierda: entramos a observar a una edad a>0, condicionando L>a
a = np.zeros(M)
trunc_mask = rng.uniform(0,1,M) < f_trunc
a_prop = rng.uniform(0, 0.6*eta, M)
keep = ~trunc_mask | (L > a_prop)                 # si truncada, requiere haber sobrevivido a 'a'
a[trunc_mask] = a_prop[trunc_mask]
x, eta, L, C, a = x[keep], eta[keep], L[keep], C[keep], a[keep]

t = np.minimum(L, C)                              # edad de salida observada
d = (L <= C).astype(int)                          # 1 = falla, 0 = censurado
# (a, t, d) es exactamente la tripleta WS-A: entry_age, exit_age, status
n = len(t)
print(f"[synth] {n} instancias | fallas={d.sum()} censuradas={(d==0).sum()} truncadas={(a>0).sum()}")

# ----------------------------------------------------------------------
# (3) Pipeline bajo prueba: MLE Weibull-AFT con censura por la derecha + trunc. izq.
#     loglik_i = d*(log b - b*log eta_i + (b-1)*log t) - (t/eta_i)^b + (a/eta_i)^b
# ----------------------------------------------------------------------
def negloglik(theta, x, t, d, a):
    b   = np.exp(theta[0])          # beta>0
    e0  = np.exp(theta[1])          # eta0>0
    g   = theta[2]                  # gamma
    eta_i = e0 * np.exp(g * x)
    zt = (t/eta_i)**b
    za = np.where(a>0, (a/eta_i)**b, 0.0)
    ll = d*(np.log(b) - b*np.log(eta_i) + (b-1)*np.log(t)) - zt + za
    return -np.sum(ll)

def fit(x, t, d, a):
    r = minimize(negloglik, x0=[np.log(2.0), np.log(1000.0), 0.0],
                 args=(x,t,d,a), method="Nelder-Mead",
                 options=dict(xatol=1e-6, fatol=1e-6, maxiter=20000))
    b, e0, g = np.exp(r.x[0]), np.exp(r.x[1]), r.x[2]
    return b, e0, g

b_hat, e0_hat, g_hat = fit(x, t, d, a)

# IC por bootstrap (60 remuestreos)
B = 60; boots = []
for _ in range(B):
    idx = rng.integers(0, n, n)
    boots.append(fit(x[idx], t[idx], d[idx], a[idx]))
boots = np.array(boots)
ci = lambda j: (np.percentile(boots[:,j],2.5), np.percentile(boots[:,j],97.5))

print("\n=== RECUPERACION (pipeline correcto: censura + truncamiento) ===")
print(f"  beta :  verdad={BETA_T:.3f}   est={b_hat:.3f}   IC95=[{ci(0)[0]:.3f}, {ci(0)[1]:.3f}]")
print(f"  eta0 :  verdad={ETA0_T:.1f}  est={e0_hat:.1f}  IC95=[{ci(1)[0]:.1f}, {ci(1)[1]:.1f}]")
print(f"  gamma:  verdad={GAMMA_T:.3f}  est={g_hat:.3f}   IC95=[{ci(2)[0]:.3f}, {ci(2)[1]:.3f}]")

# ----------------------------------------------------------------------
# (4) DEMOSTRACION DE SESGO: por que los campos del esquema WS-A importan
# ----------------------------------------------------------------------
# (4a) Ignorar CENSURA: tratar todo como falla (d=1)
b_c, e0_c, g_c = fit(x, t, np.ones_like(d), a)
# (4b) Ignorar TRUNCAMIENTO: poner a=0
b_tr, e0_tr, g_tr = fit(x, t, d, np.zeros_like(a))

print("\n=== SESGO si se ignora la estructura (mismo dato, fit mal especificado) ===")
print(f"  ignorar censura  -> beta={b_c:.3f} (verdad {BETA_T}), eta0={e0_c:.1f} (verdad {ETA0_T})   [subestima vida]")
print(f"  ignorar trunc.   -> beta={b_tr:.3f} (verdad {BETA_T}), eta0={e0_tr:.1f} (verdad {ETA0_T})")
err = lambda v,tru: 100*(v-tru)/tru
print(f"\n  Error en eta0:  correcto={err(e0_hat,ETA0_T):+.1f}%   ignorar-censura={err(e0_c,ETA0_T):+.1f}%   ignorar-trunc={err(e0_tr,ETA0_T):+.1f}%")
