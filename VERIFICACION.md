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

## Segunda aplicación real (plan 59294cb7, creado por Claude Code vía MCP)

- `pnpm store prune` (pnpm 11 de Node 24, ya ejecutado con su propio `node`): hecho. Según pnpm, eliminó 82.091 archivos (1,46 GB) y 1.528 paquetes; el store `v11` pasó de 1,6 GB a 12 KB. El arreglo del ejecutor queda confirmado con datos reales.
- Espacio disponible: 19,68 GB → 20,72 GB (+1,05 GB observado; la diferencia con lo que informa pnpm se debe a la actividad del sistema y a APFS).
- Queda el store `v10` (643 MB), que pertenece a la otra versión de pnpm (12.4.2, en Node 20.11.0). El perfil lo mide junto al `v11` y solo propone un `prune`: mejora pendiente para la 0.6.
- Corregido el 17-11-2026: el perfil crea un elemento por store de pnpm. Pregunta a cada pnpm instalado (`pnpm store path`, de solo lectura), propone `store prune` con el binario exacto que usa ese store y marca como «sin uso» el store que ninguna versión instalada declara (aquí `v10`: 673,8 MB recuperables, que van a la Papelera). Si no se puede consultar a ningún pnpm, el store huérfano queda «para revisar». 44 pruebas.

# Verificación · 0.6 (análisis inteligente y Vaciar Papelera)

Fecha local: 17 de noviembre de 2026. Mismo Mac.

- `swift test`: **52 pruebas, 0 fallos**. Las 8 nuevas cubren:
  - la clasificación de cachés: las de macOS y Homebrew se excluyen, las conocidas quedan en bajo riesgo con su app, las que tienen forma de identificador se comprueban por `lsappinfo` y las desconocidas quedan para revisar;
  - el bloqueo cuando la app está abierta, comprobado por su identificador;
  - los registros, y los instaladores antiguos de Descargas, que quedan para revisar (ni recientes ni fotos);
  - que una carpeta Descargas sincronizada se ignora;
  - que vaciar la Papelera lanza un único comando fijo a Finder y queda registrado;
  - que vaciar nunca forma parte de un plan ni del MCP;
  - que con una carpeta personal de prueba la Papelera real no se vacía;
  - que los perfiles se ejecutan en paralelo y conservan el orden.
- Análisis completo en este Mac: **unos 12 s** (antes, 37 s en secuencia). Nuevos elementos encontrados: caché de Chrome (400 MB), Firefox (387 MB) y Go (193 MB) como bajo riesgo; `dotslash` (542 MB, dueño desconocido) para revisar; registros (149 MB); 21 instaladores de más de 30 días en Descargas (16 MB). Las copias de iPhone y la Papelera no se pueden leer sin «Acceso total al disco»; la app lo indica.
- Recorrido visual sobre una carpeta de prueba:
  - **Inicio**: estado vacío, análisis, tarjetas con sumas por categoría, «Ver detalle».
  - **«Revisar y limpiar»**: el plan de bajo riesgo marcó «Caché de Firefox» como **no se ejecutará: cierra Firefox**, porque Firefox estaba abierto de verdad.
  - **«Vaciar Papelera…»**: el diálogo destructivo se abrió y se canceló.
- Corregido durante la prueba:
  - en modo de prueba, el diálogo mostraba la Papelera sintética pero Finder habría vaciado la real; ahora el vaciado se bloquea si la carpeta personal no es la real (con prueba de regresión);
  - plurales («1 elementos», «1 carpetas»).
- No probado: el vaciado real con Finder, que lo hará Jorge. La primera vez macOS pedirá permiso de Automatización para controlar Finder.
- En modo de prueba, los perfiles que consultan herramientas reales (por ejemplo `brew --cache`) siguen apuntando a datos reales. No hay que ejecutar planes en ese modo.

## 0.6 · mapa, memoria y selección (17-11-2026)

- `swift test`: **56 pruebas, 0 fallos**. Las 4 nuevas comprueban:
  - que el mapa reparte áreas proporcionales (error menor del 0,1 %), dentro de los límites y sin solapes, y que con valores iguales las piezas son cuadradas;
  - que cada nivel del mapa añade «Otros» para que las áreas sumen el total de la carpeta;
  - que el diagnóstico lee la presión de memoria y las apps ordenadas por consumo.
