# Verificación y evidencias · 0.1

Fecha local: 18 de septiembre de 2026. macOS 26.5.2 (25F84), Apple Silicon; Swift 6.2.1 y SDK macOS 26.1. No se verificó compatibilidad en otros sistemas ni arquitecturas.

## Resultados reales

- `swift test --disable-sandbox --scratch-path "$TMPDIR/gestor-espacio-build"`: **9 pruebas XCTest, 0 fallos**. Se usó `CLANG_MODULE_CACHE_PATH` en temporal y `--package-path` desde la raíz del repositorio. La línea adicional de Swift Testing «0 tests» corresponde al runner vacío de esa biblioteca; las 9 pruebas son XCTest.
- `bash scripts/build-app.sh`: compilación release de app y CLI exitosa. Generados `dist/GestorEspacio.zip` y `dist/espacio`; la app se firma en una carpeta temporal local para que la sincronización no añada metadatos al bundle.
- `codesign --verify --deep --strict` sobre la app temporal: éxito. `plutil -lint` del `Info.plist`: éxito. `unzip -t dist/GestorEspacio.zip`: sin errores.
- CLI release `scan` sobre fixture local sintético: 4 entradas, orden/tamaños correctos, interior de Library omitido, `canDelete` falso en todas. JSON interpretado y comprobado mediante Python. Comando inválido devuelve código 1.
- CLI release `status`: muestra RAM física, cableada, compresor y capacidad del volumen. El entorno restringe `sysctl vm.swapusage`: tanto la CLI como `/usr/sbin/sysctl vm.swapusage` reportaron indisponibilidad. Se devuelve error explícito y se omite el valor numérico.
- Contraste de magnitud con `/usr/bin/vm_stat`: tamaño de página 16.384 bytes; memoria cableada y compresor en el mismo orden de magnitud. Muestras sucesivas, no simultáneas: no se afirma igualdad exacta ni equivalencia con la memoria usada de Monitor de Actividad.
- UI: apertura real de la app observada mediante accesibilidad. Se comprobó ventana principal, navegación, métricas de disco, estado inicial, búsqueda, filtro y apertura del selector nativo. La automatización del selector produjo acciones inconsistentes; **no se completó el análisis desde UI ni la inspección visual de resultados, filtros o panel de RAM**. Captura no utilizable; no se declara revisión visual completa.

## Trazabilidad

| Requisito → historia | Código | Evidencia / estado |
|---|---|---|
| RF-001–004 → HU-001 | Scanner.swift, App.swift | Núcleo probado: carpeta vacía/inválida, tamaños, orden, cancelación previa y durante análisis, límite, análisis nuevo y permisos denegados. Selector abre; recorrido UI completo pendiente |
| RF-008–009 → HU-004 | Classification.swift | Credenciales protegidas, nube protegida, nombre engañoso de caché desconocido, instalador revisable; razones y consecuencias no vacías; prueba de JSON |
| RNF-001–002 | Scanner.swift, Classification.swift | Enlace externo sin recorrido; Library, .ssh y paquete sin inspeccionar; contenido y fecha de fixture conservados; sin código de red |
| RF-007 → HU-003 | Diagnostics.swift | Lectura real de métricas y fallo explícito de swap; comprobación contextual con vm_stat; panel visual pendiente |
| RF-005–006, RF-010 → HU-002 | Sin implementar | No hay traslado ni eliminación; revalidación y recuperación pendientes |
| RNF-003 | App.swift | Compila y abre; búsqueda, filtros, teclado, detalle y comportamiento con análisis simultáneos aún requieren validación UI |

## Incidencias resueltas

1. Colisión del nombre `Category` con Objective-C: referencia calificada `SpaceCore.Category`.
2. Error de base de datos de SwiftPM en la ruta con espacios: compilación en carpeta temporal sin espacios.
3. Fixtures en Documentos reconocidos como iCloud y correctamente bloqueados: pruebas trasladadas a `/private/tmp`, con limpieza de sus propios archivos al terminar.
4. Metadatos Finder añadidos al bundle en carpeta sincronizada: retiro solo en artefacto generado antes de firmar. La app abrió posteriormente mediante el controlador de UI.

SwiftPM emitió advertencias por cachés globales no escribibles en el entorno restringido; compilación y pruebas finalizaron correctamente usando el directorio temporal. No se cambiaron permisos globales.

## Pendientes materiales

