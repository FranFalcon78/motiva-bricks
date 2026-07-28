#!/usr/bin/env python3
"""Comprobaciones estáticas rápidas antes de abrir el proyecto en Godot."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REQUIRED = [
    "project.godot", "export_presets.cfg", "scenes/main.tscn",
    "scripts/main.gd", "scripts/level_factory.gd", "scripts/level_repository.gd",
    "config/game_config.json", "levels/index.json", "assets/icon.svg",
]


def check_balanced(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    stack: list[tuple[str, int]] = []
    pairs = {')': '(', ']': '[', '}': '{'}
    opening = set(pairs.values())
    quote = None
    escaped = False
    line = 1
    errors = []
    for char in text:
        if char == '\n': line += 1
        if quote:
            if escaped: escaped = False
            elif char == '\\': escaped = True
            elif char == quote: quote = None
            continue
        if char in {'"', "'"}: quote = char; continue
        if char in opening: stack.append((char, line))
        elif char in pairs:
            if not stack or stack[-1][0] != pairs[char]:
                errors.append(f"{path.name}:{line}: delimitador {char} sin pareja")
            else: stack.pop()
    for char, at in stack:
        errors.append(f"{path.name}:{at}: delimitador {char} sin cerrar")
    return errors


def main() -> int:
    errors = []
    for relative in REQUIRED:
        if not (ROOT / relative).exists(): errors.append(f"Falta {relative}")
    json.loads((ROOT / "config/game_config.json").read_text(encoding="utf-8"))
    json.loads((ROOT / "levels/index.json").read_text(encoding="utf-8"))
    for path in (ROOT / "scripts").glob("*.gd"):
        errors.extend(check_balanced(path))
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if line.startswith(" "):
                errors.append(f"{path.name}:{number}: se esperaba tabulación al inicio")
            if ": return " in line:
                errors.append(f"{path.name}:{number}: bloque GDScript en una línea")
    if errors:
        print("ERRORES ESTÁTICOS:")
        print("\n".join(f" - {item}" for item in errors))
        return 1
    print("OK: estructura, JSON y delimitadores comprobados.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
