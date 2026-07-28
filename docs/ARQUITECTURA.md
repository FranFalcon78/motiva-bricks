# Arquitectura de Motiva Bricks

## Decisión principal

El juego se dibuja en un único `Node2D` en vez de crear un nodo por ladrillo. Esto reduce la carga de escenas y señales cuando un nivel contiene más de mil bloques. La colisión usa una cuadrícula: cada bola consulta únicamente las celdas cercanas, no todos los ladrillos.

## Módulos

- `scripts/main.gd`: ciclo de juego, física, dibujo, interfaz, power-ups y resultados.
- `scripts/level_factory.gd`: convierte una especificación JSON compacta en una cuadrícula reproducible.
- `scripts/level_repository.gd`: niveles locales, descarga remota y reserva local.
- `scripts/ad_service.gd`: frontera entre el juego y la futura integración publicitaria.
- `levels/`: cinco ejemplos y su índice.
- `config/game_config.json`: servidor, publicidad, versión y límites.

## Exportación

No hay código dependiente de Linux dentro del juego. Los lanzadores `.sh` solo facilitan la prueba en el PC. La escena, la física, los controles táctiles, los niveles y la lógica de anuncios se mantienen iguales al exportar a Android.

## Publicidad

`AdService` funciona en modo `mock`. En una fase posterior se sustituirá su implementación por un complemento Android de Google Mobile Ads/UMP sin introducir llamadas publicitarias dentro de la física ni de la interfaz principal.