- Validación manual del recorrido UI, accesibilidad visual y cancelación/reinicio desde la ventana.
- App Sandbox, identidad de archivos, carreras durante enumeración, detección de otros proveedores de sincronización y permisos reales para operaciones de escritura.
- Presupuesto de rendimiento y pruebas de volumen. La implementación limita visitas a 20.000 elementos y mensajes de error a 100.
- No hay reglas de bajo riesgo habilitadas, limpieza, firma Developer ID, notarización ni MCP.
- La UI/CLI no son una frontera de aislamiento: ejecutan con permisos del usuario. Este prototipo es local y de solo lectura.

# Verificación · 0.2

Fecha local: 17 de noviembre de 2026. Mismo Mac (Apple Silicon), compilación release.

## Resultados reales

- `swift test`: **15 pruebas XCTest, 0 fallos**. Las 9 de la 0.1 más 6 nuevas: totales por carpeta, enlaces duros contados una vez, carpetas protegidas medidas pero no listadas, espejo de Google Drive protegido (también analizando una subcarpeta), rutas de `CloudStorage`/iCloud, y filtros de profundidad y tamaño mínimo.
- `bash scripts/install.sh`: app instalada en `~/Applications/Gestor Espacio.app` (firma verificada con `codesign --verify --deep --strict`) y CLI en `~/.local/bin/espacio`.
- **Comparación con `du` en `~/Developer`**: `espacio` 7,01 GB frente a `du -sh` 6,5 GiB (= 6,98 GB). Diferencia menor del 0,5 %.
- **Análisis de la carpeta personal** (`espacio scan ~ --depth 3 --min-mb 500`): 1.627.259 elementos en 3 min 15 s (limitado por E/S, 17 % de CPU); total 77,33 GiB; 100 incidencias guardadas, en su mayoría `Operation not permitted` en datos protegidos por la privacidad de macOS (Fotos, navegadores, `FileProvider`…).
  - `du -sk ~` dio 100,8 GiB porque **cruza el montaje `devicefs` de `~/Library/Developer/CoreDevice/DeviceFS`**, que vuelve a apuntar a datos dentro de `~/Library` y los cuenta dos veces. Con `du -skx ~/Library` (sin cruzar montajes): 46,73 GiB, idéntico al total de `~/Library` que da `espacio`. El criterio correcto de comparación es `du -x`.
  - `~/Documents` se detectó como espejo de Google Drive (1,3 GiB, `protection: sync`) y ninguno de sus archivos aparece como revisable.
  - Carpetas protegidas que antes eran invisibles y ahora se miden: `~/Library/Application Support/Claude` 13,4 GiB, `~/Library/Android/sdk` 11,6 GiB, `~/Library/Developer/CoreSimulator` 3,5 GiB, `~/Library/pnpm` 3,0 GiB, `~/Library/Containers/com.docker.docker` 1,95 GiB.

## Pendientes materiales

- La interfaz (pestaña Carpetas con árbol) compila y se instala, pero no se recorrió visualmente de punta a punta.
- Al analizar `~` desde la app, macOS puede pedir acceso a datos de otras apps; no se probó qué diálogos aparecen ni el resultado si se deniegan.
- La detección de Google Drive se basa en los marcadores del modo espejo; el modo streaming vive en `~/Library/CloudStorage` y se reconoce por ruta. No se comprobó Dropbox real.
- Sin perfiles de desarrollo, sin acciones y sin MCP (0.3–0.5).

# Verificación · 0.3

Fecha local: 17 de noviembre de 2026. Mismo Mac.

## Resultados reales

- `swift test`: **23 pruebas, 0 fallos** (15 anteriores + 8 de perfiles). Las de perfiles usan una carpeta personal sintética y un ejecutor falso de comandos: imágenes de Android usadas frente a no usadas, NDK referenciado frente a no referenciado (este último queda en «revisar», no en bajo riesgo), artefactos de proyectos activos frente a inactivos, enlaces duros de pnpm que reducen lo recuperable, versiones de Gradle pedidas por un wrapper, simuladores no disponibles y runtimes antiguos, salida de `docker system df`, deduplicación de `~/projects`/`~/Projects`, y una prueba de seguridad: el análisis no modifica ningún archivo, solo hace consultas de una lista permitida y ningún elemento tiene `canDelete`.
- `espacio dev --text` en este Mac (unos 37 s): **5,59 GB de bajo riesgo** y **23,25 GB para revisar**. Lo principal:
  - Bajo riesgo: store de pnpm 2,39 GB recuperables (de 2,95 GB), repositorio de Maven 788 MB, Gradle 8.14.1 (all + bin) y 9.2.0 sin ningún wrapper que las pida (unos 815 MB), cachés de Claude Desktop 1,19 GB y descargas de Homebrew.
  - Para revisar: máquina virtual de Claude Desktop 11,6 GB, emulador Logday_Pixel 3,9 GB (en uso hoy), simulador «BabyHome QA iPhone 17» 3,75 GB, NDK 25.1 2,25 GB (ningún proyecto revisado lo pide), Node v20.11.0 843 MB (tiene pnpm, expo y eas globales).
  - Se conservan: imagen android-36 (la usa Logday_Pixel), NDK 27.1 (lo pide React Native), runtime iOS 26.1 (usado hace 2 días) y los `node_modules` de los proyectos activos (task-manager, baby-home, logday-*).
