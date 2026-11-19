# Margin · referencia técnica

Qué hace cada parte de Margin, qué garantías tiene y cómo se usa desde la terminal y con agentes. La presentación está en el [README](../README.md).

Hasta la 0.6 se llamaba «Gestor de espacio para Mac» (`Gestor Espacio.app`, comando `espacio`) y durante unas horas de la 0.7, «Margen»; `espacio` y `margen` siguen funcionando como alias.

Estado: versión 0.10.0 (2026-11-18), publicada en GitHub Releases con actualizaciones automáticas. Uso personal; interfaz en español e inglés. Swift + SwiftUI con Liquid Glass; requiere macOS 26 o posterior (validado en macOS 27 / Apple Silicon).

## Qué incluye

- **Barra del disco** (pestaña Inicio y `margin disco --text`): el total del volumen repartido en apps, documentos y archivos, datos de apps y cachés, desarrollo, macOS, Papelera, purgable por macOS, otros y disponible, con tamaño y porcentaje. Se mide en segundo plano (unos 25 s), se guarda en caché y se actualiza sola al limpiar o vaciar la Papelera. «macOS» suma los volúmenes del sistema que informa `diskutil` y los recursos que descarga macOS; «otros» es lo que no se puede atribuir (datos protegidos de otras apps, carpetas sin permiso de lectura…).
- **Apps** (0.9, sección Apps y `margin apps --text`): cada app con lo que ocupa junto con sus restos en `~/Library` y la última vez que la usaste (según Spotlight).
  - **Desinstalar** es un plan como cualquier otro: los restos elegidos y la app van a la Papelera, primero los restos y la app al final. Si vino de Homebrew se usa `brew uninstall --cask`, y las de root o de la App Store las mueve Finder, que pide tu contraseña. Se bloquea si la app está abierta.
  - **Restos por riesgo**: caché, estado de ventanas, datos web y registros son de bajo riesgo; datos, preferencias, contenedores y agentes de inicio, «revisar».
  - **Protegidas**: las apps de Apple incluidas con macOS y Margin. Lo que está fuera de tu carpeta personal solo se informa.
  - **Restos de apps ya borradas**: carpetas con el identificador de una app que no está instalada, siempre como «revisar».
- **Diseño macOS 26** (0.8): barra lateral nativa sin títulos repetidos, acciones de cada sección en la barra de herramientas, búsqueda de Archivos en la barra, tarjetas y paneles de Liquid Glass sobre un fondo de color que cambia con la sección, barras de acción flotantes («Revisar y limpiar», «Revisar plan», «Mover a la Papelera») que aparecen solo cuando hay algo que hacer, ⌘1–⌘5 para saltar entre secciones. Animaciones: la barra del disco se llena al abrir y brilla mientras mide, las cifras cambian con transición, las tarjetas entran escalonadas, tarjetas de carga durante el análisis, el mapa se anima al entrar y salir de carpetas, iconos con efectos. Todo respeta «Reducir movimiento» y «Reducir transparencia» de macOS.
- **Aviso de poco espacio** (Ajustes): un agente de inicio comprueba cada hora el espacio libre (solo lo lee) y avisa con una notificación cuando baja del umbral elegido, como mucho una vez al día salvo que siga bajando. Desactivarlo retira el agente.
- **Ajustes** (barra lateral o ⌘,): pestaña al abrir, medir el disco y hacer el análisis inteligente al abrir, días de inactividad y carpetas de proyectos, tema (sistema, claro u oscuro), idioma (sistema, español o inglés) y accesibilidad (colores aptos para daltonismo, más contraste, reducir movimiento).

