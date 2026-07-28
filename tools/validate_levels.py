#!/usr/bin/env python3
"""Valida niveles y reproduce exactamente el generador determinista de Godot."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

REQUIRED = {"id", "order", "name", "seed", "theme", "generator", "physics", "rules", "powerups"}
PATTERNS = {"neon-gates", "concentric", "guardian", "circuit-maze", "reactor", "wave-tunnel"}
HASH_MODULUS = 2_147_483_647
HASH_MULTIPLIER = 48_271


def cell_random(seed: int, x: int, y: int, salt: int) -> float:
    value = abs(int(seed)) % HASH_MODULUS
    value = (
        value
        + (x + 1) * 73_856_093
        + (y + 1) * 19_349_663
        + (salt + 1) * 83_492_791
    ) % HASH_MODULUS
    value = (value * HASH_MULTIPLIER + 1) % HASH_MODULUS
    value = (value * HASH_MULTIPLIER + 1) % HASH_MODULUS
    return value / HASH_MODULUS


def matches(kind: str, x: int, y: int, cols: int, rows: int, random_value: float) -> bool:
    if kind == "neon-gates":
        top = y <= 4
        outer = (x <= 1 or x >= cols - 2) and y >= 8
        lower = y >= rows - 3
        column = y >= 9 and y <= rows - 7 and x % 7 < 3
        middle_y = math.floor(rows * 0.46)
        middle = middle_y <= y <= middle_y + 2 and 5 < x < cols - 6
        gap = (math.floor(x / 7) + math.floor(y / 8)) % 5 == 0 and random_value < 0.34
        return (top or outer or lower or column or middle) and not gap

    if kind == "concentric":
        distance = min(x, cols - 1 - x, y, rows - 1 - y)
        center_x = (cols - 1) * 0.5
        center_y = (rows - 1) * 0.5
        ring = distance % 5 <= 1
        cross = (abs(x - center_x) <= 1 or abs(y - center_y) <= 1) and distance > 5
        gate = (
            abs(x - center_x) <= 2 and y < rows * 0.19
        ) or (
            abs(y - center_y) <= 1 and x > cols * 0.78
        )
        texture = random_value < 0.045 and distance > 3
        return (ring or cross or texture) and not gate

    if kind == "guardian":
        nx = x / max(1, cols - 1)
        ny = y / max(1, rows - 1)
        symmetry_x = abs(nx - 0.5)
        helmet = ny < 0.17 and symmetry_x < 0.46
        side = 0.14 <= ny < 0.83 and 0.38 < symmetry_x < 0.47
        face = 0.17 < ny < 0.75 and 0.25 < symmetry_x < 0.34
        eye_left = 0.25 < nx < 0.42 and 0.27 < ny < 0.43
        eye_right = 0.58 < nx < 0.75 and 0.27 < ny < 0.43
        cut_left = 0.30 < nx < 0.38 and 0.31 < ny < 0.39
        cut_right = 0.62 < nx < 0.70 and 0.31 < ny < 0.39
        nose = symmetry_x < 0.08 and 0.42 < ny < 0.61
        mouth = 0.25 < nx < 0.75 and 0.56 < ny < 0.75
        mouth_cut = 0.34 < nx < 0.66 and 0.61 < ny < 0.68
        jaw = 0.72 < ny < 0.82 and symmetry_x < 0.34
        circuit = 0.18 < ny < 0.78 and (x + y * 2) % 11 == 0 and random_value > 0.25
        return (
            helmet or side or face or (eye_left and not cut_left)
            or (eye_right and not cut_right) or nose
            or (mouth and not mouth_cut) or jaw or circuit
        )

    if kind == "circuit-maze":
        border = x <= 1 or x >= cols - 2 or y <= 1 or y >= rows - 2
        vertical = x % 6 <= 1
        horizontal = y % 7 <= 1
        checker = (math.floor(x / 6) + math.floor(y / 7)) % 2 == 0
        track = (vertical and checker) or (horizontal and not checker)
        open_gate = (vertical or horizontal) and random_value < 0.12
        node = vertical and horizontal
        return border or node or (track and not open_gate)

    if kind == "reactor":
        center_x = (cols - 1) * 0.5
        center_y = (rows - 1) * 0.5
        dx = (x - center_x) / (cols * 0.5)
        dy = (y - center_y) / (rows * 0.5)
        radius = math.hypot(dx, dy)
        angle = math.atan2(dy, dx)
        ring = math.floor(radius * 28) % 4 <= 1 and 0.09 < radius < 0.96
        spoke = abs(math.sin(angle * 6)) < 0.16 and 0.17 < radius < 0.90
        core = radius < 0.18 and (x + y) % 2 == 0
        fracture = random_value < 0.035 and radius > 0.30
        return ring or spoke or core or fracture

    nx = x / max(1, cols - 1)
    wave_a = math.sin(nx * math.pi * 5.5) * 4 + rows * 0.27
    wave_b = math.cos(nx * math.pi * 4.2) * 5 + rows * 0.54
    wave_c = math.sin(nx * math.pi * 7.3 + 1.2) * 3 + rows * 0.76
    thick_wave = abs(y - wave_a) <= 2 or abs(y - wave_b) <= 2 or abs(y - wave_c) <= 2
    vertical_sparks = x % 8 <= 1 and y > 4 and random_value > 0.58
    return y < 3 or x <= 1 or x >= cols - 2 or thick_wave or vertical_sparks


def count_bricks(level: dict[str, Any]) -> tuple[int, int]:
    generator = level["generator"]
    cols = max(18, min(72, round(float(generator.get("cols", 52)))))
    rows = max(14, min(56, round(float(generator.get("rows", 38)))))
    kind = str(generator.get("pattern", "neon-gates"))
    seed = int(level.get("seed", 1))
    indestructible_rate = max(0.0, min(0.25, float(generator.get("indestructibleRate", 0.025))))
    structural_every = max(0, round(float(generator.get("structuralEvery", 0))))
    total = 0
    destructible = 0
    for y in range(rows):
        for x in range(cols):
            if not matches(kind, x, y, cols, rows, cell_random(seed, x, y, 0)):
                continue
            total += 1
            structural = structural_every > 0 and (x + y * cols) % structural_every == 0
            if not structural and cell_random(seed, x, y, 1) >= indestructible_rate:
                destructible += 1
    return total, destructible


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", nargs="?", default=str(Path(__file__).resolve().parents[1] / "levels"))
    args = parser.parse_args()
    directory = Path(args.directory)
    index = json.loads((directory / "index.json").read_text(encoding="utf-8"))
    errors: list[str] = []
    seen_ids: set[str] = set()
    entries = index.get("levels", [])

    print("Motiva Bricks - validaci\u00f3n determinista de escenarios")
    print("-" * 74)
    for relative in entries:
        path = directory / str(relative).removeprefix("./")
        try:
            level = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{path.name}: JSON inv\u00e1lido: {exc}")
            continue

        missing = REQUIRED - level.keys()
        if missing:
            errors.append(f"{path.name}: faltan {sorted(missing)}")
        level_id = str(level.get("id", ""))
        if not level_id:
            errors.append(f"{path.name}: id vac\u00edo")
        elif level_id in seen_ids:
            errors.append(f"{path.name}: id duplicado: {level_id}")
        seen_ids.add(level_id)

        pattern = level.get("generator", {}).get("pattern")
        if pattern not in PATTERNS:
            errors.append(f"{path.name}: patr\u00f3n no soportado: {pattern}")

        total, destructible = count_bricks(level)
        if total < 700:
            errors.append(f"{path.name}: densidad insuficiente ({total} bloques)")
        if destructible <= 0:
            errors.append(f"{path.name}: no tiene bloques destruibles")

        print(
            f"{level.get('order', '?'):>2}. {level.get('name', path.stem):<27} "
            f"{total:>4} bloques | {destructible:>4} destruibles"
        )

    print("-" * 74)
    if errors:
        print("ERRORES:")
        for error in errors:
            print(" -", error)
        return 1
    print(f"OK: {len(entries)} escenarios v\u00e1lidos y reproducibles.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
