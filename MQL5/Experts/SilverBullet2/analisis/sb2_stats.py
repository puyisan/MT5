#!/usr/bin/env python3
"""Estadísticas y veredicto del protocolo de SilverBullet2 a partir del registro CSV del EA.

Uso:
    python3 sb2_stats.py SilverBullet2_operaciones_backtest.csv --fase diseno
    python3 sb2_stats.py SB2_validacion.csv --fase validacion
    python3 sb2_stats.py archivo.csv --desde 2021-01-01 --hasta 2024-12-31   (sin veredicto)

Solo usa la biblioteca estándar de Python (sirve en el Mac sin instalar nada).
Los criterios están fijados en PROTOCOLO.md ANTES de ver resultados: no los cambies después.
"""
import argparse
import csv
import math
import random
import sys
from collections import defaultdict
from datetime import datetime

# --- criterios del protocolo (idénticos a PROTOCOLO.md) ---------------------------------
CRITERIOS = {
    "diseno": {"desde": "2021-01-01", "hasta": "2024-12-31",
               "n_min": 100, "pf_min": 1.20, "t_min": 2.0, "ic_pos": True,
               "anios_pos_min": 3, "dd_max": 20.0},
    "validacion": {"desde": "2025-01-01", "hasta": "2026-11-07",
                   "n_min": 30, "pf_min": 1.10, "t_min": None, "ic_pos": False,
                   "anios_pos_min": None, "dd_max": 15.0},
}
BOOT = 10000
SEED = 20261111


def leer(path, desde, hasta):
    filas = []
    with open(path, newline="", encoding="latin-1") as fh:
        for row in csv.DictReader(fh):
            try:
                t = datetime.strptime(row["abierta"].strip(), "%Y-%m-%d %H:%M:%S")
            except (KeyError, ValueError):
                continue
            if desde and t < desde:
                continue
            if hasta and t > hasta:
                continue
            row["_t"] = t
            row["_usd"] = float(row["usd"] or 0)
            row["_r"] = float(row["r"]) if row.get("r", "").strip() else None
            row["_bal"] = float(row["balance"]) if row.get("balance", "").strip() else None
            filas.append(row)
    filas.sort(key=lambda r: r["_t"])
    return filas


def pf(usd):
    gp = sum(x for x in usd if x > 0)
    gl = -sum(x for x in usd if x < 0)
    return gp / gl if gl > 0 else (float("inf") if gp > 0 else 0.0)


def media_sd(xs):
    n = len(xs)
    if n == 0:
        return 0.0, 0.0
    m = sum(xs) / n
    sd = math.sqrt(sum((x - m) ** 2 for x in xs) / (n - 1)) if n > 1 else 0.0
    return m, sd


def ic_bootstrap(xs, b=BOOT, seed=SEED):
    if len(xs) < 2:
        return (float("nan"), float("nan"))
    rnd = random.Random(seed)
    n = len(xs)
    medias = sorted(sum(rnd.choice(xs) for _ in range(n)) / n for _ in range(b))
    return medias[int(0.025 * b)], medias[int(0.975 * b) - 1]


def max_dd_pct(filas):
    if not filas or filas[0]["_bal"] is None:
        return float("nan")
    bal0 = filas[0]["_bal"] - filas[0]["_usd"]
    pico, dd = bal0, 0.0
    for r in filas:
        b = r["_bal"]
        pico = max(pico, b)
        dd = max(dd, 100.0 * (pico - b) / pico if pico > 0 else 0.0)
    return dd


def racha_perdidas(usd):
    best = cur = 0
    for x in usd:
        cur = cur + 1 if x < 0 else 0
        best = max(best, cur)
    return best