- **Totales por carpeta**, con la misma lógica que `du`: espacio asignado, enlaces duros contados una vez, sin seguir enlaces simbólicos ni cruzar a otros volúmenes. Los totales no tienen límite de elementos.
- **Carpetas protegidas medidas**: `Library`, paquetes, `node_modules`, `.build`, `.git`, configuración y credenciales muestran cuánto ocupan, pero sus archivos no se listan y nunca son accionables.
- **Detección de sincronización**: Google Drive en modo espejo (marcadores `.tmp.driveupload`/`.tmp.drivedownload`), Dropbox, `~/Library/CloudStorage` (Google Drive, OneDrive, Box…) e iCloud. Lo sincronizado se mide y queda protegido; si la carpeta analizada está dentro de una sincronizada, todo el informe es solo de medida.
- **Archivos más grandes** fuera de zonas protegidas, con clasificación y explicación: revisar, protegido o no determinado. «Candidato de bajo riesgo» solo lo asignan los perfiles de desarrollo, nunca el análisis genérico de archivos.
- **Análisis inteligente** (pestaña Inicio): en unos 12 s revisa lugares conocidos —cachés de apps (Chrome, Firefox, Go, apps por identificador; nunca las de macOS), registros, instaladores de más de 30 días en Descargas, copias de iPhone, herramientas de desarrollo y la Papelera— y muestra tarjetas por categoría con un botón «Revisar y limpiar» (solo bajo riesgo, con la confirmación de siempre).
- **Vaciar Papelera** (tarjeta en Inicio, aunque no se haya analizado; menú Margin › Vaciar Papelera…, ⇧⌘⌫ como en Finder; botón en el resultado de un plan que usó la Papelera; o `margin vaciar-papelera`): va aparte de los planes, la hace Finder y pide su propia confirmación, en la que Retorno y Escape cancelan (en la CLI, escribir VACIAR en una terminal interactiva). No la proponen los perfiles ni la expone el MCP, y nunca se ejecuta con una carpeta personal de prueba.
- **Borrado definitivo** (Ajustes › Borrado definitivo, **apagado por defecto**): los planes de la app borran sin pasar por la Papelera. Activarlo pide confirmación, el riesgo se explica siempre en Ajustes, y mientras está activado lo recuerdan la barra lateral y cada plan («Borrar definitivamente: …»). Las comprobaciones de seguridad son las mismas; si un borrado falla, el archivo se queda donde estaba (no pasa a la Papelera a escondidas). Las apps de /Applications van siempre a la Papelera, porque un borrado a medias por permisos las dejaría rotas. La CLI (`margin apply`) y el servidor MCP nunca borran definitivamente.
- **Perfiles de desarrollo** (`margin dev`, pestaña Limpieza): SDK de Android, emuladores, simuladores y runtimes de iOS, Xcode, artefactos de proyectos (`node_modules`, `.build`, `build`, `target`, `Pods`…), pnpm/npm/yarn, Gradle y Maven, Docker, Homebrew, versiones de Node (nvm), Claude Desktop y VS Code. Cada elemento trae tamaño, recuperable estimado, causa, coste de regenerarlo y el comando oficial de la herramienta dueña.
- App nativa con pestañas Inicio, Limpieza, Apps, Carpetas (árbol o mapa de áreas), Archivos (con casillas) y Rendimiento; menú «Analizar» con carpetas frecuentes y atajos de teclado; análisis en segundo plano con cancelación.
- **Rendimiento** (antes «Memoria RAM»), solo lectura:
  - uso de CPU entre dos muestras (`host_statistics`), con la carga media;
  - apps que más CPU usan (tiempo de CPU por proceso con `proc_pid_rusage`, agrupado por app);
  - estado térmico de macOS y tiempo encendido;
  - batería por IOKit: carga, capacidad máxima frente a la de fábrica y ciclos (no aparece en Macs de escritorio);
  - lo que ya había: presión de memoria, intercambio, memoria cableada y comprimida, y apps que más memoria usan.
  Se actualiza cada 3 segundos solo mientras la sección está abierta.
- **Intercambio (swap)** en la barra del disco: el tamaño de los archivos de intercambio (`vm.swapusage`, total). Se relee en vivo y se descuenta de «macOS», que antes lo incluía.
- **Permisos** (Ajustes):
  - acceso total al disco: macOS no deja pedirlo, así que el botón abre el panel;
  - notificaciones: se piden con el diálogo del sistema;
  - control de Finder (Automatización), que necesita «Vaciar Papelera»: se pide con `AEDeterminePermissionToAutomateTarget`.
  Cada uno muestra su estado y se vuelve a comprobar al volver a la app.
- **Actualizaciones** (Sparkle 2):
  - lee `appcast.xml` de la última GitHub Release una vez al día;
  - comprueba la firma EdDSA y que la versión nueva esté firmada con la misma identidad;
  - sin perfil del sistema (`SUEnableSystemProfiling` apagado);
  - menú Margin › Buscar actualizaciones… y Ajustes › Actualizaciones (comprobar sola, instalar sin preguntar);
  - no se activa en modo de prueba ni cuando la app corre como agente de aviso.
- CLI `margin` con JSON para agentes y `--text` para la terminal, y **servidor MCP** (`margin mcp`) con la skill `liberar-espacio` para Claude Code y Codex.

- **Liberar espacio con confirmación** (`margin plan` + `margin apply`, o «Revisar plan…» / «Mover a la Papelera…» en la app): las únicas escrituras posibles son mover a la Papelera o ejecutar el comando oficial de la herramienta dueña. **Fuera de «Vaciar Papelera» y del ajuste «Borrado definitivo» de la app no hay borrado definitivo**, ni siquiera como alternativa si la Papelera falla.

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