- **Lectura real en este Mac**: presión «Advertencia» (nivel 2) y 9 GB de intercambio. Apps que más memoria usan: Firefox 6,2 GB (20 procesos), ChatGPT 2,4 GB, Claude 1,7 GB, Google Chrome 1,1 GB. Hay 174 procesos del sistema que no se pueden inspeccionar sin privilegios; la app lo indica.
- El menú «Analizar» aparece en la barra de menús con las carpetas que existen.
- No verificado visualmente (pantalla bloqueada durante la prueba): el mapa, la nueva pestaña de memoria, las casillas de Archivos y los atajos de teclado. La app compila, se instala y arranca.
- **Revisión visual con la pantalla bloqueada** (solo capturas; los clics no son posibles): se añadieron `ESPACIO_TAB` y `ESPACIO_VIEW` para abrir la app en una pestaña o en el mapa.
  - **Mapa de Carpetas**: Library (158 MB, gris y con candado), Developer y Downloads proporcionales.
  - **Memoria RAM**: presión «Advertencia» en naranja, 11,9 GB de intercambio y la lista de 12 apps con barras y número de procesos.
  - **Archivos**: columna de casillas y carpeta contenedora.
  - Sin verificar: la interacción (entrar en el mapa, marcar casillas, atajos de teclado).
- **DotSlash**: la caché de 542 MB que antes era «de dueño desconocido» se reconoce como «Caché de DotSlash» (binarios descargados bajo demanda, por ejemplo por Codex). Pasa a bajo riesgo y exige Codex cerrado.
- **Codex**: `install-agentes.sh` registró el MCP (`codex mcp list` → `gestor-espacio … enabled`) y copió la skill a `~/.codex/skills`. No se pudo probar con el modelo: la cuenta de Codex devuelve `402 deactivated_workspace`.

## Pruebas de interacción de la 0.6 (18-11-2026, pantalla desbloqueada)

Hechas con clics reales sobre una carpeta personal sintética de 52 MB (`ESPACIO_HOME` + `ESPACIO_SCAN`), sin ejecutar ningún plan.

- **Mapa**: clic en Proyectos → app-web entra nivel a nivel y las áreas cuadran (23,5 MB = 16,5 + 7). «Subir» vuelve hasta la raíz y se desactiva allí. Las carpetas protegidas salen en gris con candado.
- **Archivos**: las casillas marcan solo «Revisar antes de borrar»; las protegidas y «No determinado» no se marcan. «Mover a la Papelera (2)…» abre el plan con las rutas, y «Ejecutar» sigue desactivado hasta marcar «Entiendo…». Se canceló. La búsqueda filtra.
- **Limpieza**: «Ver detalle» desde Inicio lleva a Limpieza. La casilla activa «Revisar plan (1)…» y el plan muestra el comando exacto (`brew cleanup --prune=all`). Se canceló.
- **Menú «Analizar»**: lista solo las carpetas que existen; «Descargas» y «Análisis inteligente» funcionan.

Fallos encontrados y corregidos:

1. **Selección arrastrada entre análisis**: al analizar otra carpeta seguía la selección anterior («2 seleccionados» con el botón en 1), y un elemento que ya no se veía podía acabar en el plan. Ahora la selección se vacía con cada análisis nuevo (verificado: botón en 0).
2. **Mapa sin salida**: entrar en una carpeta sin subcarpetas en el informe (por ejemplo, `node_modules` en el tercer nivel) mostraba una única pieza «Otros». Ahora solo se entra si hay subcarpetas. Para ver más detalle, el menú contextual ofrece «Analizar esta carpeta», y la ayuda emergente lo indica.
3. **Filtro y selección**: el resumen avisa de los elementos marcados que el filtro oculta («2 seleccionados (1 oculto por el filtro)»), porque también irían al plan.
4. **El menú no cambiaba de pestaña**: «Análisis inteligente» desde Memoria RAM no mostraba nada. Ahora lleva a Inicio (o se queda en Limpieza), y las carpetas llevan a Carpetas (o se quedan en Archivos).
5. **Modo de prueba y comandos globales**: con la carpeta sintética, el perfil de Homebrew mostraba la caché real (41,1 MB), porque `brew` es de todo el Mac. Aplicar ese plan en modo de prueba habría ejecutado `brew cleanup` de verdad. Ahora, con una carpeta personal sintética, los comandos de las herramientas se bloquean (como ya pasaba con Vaciar Papelera). Lo cubre una prueba nueva: **57 pruebas, 0 fallos**.

