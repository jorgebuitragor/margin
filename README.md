# Margin

Margin mide tu disco y te ayuda a liberar espacio en el Mac sin sorpresas: nada se borra sin tu confirmación. Hasta la 0.6 se llamaba «Gestor de espacio para Mac» (`Gestor Espacio.app`, comando `espacio`) y durante unas horas de la 0.7, «Margen»; `espacio` y `margen` siguen funcionando como alias.

Estado: versión local 0.7 (2026-11-18). Uso personal; interfaz en español e inglés. Swift + SwiftUI, macOS 14 como mínimo declarado; validado en macOS 26 / Apple Silicon. No validado en macOS 14 ni Intel.

## Qué incluye

- **Barra del disco** (pestaña Inicio y `margin disco --text`): el total del volumen repartido en apps, documentos y archivos, datos de apps y cachés, desarrollo, macOS, Papelera, purgable por macOS, otros y disponible, con tamaño y porcentaje. Se mide en segundo plano (unos 25 s), se guarda en caché y se actualiza sola al limpiar o vaciar la Papelera. «macOS» suma los volúmenes del sistema que informa `diskutil` y los recursos que descarga macOS; «otros» es lo que no se puede atribuir (datos protegidos de otras apps, carpetas sin permiso de lectura…).
- **Ajustes** (barra lateral o ⌘,): pestaña al abrir, medir el disco y hacer el análisis inteligente al abrir, días de inactividad y carpetas de proyectos, tema (sistema, claro u oscuro), idioma (sistema, español o inglés) y accesibilidad (colores aptos para daltonismo, más contraste, reducir movimiento). Las explicaciones detalladas de cada elemento siguen en español.

- **Totales por carpeta**, con la misma lógica que `du`: espacio asignado, enlaces duros contados una vez, sin seguir enlaces simbólicos ni cruzar a otros volúmenes. Los totales no tienen límite de elementos.
- **Carpetas protegidas medidas**: `Library`, paquetes, `node_modules`, `.build`, `.git`, configuración y credenciales muestran cuánto ocupan, pero sus archivos no se listan y nunca son accionables.
- **Detección de sincronización**: Google Drive en modo espejo (marcadores `.tmp.driveupload`/`.tmp.drivedownload`), Dropbox, `~/Library/CloudStorage` (Google Drive, OneDrive, Box…) e iCloud. Lo sincronizado se mide y queda protegido; si la carpeta analizada está dentro de una sincronizada, todo el informe es solo de medida.
- **Archivos más grandes** fuera de zonas protegidas, con clasificación y explicación: revisar, protegido o no determinado. «Candidato de bajo riesgo» solo lo asignan los perfiles de desarrollo, nunca el análisis genérico de archivos.
- **Análisis inteligente** (pestaña Inicio): en unos 12 s revisa lugares conocidos —cachés de apps (Chrome, Firefox, Go, apps por identificador; nunca las de macOS), registros, instaladores de más de 30 días en Descargas, copias de iPhone, herramientas de desarrollo y la Papelera— y muestra tarjetas por categoría con un botón «Revisar y limpiar» (solo bajo riesgo, con la confirmación de siempre).
- **Vaciar Papelera** (botón en Inicio o `margin vaciar-papelera`): la **única** acción de borrado definitivo, autorizada expresamente. Va aparte de los planes, la hace Finder, pide su propia confirmación (diálogo destructivo; en la CLI, escribir VACIAR en una terminal interactiva), no la proponen los perfiles ni la expone el MCP, y nunca se ejecuta con una carpeta personal de prueba.
- **Perfiles de desarrollo** (`margin dev`, pestaña Limpieza): SDK de Android, emuladores, simuladores y runtimes de iOS, Xcode, artefactos de proyectos (`node_modules`, `.build`, `build`, `target`, `Pods`…), pnpm/npm/yarn, Gradle y Maven, Docker, Homebrew, versiones de Node (nvm), Claude Desktop y VS Code. Cada elemento trae tamaño, recuperable estimado, causa, coste de regenerarlo y el comando oficial de la herramienta dueña.
- App nativa con pestañas Inicio, Limpieza, Carpetas (árbol o mapa de áreas), Archivos (con casillas) y Memoria RAM (presión real y apps que más memoria usan); menú «Analizar» con carpetas frecuentes y atajos de teclado; análisis en segundo plano con cancelación.
- CLI `margin` con JSON para agentes y `--text` para la terminal, y **servidor MCP** (`margin mcp`) con la skill `liberar-espacio` para Claude Code y Codex.