def tabla(titulo, grupos):
    print(f"\n{titulo}")
    print(f"  {'grupo':<12}{'n':>5}{'neto USD':>11}{'PF':>7}{'R medio':>9}{'acierto':>9}")
    for k in sorted(grupos):
        g = grupos[k]
        usd = [r["_usd"] for r in g]
        rs = [r["_r"] for r in g if r["_r"] is not None]
        m, _ = media_sd(rs)
        win = 100.0 * sum(1 for x in usd if x > 0) / len(usd)
        p = pf(usd)
        print(f"  {str(k):<12}{len(g):>5}{sum(usd):>11.2f}{(p if p != float('inf') else 99):>7.2f}{m:>9.3f}{win:>8.1f}%")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("csv")
    ap.add_argument("--fase", choices=["diseno", "validacion"])
    ap.add_argument("--desde")
    ap.add_argument("--hasta")
    a = ap.parse_args()

    crit = CRITERIOS.get(a.fase) if a.fase else None
    desde_s = a.desde or (crit and crit["desde"])
    hasta_s = a.hasta or (crit and crit["hasta"])
    desde = datetime.strptime(desde_s, "%Y-%m-%d") if desde_s else None
    hasta = datetime.strptime(hasta_s + " 23:59:59", "%Y-%m-%d %H:%M:%S") if hasta_s else None

    filas = leer(a.csv, desde, hasta)
    if not filas:
        sys.exit("No hay operaciones en el periodo.")
    versiones = sorted({r.get("version", "") for r in filas})
    usd = [r["_usd"] for r in filas]
    rs = [r["_r"] for r in filas if r["_r"] is not None]
    n = len(filas)
    m, sd = media_sd(rs)
    t = m / (sd / math.sqrt(len(rs))) if sd > 0 and len(rs) > 1 else 0.0
    lo, hi = ic_bootstrap(rs)
    dd = max_dd_pct(filas)
    meses = max(1.0, (filas[-1]["_t"] - filas[0]["_t"]).days / 30.44)
    p = pf(usd)
    anios = defaultdict(list)
    for r in filas:
        anios[r["_t"].year].append(r)
    anios_pos = sum(1 for g in anios.values() if sum(x["_usd"] for x in g) > 0)

    print(f"Archivo: {a.csv}   versión(es): {', '.join(versiones)}")
    print(f"Periodo: {desde_s or filas[0]['_t'].date()} a {hasta_s or filas[-1]['_t'].date()}")
    print(f"Operaciones ........ {n}  ({n / meses:.1f} al mes)")
    print(f"Neto USD ........... {sum(usd):.2f}")
    print(f"Profit factor ...... {p:.2f}")
    print(f"Acierto ............ {100.0 * sum(1 for x in usd if x > 0) / n:.1f} %")
    print(f"R medio ............ {m:.3f}  (desv. {sd:.3f}, t = {t:.2f})")
    print(f"IC 95 % R medio .... [{lo:.3f}, {hi:.3f}]  (bootstrap {BOOT}, semilla {SEED})")
    print(f"DD máx. balance .... {dd:.2f} %")
    print(f"Racha de pérdidas .. {racha_perdidas(usd)}")
    print(f"Años positivos ..... {anios_pos} de {len(anios)}")

    tabla("Por año", anios)
    for campo, titulo in (("ventana", "Por ventana"), ("dir", "Por dirección"), ("salida", "Por tipo de salida")):
        g = defaultdict(list)
        for r in filas:
            g[r.get(campo, "") or "?"].append(r)
        tabla(titulo, g)

    if not crit:
        return
    print(f"\n=== Veredicto del protocolo: fase {a.fase} ===")
    checks = [(f"n >= {crit['n_min']}", n >= crit["n_min"], f"{n}"),
              (f"PF >= {crit['pf_min']:.2f}", p >= crit["pf_min"], f"{p:.2f}"),
              ("R medio > 0", m > 0, f"{m:.3f}")]
    if crit["t_min"] is not None:
        checks.append((f"t >= {crit['t_min']:.1f}", t >= crit["t_min"], f"{t:.2f}"))
    if crit["ic_pos"]:
        checks.append(("IC 95 % del R medio > 0", lo > 0, f"[{lo:.3f}, {hi:.3f}]"))
    if crit["anios_pos_min"] is not None:
        checks.append((f"años positivos >= {crit['anios_pos_min']}", anios_pos >= crit["anios_pos_min"],
                       f"{anios_pos} de {len(anios)}"))
    checks.append((f"DD máx. <= {crit['dd_max']:.0f} %", dd <= crit["dd_max"], f"{dd:.2f} %"))
    for nombre, ok, val in checks:
        print(f"  [{'OK' if ok else 'NO'}] {nombre:<28} {val}")
    todo = all(ok for _, ok, _ in checks)
    if a.fase == "diseno":
        print("RESULTADO:", "PASA -> lanzar la validación 2025-2026 UNA sola vez, sin cambiar nada."
              if todo else "NO PASA -> la hipótesis se descarta. No ajustar parámetros para rescatarla.")
    else:
        print("RESULTADO:", "PASA -> se puede proponer una demo." if todo
              else "NO PASA -> no hay ventaja demostrada fuera de muestra. No va a demo.")


if __name__ == "__main__":
    main()
