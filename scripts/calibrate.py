"""Simulador de calibración de progresión (espejo del motor Swift).

Uso: python scripts/calibrate.py

Replica las constantes de Sistema/Engine/Progression.swift y simula años de
entrenamiento (5 sesiones/semana de 60 min, RPE 7) con distintos niveles de
cumplimiento. Sirve para ajustar constantes rápido antes de correr
CalibrationTests en Xcode, que hace lo mismo con el motor real.
"""
import math

# --- Constantes (mantener sincronizadas con Progression.swift) ---
CURVE_BASE = 50.0
CURVE_COEF = 7.3  # ajustado desde 7.0: con el bonus de madrugada SS caía en 9.8 años
CURVE_EXP = 1.5
MAX_LEVEL = 100
BASE_XP = 100.0          # sesión completa de 60 min, RPE 7
DAILY_CAP = 200
WEEKLY_CAP = 700
EARLY_BONUS = 0.10       # antes de las 6 a. m.

# rango: (nivel mínimo, nivel máximo, meses mínimos en el rango anterior)
RANKS = [
    ("E", 1, 9, 0),
    ("D", 10, 24, 1),
    ("C", 25, 44, 3),
    ("B", 45, 64, 6),
    ("A", 65, 84, 12),
    ("S", 85, 99, 24),
    ("SS", 100, 100, 36),
]
DAYS_PER_MONTH = 30.4375


def xp_to_next(level):
    return round(CURVE_BASE + CURVE_COEF * level ** CURVE_EXP)


CUM = [0, 0]
for lv in range(1, MAX_LEVEL):
    CUM.append(CUM[-1] + xp_to_next(lv))


def level_for(xp):
    lv = 1
    while lv < MAX_LEVEL and xp >= CUM[lv + 1]:
        lv += 1
    return lv


def rank_index(level):
    for i, (_, lo, hi, _) in enumerate(RANKS):
        if lo <= level <= hi:
            return i
    return len(RANKS) - 1


def simulate(compliance, years=20, early=False):
    total, overflow = 0, 0
    unlocked = 0
    entered_day = 0
    arrivals = {"E": 0}
    week_xp = 0
    for day in range(int(years * 365.25)):
        weekday = day % 7  # 0 = lunes
        if weekday == 0:
            week_xp = 0
        if weekday < 5:
            raw = BASE_XP * compliance * (1 + EARLY_BONUS if early else 1)
            gain = int(round(min(raw, DAILY_CAP, WEEKLY_CAP - week_xp)))
            week_xp += gain
            cap = RANKS[unlocked][2]
            ceiling = CUM[cap + 1] - 1 if cap < MAX_LEVEL else CUM[MAX_LEVEL]
            room = max(0, ceiling - total)
            total += min(gain, room)
            extra = gain - min(gain, room)
            if cap < MAX_LEVEL:
                overflow = min(xp_to_next(cap), overflow + extra)
        # rango visible
        r = rank_index(level_for(total))
        if RANKS[r][0] not in arrivals:
            arrivals[RANKS[r][0]] = day
            entered_day = day
        # prueba de ascenso: disponible al tope y con tiempo mínimo cumplido
        if unlocked < len(RANKS) - 1 and level_for(total) == RANKS[unlocked][2]:
            need = RANKS[unlocked + 1][3] * DAYS_PER_MONTH
            if day - entered_day >= need:
                unlocked += 1
                total += overflow
                overflow = 0
                r = rank_index(level_for(total))
                if RANKS[r][0] not in arrivals:
                    arrivals[RANKS[r][0]] = day
                    entered_day = day
    return arrivals


def fmt(days):
    if days is None:
        return "—"
    if days < 365:
        return f"{days / DAYS_PER_MONTH:.1f} meses"
    return f"{days / 365.25:.2f} años"


if __name__ == "__main__":
    print(f"XP total para nivel 100: {CUM[MAX_LEVEL]}")
    for lo in (10, 25, 45, 65, 85, 100):
        print(f"  XP acumulado para nivel {lo}: {CUM[lo]}")
    for label, c, early in [("100%", 1.0, False), ("100% madrugada", 1.0, True),
                            ("80%", 0.8, False), ("60%", 0.6, False)]:
        arr = simulate(c, early=early)
        print(label, " | ".join(f"{k}: {fmt(arr.get(k))}" for k, *_ in RANKS))
