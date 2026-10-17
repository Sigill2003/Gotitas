"""Generador de dataset simulado - Proyecto Gotitas.

Uso:
    python generar_dataset.py --giro restaurante --dias 30
    python generar_dataset.py --giro todos --dias 365

Salida (carpeta datos/):
    horario_<giro>.csv  -> consumo por hora + etiqueta de anomalía (verdad para medir recall)
    lecturas_<giro>.csv -> lecturas de apertura y cierre (lo que captura el encargado)

Los parámetros son SUPUESTOS ajustables: se calibran con las entrevistas de campo.
"""
import argparse
import os

import numpy as np
import pandas as pd

# apertura/cierre en horas; descanso: días sin operar (0=lunes ... 6=domingo)
# l_dia: litros promedio por día abierto; picos: franjas de mayor uso
PERFILES = {
    "restaurante": dict(apertura=8, cierre=20, descanso=[], l_dia=3000, picos=[(13, 15), (19, 20)]),
    "estetica": dict(apertura=10, cierre=19, descanso=[6], l_dia=700, picos=[(11, 13), (16, 18)]),
    "abarrotes": dict(apertura=7, cierre=21, descanso=[], l_dia=250, picos=[(8, 9)]),
    "lavanderia": dict(apertura=8, cierre=20, descanso=[], l_dia=4500, picos=[(9, 12), (16, 18)]),
    "oficina": dict(apertura=9, cierre=18, descanso=[5, 6], l_dia=450, picos=[(9, 10), (14, 15)]),
}


def generar(giro, dias, semilla=42):
    rng = np.random.default_rng(semilla)
    p = PERFILES[giro]

    df = pd.DataFrame({"fecha_hora": pd.date_range("2026-01-01", periods=dias * 24, freq="h")})
    h = df.fecha_hora.dt.hour
    wd = df.fecha_hora.dt.weekday
    df["dia"] = df.fecha_hora.dt.date
    dia_idx = (df.fecha_hora - df.fecha_hora.iloc[0]).dt.days

    # --- Patrón base: consumo solo en horario, con picos ---
    abierto = (h >= p["apertura"]) & (h < p["cierre"]) & ~wd.isin(p["descanso"])
    peso = abierto.astype(float).to_numpy()
    for a, b in p["picos"]:
        peso = np.where(abierto & (h >= a) & (h < b), peso * 2.0, peso)
    suma_dia = pd.Series(peso).groupby(df["dia"]).transform("sum").replace(0, 1)
    litros = peso / suma_dia.to_numpy() * p["l_dia"]

    # --- Variabilidad: ruido + días atípicos (más/menos movimiento) ---
    litros = litros * rng.normal(1, 0.12, len(df)).clip(0.5)
    factor_dia = pd.Series(rng.normal(1, 0.10, dias).clip(0.6, 1.5))
    for d in rng.choice(dias, size=max(1, dias // 30), replace=False):
        factor_dia[d] = rng.choice([0.5, 1.6])  # festivo o evento
    litros = litros * dia_idx.map(factor_dia).to_numpy()

    df["litros"] = litros
    df["anomalia"] = ""

    # --- Anomalías etiquetadas ---
    # 1) Fuga continua de bajo caudal (38 L/h) durante 7 días
    ini = dias // 3
    m = (dia_idx >= ini) & (dia_idx < ini + 7)
    df.loc[m, "litros"] += 38
    df.loc[m, "anomalia"] = "fuga_continua"

    # 2) Fuga intermitente (válvula de inodoro): 25 L/h de 2 a 4 a. m. en noches al azar
    noches = rng.choice(dias, size=max(2, dias // 6), replace=False)
    m = dia_idx.isin(noches) & h.between(2, 4)
    df.loc[m, "litros"] += 25
    df.loc[m, "anomalia"] = "fuga_intermitente"

    # 3) Picos por mal uso: una hora con consumo x4 en días al azar
    for d in rng.choice(dias, size=max(1, dias // 15), replace=False):
        hora = int(rng.integers(p["apertura"], p["cierre"]))
        m = (dia_idx == d) & (h == hora)
        df.loc[m, "litros"] *= 4
        df.loc[m, "anomalia"] = "pico"

    df["litros"] = df["litros"].round(1)

    # --- Lecturas del medidor (m3 acumulados) en apertura y cierre ---
    df["m3_antes"] = 1250 + (df.litros.cumsum() - df.litros) / 1000
    dia_abierto = ~wd.isin(p["descanso"])
    lect = []
    for tipo, hora in (("apertura", p["apertura"]), ("cierre", p["cierre"])):
        t = df[(h == hora) & dia_abierto][["fecha_hora", "m3_antes"]].copy()
        t["tipo"] = tipo
        lect.append(t)
    lecturas = pd.concat(lect).sort_values("fecha_hora").reset_index(drop=True)
    lecturas = lecturas.rename(columns={"m3_antes": "lectura_m3"})
    lecturas["lectura_m3"] = lecturas["lectura_m3"].round(3)
    lecturas["anomalia"] = ""

    # 4) Lecturas erróneas: error de captura (un cero de más)
    for i in rng.choice(len(lecturas), size=max(1, dias // 20), replace=False):
        lecturas.loc[i, "lectura_m3"] = round(lecturas.loc[i, "lectura_m3"] * 10, 3)
        lecturas.loc[i, "anomalia"] = "lectura_erronea"

    df = df.drop(columns=["dia", "m3_antes"])
    for t in (df, lecturas):
        t.insert(0, "giro", giro)
    return df, lecturas


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--giro", default="restaurante", choices=list(PERFILES) + ["todos"])
    ap.add_argument("--dias", type=int, default=30)
    ap.add_argument("--salida", default="datos")
    a = ap.parse_args()

    os.makedirs(a.salida, exist_ok=True)
    giros = list(PERFILES) if a.giro == "todos" else [a.giro]
    for g in giros:
        horario, lecturas = generar(g, a.dias)
        horario.to_csv(f"{a.salida}/horario_{g}.csv", index=False)
        lecturas.to_csv(f"{a.salida}/lecturas_{g}.csv", index=False)
        total_m3 = horario.litros.sum() / 1000
        n_anom = (horario.anomalia != "").sum()
        print(f"{g}: {len(horario)} horas, {total_m3:.1f} m3 en {a.dias} días, {n_anom} horas con anomalía")