- Docker no estaba en ejecución: el perfil solo midió su disco virtual (1,92 GB) y pidió abrir Docker Desktop.

## Pendientes materiales

- La pestaña Desarrollo compila y se instala, pero no se recorrió visualmente.
- Los comandos propuestos no se han ejecutado: su efecto real (y el espacio que liberan) se medirá en la 0.4.
- La actividad de proyectos se basa en el último commit y en la fecha de los archivos de primer nivel; un proyecto con trabajo reciente solo en subcarpetas profundas podría verse inactivo.

# Verificación · 0.4

Fecha local: 17 de noviembre de 2026. Mismo Mac.

## Resultados reales

- `swift test`: **36 pruebas, 0 fallos**. Las 13 nuevas de acciones usan una carpeta personal sintética y una Papelera falsa (nunca la real):
  - mover un artefacto inactivo, con registro y sin poder repetir el plan;
  - lo protegido o activo no se puede planificar;
  - carpeta reemplazada entre el plan y la ejecución (otro inodo): bloqueada;
  - proyecto que volvió a estar activo: bloqueado por cambio de categoría;
  - archivo personal modificado: bloqueado; sin cambios: va a la Papelera;
  - ruta `/tmp` frente a `/private/tmp`: se normaliza a la ruta real;
  - archivo dentro de un espejo de Google Drive: bloqueado;
  - fallo parcial de la Papelera: el archivo que falla se queda en su sitio y no se borra de forma permanente;
  - Xcode abierto: bloqueado;
  - el comando de pnpm se lanza con argumentos fijos y su código de salida decide el estado;
  - un plan de más de 24 h se rechaza;
  - reglas de ruta: la carpeta personal, carpetas de primer nivel, rutas ajenas y rutas con enlaces simbólicos se rechazan.
- **Prueba de punta a punta de la CLI** sobre una carpeta personal sintética (`ESPACIO_HOME`) con la Papelera real del sistema: `dev` mostró el id, `plan` creó el plan, `apply` con un código incorrecto canceló sin tocar nada, con el código correcto movió `node_modules` a la Papelera, el segundo `apply` se rechazó y el registro JSONL quedó escrito.
  - La prueba **detectó un fallo real**: la CLI escribía `/tmp/…` y la regla de seguridad bloqueó el archivo por estar «fuera de la carpeta personal» (`/private/tmp/…`). Se corrigió normalizando con `realpath` en el plan; hay una prueba de regresión.
  - Efecto secundario: quedó en la Papelera real del usuario una carpeta `node_modules` de 1,2 MB con datos aleatorios de la prueba. No se pudo retirar porque `~/.Trash` no es legible desde la terminal de Claude Code.
- App 0.4 instalada (firma verificada); abre y cierra sin errores.

## Pendientes materiales

- No se ha aplicado ningún plan sobre datos reales del usuario: lo decide él.
- Las hojas de confirmación y de resultados de la app compilan, pero no se recorrieron visualmente.
- No se probaron con las herramientas reales los comandos `sdkmanager`, `avdmanager`, `simctl`, `docker` ni `brew` (se usó un ejecutor falso). Si uno falla, el paso queda como «falló», con la salida del comando.

## Primera aplicación real (plan d2d493f0, 17-11-2026)

Jorge aplicó desde su terminal un plan de 8 pasos de bajo riesgo:

- **7 hechos**: `~/.m2/repository`, Gradle 8.14.1 (all y bin) y 9.2.0 (bin), `log-processor/node_modules` y `citas-api/target` movidos a la Papelera; `brew cleanup --prune=all` terminado.
- **1 falló**: `pnpm store prune` terminó con código 1 sin mensaje. Causa: se eligió el `pnpm` de `~/.nvm/versions/node/v24.11.1` (el más nuevo), pero se ejecutó con el `node` del PATH de la terminal (v20.11.0), con el que esa versión de pnpm no arranca. Además, el ejecutor descartaba la salida de error.
  - Corregido: el ejecutor pone primero en el PATH la carpeta del propio ejecutable (pnpm de nvm usa su propio `node`) y guarda la salida de error. Dos pruebas de regresión; 38 pruebas en total.
