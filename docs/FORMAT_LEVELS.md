# Formato de escenarios

Cada escenario es un JSON con estas secciones:

- `id`, `order`, `name`, `subtitle` y `seed`.
- `theme`: fondo, paleta, bola y carro.
- `generator`: patrón, columnas, filas, separación y proporciones de resistencia.
- `physics`: velocidad, radio de bola, anchura del carro y ángulo máximo.
- `rules`: vidas iniciales.
- `powerups`: frecuencia, duración y pesos de las monedas.

Patrones incluidos: `neon-gates`, `concentric`, `guardian`, `circuit-maze`, `reactor` y `wave-tunnel`.

El índice remoto esperado es equivalente a:

```json
{
  "schemaVersion": 1,
  "collection": "Motiva Bricks",
  "levels": [
    "./level-00001.json",
    "./level-00002.json"
  ]
}
```