Sin cubrir: los atajos de teclado como pulsaciones reales (el control en segundo plano solo usa el menú, que ejecuta las mismas órdenes), el menú contextual (no se puede abrir en segundo plano) y el selector de carpetas del sistema.

## 0.7 · Barra del disco, ajustes, idiomas y Margin (18-11-2026)

- `swift test`: **62 pruebas, 0 fallos**. Las 5 nuevas (`StorageTests`) comprueban:
  - que cada carpeta va a su categoría y que con una carpeta personal sintética no se mide nada del sistema real;
  - que las partes más el disponible suman exactamente el total;
  - que lo medido de más (clones de APFS, enlaces duros) se recorta y nunca supera lo usado;
  - que los volúmenes de macOS se leen del contenedor de «Data» en el formato real de `diskutil apfs list -plist`, ignorando discos externos e imágenes de simuladores;
  - que la caché se guarda y se lee, y que la carpeta de datos `GestorEspacio` se renombra a `Margin` conservando el registro.
- **Medición real** (`margin disco --text`, 23 s): disco de 245,1 GB, con 21,2 GB disponibles. Apps 25,9 GB; documentos y archivos 2,4; datos de apps y cachés 30,5; desarrollo 60,2; macOS 58,5; purgable 0,9; otros 45,5. Antes de separar macOS, «sistema y otros» era 115 GB (47 %).
- **Pruebas con clics en la app** (datos reales, solo lectura):
  - **Barra y leyenda**: la leyenda muestra los nombres completos (la primera versión los cortaba). «Volver a medir» enseña el progreso y termina en «Medido ahora».
  - **Ajustes**: el tema claro y el oscuro se aplican al momento. Con inglés cambia toda la interfaz, y los tamaños pasan a «21.17 GB» (antes se quedaban con coma por usar el formateador del sistema; corregido). La app se queda en Ajustes al cambiar de idioma (antes volvía a Inicio; corregido). La paleta para daltonismo y el contraste cambian la barra, y los ajustes se conservan al reiniciar. `~/projects` y `~/Projects` (la misma carpeta) se muestran una vez.
  - **Otras pestañas**: Memoria en inglés y modo oscuro; Carpetas muestra «21.17 GB of 245.11 GB».
- Después de probar se devolvieron los ajustes de tema, idioma y accesibilidad a sus valores por defecto.
- **Instalación**: `install.sh` retiró `Gestor Espacio.app`, instaló `Margin.app` y `margin`, y dejó `espacio` como alias. `install-agentes.sh` registró el MCP `margin` (`claude mcp list` → Connected; también en Codex) y retiró `gestor-espacio`. `disk_status` por MCP devuelve el desglose.
- Sin cubrir: la barra de menús del sistema (Archivo, Edición, Ventana) sigue en el idioma de macOS; las explicaciones del análisis están solo en español.

### Cambio de nombre a «Margin» (18-11-2026)

Jorge prefirió «Margin» a «Margen».
- **Código**: se renombraron la app (`Margin.app`, `local.margin.mac`), el comando `margin`, el MCP `margin`, la carpeta de datos y las variables `MARGIN_*`. Los nombres anteriores siguen valiendo: `margen` y `espacio` como alias, y `MARGEN_*` y `ESPACIO_*` como variables.
- **Pruebas**: **63 pruebas, 0 fallos**. La nueva comprueba que una carpeta de datos `Margen` se conserva al renombrarse.
- **Instalación real**:
  - `install.sh` retiró `Margen.app` e instaló `Margin.app`, y dejó `margen` y `espacio` como enlaces a `margin`.
  - La carpeta de datos pasó a `~/Library/Application Support/Margin` con registro, planes y desglose.
  - `install-agentes.sh` dejó registrado solo el MCP `margin` (Claude Code: Connected; Codex: enabled).
  - `espacio disco --text` y `margen --help` funcionan.
  - La app instalada muestra «Margin» en la barra lateral y en la ventana.

