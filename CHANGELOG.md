# Cambios

## 0.1.3 - 2026-07-28
- Selector de 10 niveles en una cuadrícula de dos columnas con vistas previas compactas.
- Carro reducido un 30 % y ladrillos reducidos un 25 %.
- Diámetro de todas las bolas ajustado automáticamente a la altura real de los ladrillos, también después de multiplicarlas.
- Frecuencia de aparición de power-ups reducida aproximadamente un 75 %.
- Sonido diferenciado al recoger cada tipo de power-up utilizando el banco de audio existente.
- Nuevo power-up permanente de disparo continuo.
- Cañones situados en los extremos exteriores del carro para cubrir los bordes del escenario.
- Los proyectiles destruyen ladrillos destructibles e ignoran los indestructibles, pasando visualmente por detrás.
- Multiplicación ×3 acumulativa hasta un máximo absoluto de 300 bolas.
- Control antiatasco con detección de poco desplazamiento y colisiones repetidas; prueba varias direcciones y posiciones libres para liberar cada bola.
- Estructura consolidada: `main.gd` conserva el motor común y `gameplay.gd` contiene el único controlador jugable actual; se elimina el archivo duplicado `main_v013.gd`.

## 0.1.2
- Corregida la resolución de `LevelFactory` en Godot 4.7.1 mediante precarga explícita del script.
- Añadido tipado explícito al resultado generado para evitar advertencias tratadas como errores.

## 0.1.0 - 2026-07-28

- Primera versión jugable de Godot.
- Cinco niveles JSON densos.
- Física de rebote dirigida por el punto de impacto.
- Power-ups ×3, carro ancho y cierre de foso.
- Niveles locales/remotos, récord, sonidos y anuncios simulados.
- Lanzadores para Linux Mint, presets Linux/Android y vista web de reserva.