- **Liberar espacio con confirmación** (`margin plan` + `margin apply`, o «Revisar plan…» / «Mover a la Papelera…» en la app): las únicas escrituras posibles son mover a la Papelera o ejecutar el comando oficial de la herramienta dueña. **Fuera de «Vaciar Papelera» no hay borrado definitivo**, ni siquiera como alternativa si la Papelera falla.

`scan` y `dev` no modifican nada. No se leen contenidos, no se detectan duplicados y no se descargan archivos de la nube. Los totales son espacio ocupado, no espacio recuperable.

## Liberar espacio

```sh
margin dev --text                 # cada elemento accionable muestra «id xxxxxxxx»
margin plan 3fa59d9b 1c2d3e4f     # crea un plan; no ejecuta nada
margin plan --file ~/Downloads/viejo.dmg
margin apply <plan>               # revalida, muestra vista previa y pide escribir el código del plan
```

Garantías de `apply` (cubiertas por pruebas):

- Solo entran en un plan elementos «bajo riesgo» o «revisar» con acción; nada protegido, desconocido ni sincronizado. Los archivos sueltos deben ser «Revisar antes de borrar».
- Se captura la identidad (volumen, inodo y, en archivos, tamaño y fecha) al planificar y se comprueba otra vez justo antes de mover: si algo cambió, el paso se bloquea.
- El perfil se recalcula antes de actuar: un proyecto que volvió a estar activo o una imagen que ahora usa un emulador quedan bloqueados.
- Si la app dueña está abierta (Xcode, Claude, VS Code, el emulador, daemons de Gradle…), el paso se bloquea.
- Las rutas deben estar dentro de la carpeta personal, a dos niveles o más, sin enlaces simbólicos en el camino.
- Los comandos se lanzan sin shell, con argumentos fijos (por ejemplo `pnpm store prune`, `xcrun simctl delete unavailable`, `docker builder prune -f`).
- Un plan caduca a las 24 horas y no se puede aplicar dos veces.
- Se registra cada paso en `~/Library/Application Support/Margin/acciones.jsonl` y el resultado en `planes/<id>.resultado.json`. Se informa el espacio disponible antes y después; lo que va a la Papelera no se libera hasta vaciarla.

La confirmación consiste en escribir el código del plan en una terminal interactiva: `apply` se niega a leerlo de una tubería, de modo que un agente (Codex, Claude Code) puede crear planes pero no aplicarlos.

## Agentes (MCP y skill)

```sh
bash scripts/install-agentes.sh   # skill ~/.claude/skills/liberar-espacio + MCP «margin» (ámbito de usuario)
```

El servidor MCP (`margin mcp`, JSON-RPC por stdio) ofrece `disk_status`, `scan_folder`, `dev_report`, `propose_cleanup` y `plan_result`. **Ninguna herramienta ejecuta nada**: `propose_cleanup` guarda un plan y devuelve `margin apply <plan>` para que lo apliques tú. La skill `liberar-espacio` guía a Claude Code: mide, presenta por categoría, pregunta qué incluir, crea el plan y, cuando lo hayas aplicado, revisa el resultado. El mismo script registra el MCP y copia la skill en **Codex** (`codex mcp add`, `~/.codex/skills`) si está instalado; para otros clientes MCP, registra el comando `~/.local/bin/margin mcp`.

Deshacer la integración: `claude mcp remove --scope user margin`, `codex mcp remove margin` y borrar `~/.claude/skills/liberar-espacio` y `~/.codex/skills/liberar-espacio`.

Al analizar la carpeta personal, macOS puede pedir permiso para acceder a datos de otras apps (por ejemplo `~/Library/Containers`). Si se deniega, esa carpeta se cuenta como ilegible y el total se marca como mínimo.

## Instalar

Desde esta carpeta, con Xcode y Swift 6 instalados:

```sh
bash scripts/install.sh
```