## 0.8 · Navegación más fluida y Liquid Glass (18-11-2026)

- Compila con el SDK de macOS 27. El mínimo pasa a macOS 26, que es donde existe Liquid Glass. Pasan las **63 pruebas**.
- **Revisión visual** con capturas, abriendo la app en cada sección (`MARGIN_TAB`), en modo claro y oscuro: Inicio (antes del análisis, tarjetas de carga durante el análisis y resultados con la barra flotante), Carpetas (mapa en cristal, Lista/Mapa en la barra de herramientas), Archivos (búsqueda en la barra de herramientas), Memoria RAM y Ajustes.
- **Lo que no se pudo probar**: la pantalla volvió a bloquearse, así que los clics no fueron posibles. Faltan por comprobar en directo:
  - las animaciones (cambio de sección, mapa, barras que crecen, cifras);
  - el relieve al pasar el ratón;
  - los atajos ⌘1–⌘5;
  - que la barra flotante aparezca al marcar casillas.
  Todo compila y se ve bien en reposo.
- Arreglado durante la revisión: las filas alternas de la tabla de Archivos salían como franjas oscuras sobre el cristal; se desactivaron. Los botones principales de la barra de herramientas («Analizar», «Elegir carpeta…») muestran texto además del icono.
- El análisis inteligente tarda ahora unos 25 s en este Mac (también desde la terminal), no los 12 s medidos el 17-11.
- Se devolvieron a su valor por defecto el tema y la opción de análisis al abrir, que se cambiaron para las capturas.

### Pruebas en directo de la 0.8 (18-11-2026, pantalla desbloqueada)

Hechas con clics sobre una carpeta personal sintética, sin ejecutar ningún plan:

- **Navegación**: la barra lateral cambia de sección con su transición. ⌘1 lleva a Inicio y el menú Visualización lista las cinco secciones.
- **Barras flotantes**: en Limpieza, al marcar un elemento aparece «1 elemento en el plan · 41,1 MB» con «Revisar plan (1)…»; al desmarcarlo, desaparece. En Archivos, la búsqueda nativa de la barra de herramientas filtra, y la barra flotante muestra «2 seleccionados (1 oculto por el filtro)» con «Mover a la Papelera (2)…».
- **Mapa**: Lista/Mapa en la barra de herramientas; se entra en Proyectos y «Subir» vuelve a la raíz, con transición.
- **Arreglado**: VoiceOver leía los nombres internos de los iconos («Sangría De Lista Con Viñetas», «chevron.pulldown») en Lista/Mapa y en Carpetas frecuentes; ahora lee «Lista», «Mapa» y «Carpetas frecuentes».
- **Arreglado**: con una carpeta sintética, la barra de Inicio salía casi entera gris («Otros», 91 %), porque solo se mide esa carpeta. Jorge preguntó por qué. Ahora la barra lateral muestra «Modo de prueba» con la explicación. Con los datos reales, la barra tiene todos sus colores (verificado).
- **Sin cubrir**: el efecto al pasar el ratón (en segundo plano no se puede mover el puntero) y ⌘2–⌘5 pulsados de verdad (⌘1 sí; el resto se probó desde el menú, que ejecuta la misma orden).
- **Arreglado (aviso de Jorge con captura)**: en Carpetas sin analizar, los atajos se cortaban («Carpe…», «Desc…»), porque `ContentUnavailableView` encoge los botones al ancho del texto. Al sacarlos de ella con altura fija también desaparecían la barra lateral y las métricas. Ahora el estado vacío es una vista propia, compartida por Carpetas y Archivos (que no tenía atajos). Verificado con clics: se ven la barra lateral, las métricas y «Carpeta personal», «Descargas», «Escritorio» y «Developer» completos.

## Pendientes cerrados (18-11-2026)

