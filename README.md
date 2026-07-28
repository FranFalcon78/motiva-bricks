# Motiva Bricks 0.1.0

Primera base jugable de **Motiva Bricks**, creada como proyecto original para **Godot 4.7.1 Standard + GDScript**. Está pensada para probarse en Linux Mint y conservar una ruta limpia hacia Android (APK/AAB), sin reescribir el motor del juego.

## Jugar en Linux Mint

1. Extrae la carpeta completa.
2. Haz doble clic en `MotivaBricks-Launcher` o ejecuta `./JUGAR_MOTIVA_BRICKS.sh`.
3. En el primer inicio, si Godot 4.7.1 no está instalado, el lanzador descarga la distribución oficial de Linux (aprox. 76 MB) y la guarda en `runtime/`.
4. Los siguientes inicios reutilizan ese motor y pueden funcionar sin descargarlo de nuevo.

Alternativa inmediata: `./PROBAR_VERSION_WEB.sh` abre una versión de compatibilidad en el navegador. Esa vista permite probar la jugabilidad, pero el proyecto principal y la futura exportación Android son los de Godot.

Para abrir el editor y modificar el juego: `./ABRIR_PROYECTO_EN_GODOT.sh`.

## Controles

- Ratón o pantalla táctil: mover el carro.
- `A/D` o flechas: mover el carro.
- `Espacio` o toque: lanzar las bolas.
- `P` o `Esc`: pausa.
- En el menú, teclas `1` a `5`: abrir un escenario.

## Incluido en esta versión

- Cinco escenarios JSON de muestra, de **945 a 1.208 bloques**.
- Rebote dinámico según la zona del carro donde golpea la bola.
- Hasta 30 bolas simultáneas.
- Moneda `×3`: multiplica las bolas.
- Moneda `W`: amplía temporalmente el carro.
- Moneda `S`: cierra temporalmente el foso.
- Vidas, puntuación, récord local, partículas y sonidos originales generados para el proyecto.
- Banner e intersticial **simulados**, sin conectar todavía identificadores publicitarios reales.
- Carga de niveles remotos con reserva automática de los cinco niveles locales.
- Generador reproducible de miles de escenarios basado en patrones y semillas.
- Presets para Linux, APK de depuración y AAB de Google Play.

## Niveles remotos

La dirección está en `config/game_config.json`:

```json
"remote_enabled": false,
"remote_level_index_url": "https://motiva.studio/motiva-bricks/levels/index.json"
```

Cuando el índice y los archivos estén publicados, cambia `remote_enabled` a `true`. Si el servidor no responde, el juego mantiene los escenarios locales.

## Generar escenarios

```bash
python3 tools/generate_levels.py --count 1000 --out generated-levels-1000
```

El generador no guarda miles de coordenadas. Cada nivel contiene una semilla, un patrón y parámetros compactos. Una función aleatoria determinista propia reproduce exactamente el mismo escenario en Godot, en la vista web y en las herramientas de validación.

## Validación y exportación

```bash
./VALIDAR_PROYECTO.sh
./EXPORTAR_LINUX.sh
./EXPORTAR_ANDROID_DEBUG.sh
```

Las exportaciones requieren instalar en Godot las plantillas de exportación de la misma versión. Android necesita además Java y Android SDK. Consulta `docs/EXPORTACION_ANDROID.md`.

## Identidad y propiedad

El código, los niveles, los sonidos y los gráficos vectoriales de esta entrega son originales. Las capturas del juego de referencia solo se han usado para comprender el género y algunas mecánicas; no se incluyen su marca, código, niveles ni recursos gráficos.
