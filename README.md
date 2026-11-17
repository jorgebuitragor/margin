# Gestor de espacio para Mac

Estado: primera versión local compilada (0.1); núcleo y CLI verificados, recorrido visual completo pendiente. Uso personal; interfaz en español. Swift + SwiftUI, macOS 14 como mínimo declarado; validación local sobre macOS 26.5.2 / Apple Silicon. No validado en macOS 14 ni Intel.

## Qué incluye

- App nativa con selector de carpeta, análisis de metadatos en segundo plano, cancelación, búsqueda y filtros.
- Archivos ordenados por tamaño; clasificación y explicación: revisar, protegido o no determinado. No hay reglas de «bajo riesgo» validadas todavía.
- Exclusión de enlaces, paquetes, Library, sistema y ubicaciones sensibles reconocidas. Carpetas excluidas aparecen sin tamaño calculado; no se inspecciona su interior.
- Panel de RAM instalada, memoria cableada, ocupación del compresor e intercambio; capacidad disponible del volumen del usuario. Actualización manual y acceso al Monitor de Actividad para presión y consumo por proceso.
- CLI `espacio` con resultados JSON, utilizable por Codex o Claude Code mediante su terminal autorizada. No es todavía un servidor MCP.

Esta versión es de solo lectura: no mueve ni borra archivos. No lee contenidos para clasificarlos, no detecta duplicados y no descarga archivos de iCloud. La identificación de otros proveedores de sincronización no está implementada; por eso no se ofrece limpieza. Los tamaños lógicos y asignados no representan espacio recuperable y no se suman como tal.

## Compilar y abrir

Desde esta carpeta, con Xcode y Swift 6 instalados:

```sh
bash scripts/build-app.sh
open '/private/var/folders/_g/qhj85hv90cq6f9__qwbvz06h0000gn/T/gestor-espacio-local/Gestor Espacio.app'
```

El script crea una app firmada ad hoc en una carpeta temporal y el archivo portable `dist/GestorEspacio.zip`, además de `dist/espacio`. Extrae el ZIP en una ubicación local antes de abrirlo; una carpeta sincronizada puede añadir metadatos y romper la firma. No instala servicios, no requiere cuenta de pago y no publica nada. El prototipo local aún no tiene App Sandbox ni notarización; no confundir sus exclusiones internas con aislamiento del sistema operativo. Los permisos de privacidad de macOS siguen aplicando. No se solicita acceso total al disco.

La compilación usa una carpeta temporal sin espacios para evitar un fallo de la base de datos de SwiftPM observado en este entorno. `--disable-sandbox` afecta al proceso de construcción del paquete, no concede permisos de administrador.

## Consultar desde terminal o agentes

```sh
./dist/espacio status
./dist/espacio scan '/ruta/a/carpeta-elegida'
```

`status` muestra métricas y su fecha; `scan` devuelve entradas, causa, consecuencia, regla, tamaños opcionales, incidencias y banderas `cancelled`/`limited`. `canDelete` siempre es falso. Límite de 20.000 elementos visitados, 100 mensajes de error almacenados. Un informe con `limited` o incidencias no es un inventario completo. La CLI no persiste resultados; redirigirlos a un archivo es decisión del usuario.

Los resultados de `scan` incluyen rutas y nombres. Al consultarlos desde un asistente pueden formar parte de su conversación; comparte solo el alcance que necesites. La app y CLI no incluyen clientes de red ni un modelo.

## Pruebas

```sh
CLANG_MODULE_CACHE_PATH="$TMPDIR/gestor-espacio-clang-cache" swift test --disable-sandbox --scratch-path "$TMPDIR/gestor-espacio-build"
```

Fixtures sintéticos creados y retirados por las pruebas, sin limpieza sobre archivos personales. Consultar [evidencias](VERIFICACION.md) para resultados y límites comprobados.

## Artefactos y decisiones

- [Especificación y backlog](PROYECTO.md).
- [Clasificación explicada](CLASIFICACION.md).
- [Verificación](VERIFICACION.md).
- [Código de interfaz](Sources/SpaceApp/App.swift), [núcleo](Sources/SpaceCore), [CLI](Sources/SpaceCLI/main.swift).

Confirmados: disco y diagnóstico de RAM, uso personal, clasificación con causa. Primera implementación: análisis sin escritura; implementación técnica elegida para avanzar con el alcance autorizado. La integración MCP es propuesta futura, no capacidad actual.

## Siguiente incremento

Plan detallado 0.2 → 0.6 en [PLAN.md](PLAN.md). Resumen previo:

Validar la interfaz en uso real y preparar App Sandbox. Después, traslado selectivo a Papelera con revalidación de identidad/permisos, tratamiento de sincronización y pruebas de carreras y recuperación. El conector MCP reutilizará las reglas del núcleo; nunca recibirá autorización de borrado a partir de una clasificación del modelo.