- **Velocidad del análisis inteligente** (`MARGIN_TIMING=1`): de 13,8 s a 8,0 s.
  - Los artefactos de proyectos bajaron de 12,8 a 7 s: el `concurrentPerform` anidado se ejecutaba en serie y ahora se usa una cola propia.
  - Claude Desktop bajó de 9,3 a 7,3 s: cada carpeta se medía dos veces, una para el umbral y otra para el elemento; ahora se mide una sola vez.
  - Los 25 s observados antes coincidieron con una medición del disco en marcha.
- **Inglés en el análisis**: unos 270 textos del núcleo pasan por `loc(es, en)`.
  - Una prueba nueva comprueba que las explicaciones cambian de idioma, pero los identificadores (también los de la CLI) y las acciones no.
  - Otra comprueba que un plan creado en inglés se revalida sin bloqueos en español. Para ello, la revalidación compara las acciones por lo que ejecutan (tipo, argumentos, rutas, procesos) y no por sus textos, y Docker y los simuladores no disponibles tienen una clave fija.
- **Aviso de poco espacio**:
  - Tres pruebas de la regla: avisa por debajo del umbral, como mucho una vez al día, y antes si el espacio libre baja 2 GB más.
  - El modo sin ventana (`--aviso-espacio`) termina al momento si el aviso está desactivado. Con un umbral de 500 GB registra el aviso, y una segunda comprobación no lo repite. No quedó ningún proceso ni agente, y los ajustes se devolvieron a su estado.
  - No se activó el agente ni se envió una notificación real: eso pide el permiso de notificaciones a Jorge.
- **Atajos**: ⌘2–⌘5 probados con pulsaciones reales; cada uno abre su sección. ⌘, (Ajustes) se probó desde el menú.
- **Ajustes**: se ven bien la sección «Aviso de poco espacio» y la fila «Acceso total al disco», en inglés, que es el idioma que tenía guardado la app. Corregido: «Acerca de» decía «Versión 0.7».
- **Total**: **68 pruebas, 0 fallos**.
- **Nota**: como la app se firma ad hoc, al reinstalarla macOS puede olvidar el «Acceso total al disco» concedido; habría que volver a darlo.

## 0.9 · Desinstalación completa de apps (18-11-2026)

- **76 pruebas, 0 fallos**. Las 8 nuevas (`AppsTests`) usan apps de mentira en una carpeta personal sintética y comprueban:
  - la app y sus restos con el riesgo de cada tipo; los contenedores no se recorren, y el ayudante de una app no cuenta como suyo;
  - que las apps de Apple y Margin quedan protegidas;
  - que los restos de una app borrada se agrupan para revisar, sin confundirlos con los de apps instaladas;
  - que el plan mueve solo lo elegido;
  - que una app abierta bloquea su desinstalación;
  - que las apps de Homebrew usan `brew uninstall --cask`;
  - que /Applications queda vetada en modo de prueba, igual que las rutas anidadas;
  - que la revalidación coincide con el informe.
- **Fallo encontrado por las pruebas**: si la app se quitaba primero, sus restos dejaban de constar como suyos y el resto del plan se bloqueaba. Ahora el plan pone la app al final.
- **Datos reales** (`margin apps --text`, 6 s, solo lectura):
  - 48 apps, que ocupan 43,8 GB con sus restos. Claude 14 GB (13,3 GB de datos), Xcode 4 GB de la App Store, VS Code 3,4 GB, y Docker y Godot detectados como Homebrew.
  - 943 MB en restos de apps borradas; el mayor es Whisky, con 822 MB.
  - `com.openai.chat` aparece como resto porque la app «ChatGPT.app» instalada usa el identificador de Codex (`com.openai.codex`): es de la versión anterior.
- **App, con clics y datos reales**:
  - La lista muestra icono, origen, último uso y tamaño; el detalle de Claude, la app y cada resto con su explicación en inglés.
  - «App y restos sin riesgo» marca 4 elementos y aparece la barra flotante.
  - El plan pone los restos primero y la app al final, y bloquea todos los pasos porque Claude estaba abierta («Run 0 steps»). Se canceló.
  - La vista de restos de apps borradas lista cada grupo con sus rutas.
