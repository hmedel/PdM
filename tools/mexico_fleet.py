#!/usr/bin/env python3
"""
Genera una flota de RUTAS REALES de México vía Valhalla, con ciudades reales y **pesos casados al
corredor**: los corredores de puerto/frontera/industriales mueven más carga (camión más pesado);
los regionales/altiplano, menos. La selección es aleatoria (con semilla, reproducible) para que la
flota sea creíble y variada.

Uso:  python3 tools/mexico_fleet.py --n 6 --seed 7
Llama a tools/valhalla_route.py por cada ruta → out/routes/<name>.json
"""
import argparse, random, subprocess, sys, os

CITIES = {
    "CDMX": (19.4326, -99.1332), "Guadalajara": (20.6597, -103.3496),
    "Monterrey": (25.6866, -100.3161), "Puebla": (19.0413, -98.2062),
    "Manzanillo": (19.0522, -104.3158), "Veracruz": (19.1738, -96.1342),
    "NuevoLaredo": (27.4769, -99.5164), "Queretaro": (20.5888, -100.3899),
    "Toluca": (19.2826, -99.6557), "Tijuana": (32.5149, -117.0382),
    "Mexicali": (32.6245, -115.4523), "Chihuahua": (28.6353, -106.0889),
    "CdJuarez": (31.6904, -106.4245), "Leon": (21.1250, -101.6860),
    "SLP": (22.1565, -100.9855), "Mazatlan": (23.2494, -106.4111),
}

# Corredores reales con su rol de carga -> peso base (t). Puerto/frontera mueven más.
CORRIDORS = [
    ("Manzanillo", "Guadalajara", 31.0, "puerto-import"),
    ("Manzanillo", "CDMX",        30.0, "puerto-import"),
    ("Veracruz",   "CDMX",        30.0, "puerto-import"),     # gran descenso desde 2240 m
    ("Monterrey",  "NuevoLaredo", 32.0, "frontera-export"),
    ("CdJuarez",   "Chihuahua",   29.0, "frontera-desierto"),
    ("Tijuana",    "Mexicali",    27.0, "frontera-desierto"),
    ("CDMX",       "Queretaro",   26.0, "industrial-bajio"),
    ("Queretaro",  "Leon",        25.0, "industrial-bajio"),
    ("Guadalajara","CDMX",        28.0, "troncal"),
    ("SLP",        "Monterrey",   27.0, "troncal"),
    ("CDMX",       "Puebla",      24.0, "regional"),
    ("CDMX",       "Toluca",      21.0, "altiplano-montana"),  # alta altitud
    ("Mazatlan",   "Guadalajara", 26.0, "costa-sierra"),
]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=6)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--base", default="https://valhalla.ws2.phaimat.com")
    args = ap.parse_args()
    rnd = random.Random(args.seed)

    chosen = rnd.sample(CORRIDORS, min(args.n, len(CORRIDORS)))
    here = os.path.dirname(os.path.abspath(__file__))
    fetcher = os.path.join(here, "valhalla_route.py")
    print(f"[flota] {len(chosen)} rutas reales de México (semilla {args.seed}):", file=sys.stderr)
    ok = 0
    for o, d, base_w, role in chosen:
        weight = round(base_w + rnd.uniform(-2.5, 2.5), 1)     # jitter de carga, casado al corredor
        name = f"{o}_{d}".lower()
        olat, olon = CITIES[o]; dlat, dlon = CITIES[d]
        print(f"  {o}→{d}  [{role}]  {weight} t", file=sys.stderr)
        r = subprocess.run([sys.executable, fetcher, "--name", name,
                            "--loc", f"{olat},{olon}", "--loc", f"{dlat},{dlon}",
                            "--weight", str(weight), "--base", args.base])
        ok += (r.returncode == 0)
    print(f"[flota] {ok}/{len(chosen)} rutas generadas en out/routes/", file=sys.stderr)

if __name__ == "__main__":
    main()
