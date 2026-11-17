# Gestor de espacio para Mac

Estado: versión local 0.2 (2026-11-17). Núcleo, CLI e instalación verificados; recorrido visual completo pendiente. Uso personal; interfaz en español. Swift + SwiftUI, macOS 14 como mínimo declarado; validado en macOS 26 / Apple Silicon. No validado en macOS 14 ni Intel.

## Qué incluye

- **Totales por carpeta**, con la misma lógica que `du`: espacio asignado, enlaces duros contados una vez, sin seguir enlaces simbólicos ni cruzar a otros volúmenes. Los totales no tienen límite de elementos.
- **Carpetas protegidas medidas**: `Library`, paquetes, `node_modules`, `.build`, `.git`, configuración y credenciales muestran cuánto ocupan, pero sus archivos no se listan y nunca son accionables.
- **Detección de sincronización**: Google Drive en modo espejo (marcadores `.tmp.driveupload`/`.tmp.drivedownload`), Dropbox, `~/Library/CloudStorage` (Google Drive, OneDrive, Box…) e iCloud. Lo sincronizado se mide y queda protegido; si la carpeta analizada está dentro de una sincronizada, todo el informe es solo de medida.
- **Archivos más grandes** fuera de zonas protegidas, con clasificación y explicación: revisar, protegido o no determinado. No hay reglas de «bajo riesgo» todavía.
- App nativa con pestañas Carpetas (árbol con tamaños), Archivos y Memoria RAM; análisis en segundo plano con cancelación.
- CLI `espacio` con JSON para agentes y `--text` para la terminal. No es todavía un servidor MCP.

Esta versión es de solo lectura: no mueve ni borra archivos. No lee contenidos, no detecta duplicados y no descarga archivos de la nube. Los totales son espacio ocupado, no espacio recuperable.

Al analizar la carpeta personal, macOS puede pedir permiso para acceder a datos de otras apps (por ejemplo `~/Library/Containers`). Si se deniega, esa carpeta se cuenta como ilegible y el total se marca como mínimo.

## Instalar

Desde esta carpeta, con Xcode y Swift 6 instalados:

```sh
bash scripts/install.sh
```

Instala `~/Applications/Gestor Espacio.app` y `~/.local/bin/espacio`, sin permisos de administrador. Solo reemplaza una instalación anterior de esta misma app. `scripts/build-app.sh` compila sin instalar: deja la app firmada ad hoc en una carpeta temporal, `dist/GestorEspacio.zip` y `dist/espacio`. Sin App Sandbox ni notarización; los permisos de privacidad de macOS siguen aplicando.

La compilación usa una carpeta temporal sin espacios para evitar un fallo de la base de datos de SwiftPM. `--disable-sandbox` afecta al proceso de construcción del paquete, no concede permisos de administrador.

## Consultar desde terminal o agentes

```sh
espacio status
espacio scan ~ --depth 2 --min-mb 500 --text
espacio scan ~/Developer > informe.json
```

`scan` devuelve `totalAllocated`, `folders` (ruta, profundidad, tamaño, archivos, `protection`: `protected`/`sync`, `partial`), `entries` (archivos más grandes y carpetas protegidas con su total), `syncedBy`, incidencias y las banderas `cancelled`/`limited`. `limited` significa que se listan solo los archivos más grandes (`--max-files`, 20.000 por defecto); los totales siguen completos. Un total con `partial` o con incidencias es un mínimo. `canDelete` siempre es falso.

Los resultados incluyen rutas y nombres. Al consultarlos desde un asistente pasan a su conversación: comparte solo el alcance que necesites. La app y la CLI no incluyen clientes de red ni un modelo.

## Pruebas

```sh
CLANG_MODULE_CACHE_PATH="$TMPDIR/gestor-espacio-clang-cache" swift test --disable-sandbox --scratch-path "$TMPDIR/gestor-espacio-build"
```

Fixtures sintéticos creados y retirados por las pruebas, sin limpieza sobre archivos personales. Consultar [evidencias](VERIFICACION.md) para resultados y límites comprobados.

## Artefactos y decisiones

- [Plan 0.2 → 0.6](PLAN.md).
- [Especificación y backlog](PROYECTO.md).
- [Clasificación explicada](CLASIFICACION.md).
- [Verificación](VERIFICACION.md).
- [Código de interfaz](Sources/SpaceApp/App.swift), [núcleo](Sources/SpaceCore), [CLI](Sources/SpaceCLI/main.swift).

Confirmados: disco y diagnóstico de RAM, uso personal, clasificación con causa. Hasta la 0.2 todo es análisis sin escritura. La integración MCP es propuesta futura (0.5), no capacidad actual.

## Siguiente incremento

La 0.2 está hecha. Siguiente: 0.3, perfiles de cachés de desarrollo (Android SDK y emuladores, simuladores iOS, pnpm, Gradle, Docker, Homebrew, artefactos de proyectos inactivos). Plan completo en [PLAN.md](PLAN.md).