- **No se desinstaló nada real**. La vía de Finder para apps de root o de la App Store (contraseña) no se probó: pediría tu contraseña y movería una app real.
- **MCP**: `apps_report` devuelve las apps con sus `id`, y `propose_cleanup` los acepta. La skill explica el flujo.
- **Nota**: al lanzar el binario directamente sin ventanas guardadas, macOS no abre ninguna; abriendo la app de forma normal sí aparece. Es la restauración de ventanas de macOS, no un fallo.

## Firma estable (18-11-2026)

- `scripts/firma-local.sh` creó la identidad «Margin Local» en el llavero de inicio de sesión: certificado propio de 10 años para firma de código, sin marcarlo como de confianza ni tocar ajustes del sistema. La clave privada se generó en una carpeta temporal que se borra; solo `codesign` puede usarla sin preguntar. Volver a ejecutarlo no hace nada.
- `codesign` firmó con ella sin diálogos las dos primeras veces; en la tercera macOS preguntó si `codesign` podía usar la clave. Jorge eligió «Permitir siempre» y la firma terminó (está explicado en `firma-local.sh`). La app instalada queda con `Authority=Margin Local` y el requisito designado `identifier "local.margin.mac" and certificate leaf = H"42cf6410…"`, que ya no depende del binario: es el mismo en cada compilación, y es lo que macOS usa para recordar permisos.
- Margin abre normalmente con la nueva firma y no hay rechazos en el registro del sistema.
- Pendiente de Jorge: los permisos dados antes, con la firma ad hoc, pueden no valer; hay que darlos una vez más.

## «Marcar todos» en restos de apps borradas (18-11-2026)

- Encima de la lista de restos hay una casilla de grupo: «Select all», con el total («8 leftovers · 943.1 MB» con datos reales). Si hay una búsqueda, dice «Select all matching» y solo afecta a los restos visibles.
- Es un `Toggle(sources:)` de SwiftUI, así que macOS dibuja el estado mixto real (guion) cuando solo hay algunos marcados. Un primer intento con un icono superpuesto se veía como un cuadrado relleno, sin guion, y se descartó.
- Con clics en la app real: marcar Whisky deja la casilla con guion y la barra flotante en «1 item in the plan · 822 MB»; pulsarla marca los 8 («8 items in the plan · 943.1 MB»); pulsarla otra vez los desmarca y la barra desaparece. Buscando «openai» dice «Select all matching · 2 leftovers · 14.4 MB». No se creó ni se aplicó ningún plan.

## Vaciar Papelera siempre a mano y borrado definitivo opcional (18-11-2026)

- **Pruebas**: 80, todas bien. Cuatro nuevas para el borrado definitivo:
  - borra sin usar la Papelera, el registro anota `removed` y el informe no dice «Papelera»;
  - un proyecto que cambió se bloquea igual que sin el ajuste;
  - si un borrado falla, el archivo se queda y no pasa a la Papelera a escondidas;
  - un ejecutor que no sabe borrar definitivamente falla sin tocar nada.
- El ejecutor falso de las pruebas solo borra dentro de su carpeta sintética (`precondition`).
- **App, con clics** (sin vaciar ni borrar nada real):
  - La tarjeta «Papelera» aparece en Inicio sin haber analizado. «Vaciar Papelera…» y «Ver tamaño…» van uno debajo del otro, porque juntos recortaban el botón.
  - Margin › «Vaciar Papelera…» (⇧⌘⌫) abre la confirmación; se canceló. El registro sigue con un único vaciado, de las 08:39 UTC, anterior a estas pruebas.
  - **Fallo encontrado**: el diálogo del sistema dejaba en rojo, como botón predeterminado, «Vaciar definitivamente», así que Retorno habría vaciado la Papelera. `.keyboardShortcut(.defaultAction)` en Cancelar no lo cambia, y no se comprobó pulsando Retorno para no vaciar la Papelera real. Se sustituyó por una confirmación propia (`DestructiveConfirmation`), en la que Retorno y Escape cancelan; también se usa al activar el borrado definitivo.
