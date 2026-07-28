#!/usr/bin/env python3
"""Genera colecciones reproducibles de escenarios compactos basados en semillas."""
from __future__ import annotations

import argparse
import json
import random
from pathlib import Path

PATTERNS = ["neon-gates", "concentric", "guardian", "circuit-maze", "reactor", "wave-tunnel"]
PALETTES = [
    ["#ff4f87", "#ff8a2b", "#ffe75b", "#28dfff"],
    ["#28dfff", "#20e6c7", "#9cef39", "#ffe75b"],
    ["#a855f7", "#ff4f87", "#ff9d32", "#fff28a"],
]


def make_level(number: int, base_seed: int) -> dict:
    rng = random.Random(base_seed + number * 104729)
    difficulty = min(1.0, number / 500.0)
    pattern = PATTERNS[(number - 1) % len(PATTERNS)]
    return {
        "id": f"generated-{number:05d}",
        "order": number,
        "name": f"Escenario {number:05d}",
        "subtitle": f"Patrón {pattern} · semilla reproducible",
        "difficulty": f"Serie {1 + (number - 1) // 100}",
        "seed": rng.randrange(1, 2_000_000_000),
        "theme": {
            "backgroundTop": "#23004b",
            "backgroundBottom": "#060012",
            "accent": PALETTES[number % len(PALETTES)][0],
            "palette": PALETTES[number % len(PALETTES)],
            "indestructible": "#808797",
            "ball": "#ffffff",
            "ballGlow": "#ffe9ff",
            "paddleStart": "#ff4f87",
            "paddleMiddle": "#ffe75b",
            "paddleEnd": "#28dfff",
        },
        "generator": {
            "pattern": pattern,
            "cols": 52 + number % 9,
            "rows": 39 + number % 7,
            "gap": 2,
            "height": 625,
            "hardRate": round(0.14 + difficulty * 0.15, 4),
            "veryHardRate": round(0.025 + difficulty * 0.07, 4),
            "indestructibleRate": round(0.014 + difficulty * 0.025, 4),
            "structuralEvery": 131 + (number * 17) % 73,
        },
        "physics": {
            "ballSpeed": round(8.2 + difficulty * 1.35, 3),
            "ballRadius": 8 if number % 4 else 7.5,
            "paddleWidth": round(158 - difficulty * 18, 2),
            "maxBounceAngleDeg": round(67 + difficulty * 6, 2),
        },
        "rules": {"lives": 3},
        "powerups": {
            "dropRate": 0.12,
            "wideSeconds": 15,
            "shieldSeconds": 12,
            "wideMultiplier": 1.66,
            "weights": {"triple": 0.37, "wide": 0.32, "shield": 0.31},
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=20260728)
    parser.add_argument("--out", type=Path, default=Path("generated-levels"))
    args = parser.parse_args()
    if not 1 <= args.count <= 100_000:
        raise SystemExit("--count debe estar entre 1 y 100000")
    args.out.mkdir(parents=True, exist_ok=True)
    paths = []
    for number in range(1, args.count + 1):
        filename = f"level-{number:05d}.json"
        (args.out / filename).write_text(json.dumps(make_level(number, args.seed), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        paths.append(f"./{filename}")
    index = {"schemaVersion": 1, "collection": f"Motiva Bricks - {args.count} escenarios", "levels": paths}
    (args.out / "index.json").write_text(json.dumps(index, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Generados {args.count} escenarios en {args.out.resolve()}")


if __name__ == "__main__":
    main()
