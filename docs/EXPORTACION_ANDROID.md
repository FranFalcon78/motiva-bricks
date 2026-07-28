# Exportación Android

La base está configurada con el paquete `studio.motiva.bricks`, orientación vertical, renderizador de compatibilidad, arquitectura ARM64 y acceso a Internet para descargar escenarios.

## Preparación en Linux Mint

1. Abre el proyecto con `ABRIR_PROYECTO_EN_GODOT.sh`.
2. En Godot, instala las plantillas de exportación de la misma versión del editor.
3. Instala Java y Android SDK, y configura sus rutas en los ajustes del editor.
4. Abre `Proyecto > Exportar`.
5. Usa `Android Debug` para APK de prueba.
6. Usa `Android Play Store` para AAB firmado cuando se cree el almacén de claves definitivo.

También se puede intentar el APK por terminal:

```bash
./EXPORTAR_ANDROID_DEBUG.sh
```

## Publicidad

Esta entrega solo muestra espacios simulados. Antes de publicar se añadirá:

- Google Mobile Ads con identificadores de prueba durante el desarrollo.
- Banner anclado fuera del área de juego.
- Intersticial después de cada partida.
- UMP para consentimiento en el Espacio Económico Europeo.
- Configuración separada para identificadores de prueba y producción.

La integración se hará detrás de `AdService` para no modificar el motor de juego.
