#!/usr/bin/env python3
"""
Fetcher de rutas reales desde el servicio Valhalla (rutas de México).

Llama a /route (costing=truck con parámetros del vehículo), decodifica la polilínea (precisión 6),
pide la elevación con /height, y construye un PERFIL DE RUTA por segmentos (distancia, pendiente,
altitud, velocidad, clase de vía) que el simulador Julia consume como RouteSource. El perfil se
cachea en out/routes/<name>.json (reproducible, sin re-pegarle al servicio).

Uso:
  python3 tools/valhalla_route.py --name cdmx_puebla \
      --loc 19.4326,-99.1332 --loc 19.0413,-98.2062 \
      --weight 25 --base https://valhalla.ws2.phaimat.com

Sustento: elevación y geometría de la ruta vienen del servicio Valhalla (OSM + DEM); la pendiente
se deriva de Δaltitud/distancia (haversine). La velocidad por tramo = longitud/tiempo de la maniobra.
"""
import argparse, json, math, urllib.request, sys, os

def post(url, payload, timeout=60):
    req = urllib.request.Request(url, data=json.dumps(payload).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)

def decode_polyline(enc, precision=6):
    """Decodifica una polilínea Valhalla (precisión 6 por defecto) -> [(lat, lon), ...]."""
    factor = 10 ** precision
    coords, idx, lat, lon = [], 0, 0, 0
    while idx < len(enc):
        for is_lon in (False, True):
            shift, result = 0, 0
            while True:
                b = ord(enc[idx]) - 63; idx += 1
                result |= (b & 0x1f) << shift; shift += 5
                if b < 0x20: break
            d = ~(result >> 1) if (result & 1) else (result >> 1)
            if is_lon: lon += d
            else:      lat += d
        coords.append((lat / factor, lon / factor))
    return coords

def haversine_km(a, b):
    R = 6371.0
    lat1, lon1, lat2, lon2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    dlat, dlon = lat2 - lat1, lon2 - lon1
    h = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlon/2)**2
    return 2 * R * math.asin(math.sqrt(h))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", required=True)
    ap.add_argument("--loc", action="append", required=True, help="lat,lon (repetir)")
    ap.add_argument("--base", default="https://valhalla.ws2.phaimat.com")
    ap.add_argument("--weight", type=float, default=25.0)
    ap.add_argument("--seg-km", type=float, default=1.5, help="tamaño de segmento agregado")
    ap.add_argument("--max-height-pts", type=int, default=450)
    args = ap.parse_args()

    locs = [{"lat": float(x.split(",")[0]), "lon": float(x.split(",")[1]), "type": "break"}
            for x in args.loc]
    route_req = {
        "locations": locs, "costing": "truck",
        "costing_options": {"truck": {"weight": args.weight, "height": 3.8, "width": 2.5,
                                       "length": 15.0, "axle_load": 8.0, "hazmat": False}},
        "directions_options": {"units": "km"}, "format": "json",
    }
    print(f"[valhalla] /route truck {args.name} …", file=sys.stderr)
    rt = post(f"{args.base}/route", route_req)
    leg = rt["trip"]["legs"][0]
    pts = decode_polyline(leg["shape"], 6)
    summ = rt["trip"]["summary"]
    total_km = summ["length"]

    # velocidad por vértice desde las maniobras (longitud/tiempo)
    vspeed = [60.0] * len(pts)
    vclass = ["primary"] * len(pts)
    for m in leg["maneuvers"]:
        b, e = m["begin_shape_index"], m["end_shape_index"]
        spd = (m["length"] / (m["time"] / 3600)) if m.get("time", 0) > 0 else 60.0
        spd = max(8.0, min(spd, 110.0))
        hw = m.get("travel_type") == "drive" and any("hw" in (sn or "").lower() or "auto" in (sn or "").lower()
                                                      for sn in m.get("street_names", []))
        for i in range(b, min(e + 1, len(pts))):
            vspeed[i] = spd
            vclass[i] = "highway" if spd > 75 else ("primary" if spd > 40 else "urban")

    # elevación: submuestrear para no exceder el límite de /height
    step = max(1, len(pts) // args.max_height_pts)
    sample_idx = list(range(0, len(pts), step))
    if sample_idx[-1] != len(pts) - 1: sample_idx.append(len(pts) - 1)
    print(f"[valhalla] /height {len(sample_idx)} puntos …", file=sys.stderr)
    hres = post(f"{args.base}/height", {"shape": [{"lat": pts[i][0], "lon": pts[i][1]} for i in sample_idx]})
    heights = hres["height"]
    # interpolar altitud a todos los vértices
    alt = [0.0] * len(pts)
    for k in range(len(sample_idx) - 1):
        i0, i1 = sample_idx[k], sample_idx[k + 1]
        h0, h1 = heights[k], heights[k + 1]
        for i in range(i0, i1 + 1):
            f = 0 if i1 == i0 else (i - i0) / (i1 - i0)
            alt[i] = h0 + f * (h1 - h0)

    # construir segmentos agregados (~seg-km) con pendiente
    segs, acc_km, start_i, prev = [], 0.0, 0, pts[0]
    for i in range(1, len(pts)):
        d = haversine_km(prev, pts[i]); prev = pts[i]; acc_km += d
        if acc_km >= args.seg_km or i == len(pts) - 1:
            dz = alt[i] - alt[start_i]
            grade = 100 * dz / (acc_km * 1000) if acc_km > 0 else 0.0
            grade = max(-9.0, min(9.0, grade))
            spd = sum(vspeed[start_i:i + 1]) / max(1, (i + 1 - start_i))
            cls = max(set(vclass[start_i:i + 1]), key=vclass[start_i:i + 1].count)
            segs.append({"dist_km": round(acc_km, 4), "grade_pct": round(grade, 3),
                         "altitude_m": round((alt[i] + alt[start_i]) / 2, 1),
                         "speed_kph": round(spd, 1), "road_class": cls})
            acc_km, start_i = 0.0, i

    out = {"name": args.name, "source": "valhalla", "base": args.base,
           "weight_t": args.weight,
           "total_km": round(total_km, 2), "n_segments": len(segs),
           "min_alt": round(min(alt), 1), "max_alt": round(max(alt), 1),
           "has_toll": summ.get("has_toll"), "has_highway": summ.get("has_highway"),
           "locations": [(l["lat"], l["lon"]) for l in locs], "segments": segs}
    os.makedirs("out/routes", exist_ok=True)
    path = f"out/routes/{args.name}.json"
    json.dump(out, open(path, "w"), ensure_ascii=False)
    print(f"[valhalla] {args.name}: {total_km:.1f} km, {len(segs)} segs, "
          f"altitud {out['min_alt']:.0f}–{out['max_alt']:.0f} m → {path}", file=sys.stderr)

if __name__ == "__main__":
    main()