- Espacio disponible: 17,22 GB → 17,68 GB (+452 MB, sobre todo de Homebrew). Unos 1,6 GB más se liberarán al vaciar la Papelera.
- Observación: hay dos stores de pnpm (`v10`, 643 MB, y `v11`, 1,6 GB) de versiones distintas de pnpm; cada `pnpm store prune` solo limpia el suyo.

## Recorrido visual de la app (17-11-2026)

Con control de la app en segundo plano, sobre una carpeta personal sintética (`ESPACIO_HOME`, con un `pnpm` falso que no hace nada y `ESPACIO_SCAN`, que analiza una carpeta al arrancar):

- **Desarrollo**: el análisis lista los perfiles; el elemento protegido («activo · node_modules») no se puede marcar; el botón cuenta los marcados; la hoja «Revisa el plan» muestra el recuperable, la acción (ruta o comando) y el coste de regenerar; «Cancelar» no toca nada y conserva las marcas; «Ejecutar» lanzó el `pnpm store prune` falso, la hoja de resultados mostró «Comando terminado» y el espacio antes/después, el registro JSONL quedó escrito y la lista se volvió a analizar.
- **Carpetas**: árbol con totales y barras; Library y su subcarpeta pnpm con candado; las cifras cuadran con el total.
- **Archivos**: tabla con clasificación; el panel «Por qué» muestra la causa, la consecuencia y la ruta; «Mover a la Papelera…» abre la confirmación, que exige marcar «Entiendo que hay elementos marcados Revisar…» antes de habilitar «Ejecutar». Se canceló sin mover nada.

Corregido durante el recorrido: «Ejecutar 1 pasos» → «Ejecutar 1 paso»; la columna Archivo muestra la carpeta contenedora para distinguir elementos homónimos (había dos `node_modules` indistinguibles).

No verificado:
- **«Elegir carpeta…»**: el selector de macOS corre en otro proceso y no se pudo controlar, por eso se usó `ESPACIO_SCAN`. El selector sí se abre.
- **Selección múltiple en Archivos**: ⇧↓ enviado en segundo plano no amplió la selección. Puede ser una limitación de la automatización; falta comprobarlo a mano con ⌘/⇧ y clic.
- **Detalles menores**: la ruta raíz se muestra como `/tmp/…` cuando la carpeta está en `/private/tmp`, y el panel «Por qué» deja poca altura a la tabla.

# Verificación · 0.5

Fecha local: 17 de noviembre de 2026. Mismo Mac.

## Resultados reales

- `swift test`: **43 pruebas, 0 fallos**. Las 5 nuevas del servidor MCP comprueban:
  - el saludo inicial (versión del protocolo y capacidad de herramientas);
  - que las notificaciones no reciben respuesta;
  - la lista de herramientas, que no incluye ninguna que aplique, borre o mueva;
  - los errores de JSON-RPC (método desconocido y JSON inválido);
  - que `dev_report` seguido de `propose_cleanup` crea un plan sin tocar ningún archivo, y que `plan_result` lo da como pendiente;
  - que se rechazan archivos protegidos e id inexistentes;
  - el resumen compacto de `scan_folder`.
- `espacio apply` con la entrada por tubería (sin terminal interactiva) se niega a ejecutar: «necesita una terminal interactiva».
- `bash scripts/install-agentes.sh`: copió la skill a `~/.claude/skills/liberar-espacio` y registró el MCP `gestor-espacio` en el ámbito de usuario. `claude mcp list` → «✔ Connected».
- **Cliente real**: `claude -p` (Claude Code 2.1.314), con permiso solo para `dev_report` y `propose_cleanup`, creó el plan `59294cb7` (store de pnpm, unos 1,72 GB recuperables) y respondió que no se había ejecutado y que el usuario debe correr `espacio apply 59294cb7`. El plan quedó guardado y no se ejecutó.

## Pendientes materiales

- No se probó con Codex (el comando que hay que registrar es el mismo: `~/.local/bin/espacio mcp`).
- `scan_folder` sobre la carpeta personal tarda unos 3 minutos; un cliente MCP con un tiempo límite corto podría cortarlo.