Instala `~/Applications/Margin.app` y `~/.local/bin/margin` (con `margen` y `espacio` como alias), sin permisos de administrador. Solo reemplaza una instalación anterior de esta misma app, retira las antiguas `Gestor Espacio.app` y `Margen.app` y conserva planes y registro (la carpeta de datos `GestorEspacio` o `Margen` pasa a llamarse `Margin`). `scripts/build-app.sh` compila sin instalar: deja la app firmada ad hoc en una carpeta temporal, `dist/Margin.zip` y `dist/margin`. El icono se genera con `swift scripts/make-icon.swift` y se versiona en `Resources/`. Sin App Sandbox ni notarización; los permisos de privacidad de macOS siguen aplicando.

La compilación usa una carpeta temporal sin espacios para evitar un fallo de la base de datos de SwiftPM. `--disable-sandbox` afecta al proceso de construcción del paquete, no concede permisos de administrador.

## Consultar desde terminal o agentes

```sh
margin status
margin disco --text
margin scan ~ --depth 2 --min-mb 500 --text
margin scan ~/Developer > informe.json
margin dev --text
margin dev --inactive-days 60 --roots ~/Developer,~/git
```

`dev` tarda unos 30 s. Ejecuta solo consultas de lectura (`xcrun simctl list`, `xcrun simctl runtime list`, `docker system df`, `git log -1`, `pnpm store path`, `brew --cache`). «Recuperable estimado» excluye archivos con enlaces duros compartidos: por eso un `node_modules` de pnpm recupera poco por sí solo y el store de pnpm se mide por lo que ningún proyecto enlaza. Un proyecto es inactivo si no tiene commits ni cambios en sus archivos de primer nivel en 30 días (configurable); los artefactos de proyectos activos se muestran como «conservar».

`scan` devuelve `totalAllocated`, `folders` (ruta, profundidad, tamaño, archivos, `protection`: `protected`/`sync`, `partial`), `entries` (archivos más grandes y carpetas protegidas con su total), `syncedBy`, incidencias y las banderas `cancelled`/`limited`. `limited` significa que se listan solo los archivos más grandes (`--max-files`, 20.000 por defecto); los totales siguen completos. Un total con `partial` o con incidencias es un mínimo. En `scan`, `canDelete` siempre es falso: los archivos sueltos se planifican con `margin plan --file`.

Los resultados incluyen rutas y nombres. Al consultarlos desde un asistente pasan a su conversación: comparte solo el alcance que necesites. La app y la CLI no incluyen clientes de red ni un modelo.

## Pruebas

```sh
CLANG_MODULE_CACHE_PATH="$TMPDIR/margen-clang-cache" swift test --disable-sandbox --scratch-path "$TMPDIR/margen-build"
```

Fixtures sintéticos creados y retirados por las pruebas, sin limpieza sobre archivos personales. Para probar la app de punta a punta sobre una carpeta personal sintética: `MARGIN_HOME=/ruta` (con `MARGIN_SCAN`, `MARGIN_TAB` y `MARGIN_VIEW` para abrirla analizando una carpeta, en una pestaña o en el mapa). En ese modo los comandos de las herramientas y Vaciar Papelera se bloquean; las variables antiguas `MARGEN_*` y `ESPACIO_*` siguen valiendo. Consultar [evidencias](VERIFICACION.md) para resultados y límites comprobados.

## Artefactos y decisiones

- [Plan 0.2 → 0.7](PLAN.md).
- [Especificación y backlog](PROYECTO.md).
- [Clasificación explicada](CLASIFICACION.md).
- [Verificación](VERIFICACION.md).
- [Interfaz](Sources/SpaceApp) (una vista por pestaña, ajustes en `SettingsView.swift`, textos en inglés en `Translations.swift`), [núcleo](Sources/SpaceCore) (desglose del disco en `Storage.swift`), [CLI](Sources/SpaceCLI/main.swift).

Confirmados: disco y diagnóstico de RAM, uso personal, clasificación con causa. Desde la 0.4 hay escritura, solo mediante planes confirmados; desde la 0.5, los agentes proponen por MCP y tú aplicas.

## Siguiente incremento

La 0.7 está hecha. Pendiente: traducir al inglés las explicaciones del análisis (hoy en español), aviso opcional de poco espacio y comprobar a mano los atajos de teclado y los menús contextuales. Plan completo en [PLAN.md](PLAN.md).