## Publicar una versión

```sh
# 1. Sube VERSION y añade «## <versión>» a CHANGELOG.md. 2. Commit y push de main. 3.
bash scripts/release.sh
```

`release.sh` comprueba que main está limpia y subida, compila y firma la app con «Margin Local», firma el ZIP con la clave EdDSA de Sparkle (en el llavero; la pública está en `Resources/sparkle-clave-publica.txt`) y crea la release `v<versión>` con el ZIP y `appcast.xml`. El número de compilación es el número de commits. Todo ocurre en este Mac: ninguna clave sale de él ni se guarda en GitHub. **Si se pierde la clave privada de Sparkle, las copias instaladas no aceptarán más actualizaciones**: conviene guardar una copia (`generate_keys -x archivo`) en un lugar seguro.

## Instalar

Desde esta carpeta, con Xcode y Swift 6 instalados:

```sh
bash scripts/install.sh
```

Instala `~/Applications/Margin.app` y `~/.local/bin/margin`, que es un enlace a la CLI que va dentro de la app (`Contents/Helpers/margin`), así que se actualiza con ella; `margen` y `espacio` siguen como alias. No hacen falta permisos de administrador. Solo reemplaza una instalación anterior de esta misma app, retira las antiguas `Gestor Espacio.app` y `Margen.app` y conserva planes y registro (la carpeta de datos `GestorEspacio` o `Margen` pasa a llamarse `Margin`). La app se firma con «Margin Local», un certificado propio que solo existe en tu llavero (lo crea una vez `bash scripts/firma-local.sh`; sin él se firma ad hoc). Si macOS pregunta si `codesign` puede usar esa clave, elige «Permitir siempre». Así macOS la reconoce entre versiones y no olvida los permisos que le diste, como el acceso total al disco o las notificaciones. `scripts/build-app.sh` compila sin instalar: deja la app firmada en una carpeta temporal, `dist/Margin.zip` y `dist/margin`. Toma la versión de `VERSION`, incluye Sparkle en `Contents/Frameworks` y, si existe la clave pública, la configuración de actualizaciones. El icono se genera con `swift scripts/make-icon.swift` y se versiona en `Resources/`. Sin App Sandbox ni notarización; los permisos de privacidad de macOS siguen aplicando.

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

Los resultados incluyen rutas y nombres. Al consultarlos desde un asistente pasan a su conversación: comparte solo el alcance que necesites. La CLI no usa la red. La app solo la usa para consultar si hay una versión nueva (Sparkle, contra GitHub Releases), y eso se puede apagar en Ajustes. Ninguna de las dos incluye un modelo.

## Pruebas

```sh
CLANG_MODULE_CACHE_PATH="$TMPDIR/margin-clang-cache" swift test --disable-sandbox --scratch-path "$TMPDIR/margin-build"
```

Fixtures sintéticos creados y retirados por las pruebas, sin limpieza sobre archivos personales. Para probar la app de punta a punta sobre una carpeta personal sintética se usa `MARGIN_HOME=/ruta`, y `MARGIN_SCAN`, `MARGIN_TAB` y `MARGIN_VIEW` la abren analizando una carpeta, en una pestaña o en el mapa. `bash scripts/demo-home.sh /private/tmp/margin-demo` crea una carpeta así, con proyectos, cachés, apps y restos de ejemplo; es la de las capturas del README, y `MARGIN_CAPTURAS=1` oculta la etiqueta «Modo de prueba». En ese modo los comandos de las herramientas y Vaciar Papelera se bloquean; las variables antiguas `MARGEN_*` y `ESPACIO_*` siguen valiendo. Consultar [evidencias](../VERIFICACION.md) para resultados y límites comprobados.

## Artefactos y decisiones

- [Plan por versiones](../PLAN.md).
- [Especificación y backlog](../PROYECTO.md).
- [Clasificación explicada](../CLASIFICACION.md).
- [Verificación](../VERIFICACION.md).
- [Interfaz](../Sources/SpaceApp) (una vista por pestaña, ajustes en `SettingsView.swift`, textos en inglés en `Translations.swift`), [núcleo](../Sources/SpaceCore) (desglose del disco en `Storage.swift`), [CLI](../Sources/SpaceCLI/main.swift).

Confirmados: disco y diagnóstico de RAM, uso personal, clasificación con causa. Desde la 0.4 hay escritura, solo mediante planes confirmados; desde la 0.5, los agentes proponen por MCP y tú aplicas.

## Siguiente incremento

Lo pendiente y lo que solo puede comprobar una persona está en [PLAN.md](../PLAN.md); las evidencias de cada versión, en [VERIFICACION.md](../VERIFICACION.md).
