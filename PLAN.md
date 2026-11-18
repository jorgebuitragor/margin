# Plan de Margin (antes «Gestor de espacio») · 0.2 → 0.7

Fecha: 2026-11-17. Parte de la versión 0.1 (ver [PROYECTO.md](PROYECTO.md) y [VERIFICACION.md](VERIFICACION.md)). Estado de partida: 9 pruebas XCTest pasan desde la nueva ubicación `~/Developer/gestor-espacio-mac`; repositorio git recién inicializado, sin commits.

## Diagnóstico de la 0.1 frente al uso real

En noviembre hubo al menos cinco sesiones de Claude Code que liberaron espacio a mano. La 0.1 no habría ayudado en ninguna, por estas razones:

1. **Se salta las carpetas que más ocupan.** `Library`, `node_modules`, `.build` y `.gradle` se tratan como protegidas y ni siquiera se miden. Medición de solo lectura del 2026-11-17 en este Mac:

   | Ubicación | Tamaño |
   |---|---|
   | `~/Library/Android/sdk` | 12 GB |
   | `~/.android/avd` (emuladores) | 3,6 GB |
   | `~/Library/Developer/CoreSimulator` | 3,5 GB |
   | `~/Library/pnpm` (store) | 3,0 GB |
   | `~/Library/Containers/com.docker.docker` | 1,9 GB |
   | `~/Library/Caches` | 1,7 GB |
   | `~/.cache` | 1,7 GB |
   | `~/.gradle` | 1,5 GB |
   | `~/.m2` | 0,8 GB |
   | `~/.npm` | 0,4 GB |

   Espacio libre del volumen ese día: unos 21 GB.
2. **Solo lista archivos sueltos.** No suma por carpeta, así que no responde «¿qué carpeta ocupa más?». Además, el límite de 20.000 elementos hace que un análisis de `~` quede siempre incompleto.
3. **No hace nada.** `canDelete` es siempre falso, y la Papelera (HU-002) no está implementada.
4. **No reconoce Google Drive.** Solo detecta iCloud, pero `~/Documents` se sincroniza con Google Drive (existe `~/Documents/.tmp.driveupload` con enlaces duros a los archivos del proyecto). Esos archivos salen como «revisar» cuando, según [CLASIFICACION.md](CLASIFICACION.md), deberían estar bloqueados. Es un fallo frente a RF-010.
5. **La app no está instalada.** Se genera en una carpeta temporal del sistema con una ruta fija en el README, y la interfaz nunca se validó de punta a punta.
6. **No es accesible para agentes de forma segura.** Hay CLI pero no MCP, y la CLI no sabe proponer acciones.

## Principios que se mantienen

- No hay borrado permanente. Para archivos personales se usa la Papelera; para cachés de herramientas, el **comando oficial de la herramienta dueña** (`xcrun simctl`, `sdkmanager`, `pnpm store prune`, `brew cleanup`, `docker system prune`…), siempre con una vista previa antes.
- «Bajo riesgo» solo se asigna con reglas específicas y versionadas, nunca por nombre, edad o extensión.
- Para afirmar espacio liberado se mide la capacidad disponible del volumen antes y después; no se suman tamaños lógicos.
- Ninguna acción se ejecuta sin la confirmación explícita del usuario, tampoco cuando la pide un agente.

## Incrementos

### 0.2 · Base y visibilidad real (esfuerzo: medio) — ✅ hecha el 2026-11-17, ver VERIFICACION.md

- Hacer el commit inicial y ajustar `.gitignore`. Actualizar el README con la nueva ruta y quitar la ruta temporal fija.
- Añadir `scripts/install.sh`, que instala `Gestor Espacio.app` en `~/Applications` y `espacio` en `~/.local/bin`.
- **Sumar por carpeta:** árbol con tamaño asignado acumulado, ordenado, con desglose por niveles. La suma no tiene límite de elementos; el límite solo aplica al listado de archivos individuales.
- **Medir las carpetas protegidas sin abrirlas a limpieza:** se muestra el tamaño total pero se mantienen bloqueadas. Así `Library/Android/sdk` aparece como 12 GB protegido en lugar de quedar invisible.
- **Detectar sincronización:** `~/Library/CloudStorage/*` (File Provider: Google Drive, OneDrive, Dropbox), además de iCloud y de los atributos y carpetas de Google Drive en `~/Documents` y `~/Desktop`. Lo que se detecte queda protegido.
- Añadir pruebas con fixtures sintéticos de suma por carpeta, carpetas protegidas medidas y ubicaciones sincronizadas.

**Aceptación:** `espacio scan ~` termina con totales por carpeta coherentes con `du -sh` (±5 %), y ningún archivo de una carpeta sincronizada aparece como accionable. *Resultado:* coincide con `du -x` (que no cruza montajes); `du` sin `-x` cuenta dos veces el montaje `devicefs` de CoreDevice.

### 0.3 · Perfiles de desarrollador (esfuerzo: medio-alto; es el que más espacio libera) — ✅ hecha el 2026-11-17, ver VERIFICACION.md

Catálogo versionado (`Sources/SpaceCore/Profiles/`) de **ubicaciones regenerables conocidas**. Cada perfil define:

- cómo detectarlo (ruta y si la herramienta está instalada);
- cómo medirlo;
- qué contenido se puede retirar y cuál no;
- el comando oficial de limpieza, con su variante de vista previa si existe;
- el coste de regenerarlo (tiempo y descarga) y qué deja de funcionar mientras tanto.

Perfiles iniciales, priorizados por lo medido:

| Perfil | Qué propone | Herramienta dueña |
|---|---|---|
| Android SDK | System images y build-tools que ningún AVD ni proyecto usa | `sdkmanager --uninstall` |
| Emuladores Android | AVD sin uso reciente, uno por uno | `avdmanager delete avd` |
| Simuladores iOS | No disponibles y runtimes antiguos | `xcrun simctl delete unavailable`, `xcrun simctl runtime` |
| Xcode | DerivedData, iOS DeviceSupport antiguo | Archivos a la Papelera |
| pnpm / npm | Paquetes del store que ningún proyecto referencia | `pnpm store prune`, `npm cache verify` |
| Gradle / Maven | Versiones de Gradle y caches de dependencias antiguas | Papelera por versión; nunca la carpeta entera |
| Docker | Imágenes colgantes, build cache | `docker system df` → `docker builder prune`, `docker image prune` |
| Homebrew | Descargas y versiones antiguas | `brew cleanup --dry-run` → `brew cleanup` |
| Artefactos de proyecto | `node_modules`, `.build`, `build/`, `target/`, `dist/` en repos sin commits ni cambios en N días | Papelera; se regenera con el gestor del proyecto |

Aquí aparece por primera vez la categoría **«Candidato de bajo riesgo»**, solo para lo que cubre un perfil. En la interfaz se añade una pestaña «Desarrollo» con el total recuperable estimado por perfil y el motivo.

**Aceptación:** en este Mac, el informe de perfiles identifica al menos 10 GB con su causa y su comando, sin ejecutar nada. Las pruebas cubren detección, herramientas ausentes y un proyecto activo que no se propone.

### 0.4 · Acción segura (esfuerzo: alto, por integridad de datos) — ✅ hecha el 2026-11-17, ver VERIFICACION.md

- **Archivos:** HU-002 con `FileManager.trashItem`. Antes de mover, se revalida identidad (inodo y volumen), fecha de modificación, clasificación y permisos. El resultado se informa archivo por archivo y nunca se recurre al borrado permanente como alternativa.
- **Perfiles:** cada uno muestra primero su vista previa (`--dry-run` o equivalente). Al confirmar se ejecuta el comando oficial y se guarda la salida.
- Registro local de acciones en `~/Library/Application Support/GestorEspacio/acciones.jsonl` con fecha, perfil o archivo, bytes antes/después del volumen y resultado. No guarda contenido.
- Medición real: «Espacio disponible: antes X, después Y». Si los archivos están en la Papelera, se aclara que el espacio no se libera hasta vaciarla.
- Pruebas de carrera (el archivo cambia entre la revisión y la acción), de permisos denegados y de fallo parcial, siempre con fixtures sintéticos y nunca sobre archivos reales.

### 0.5 · Integración con agentes (esfuerzo: medio) — ✅ hecha el 2026-11-17, ver VERIFICACION.md

- Servidor **MCP por stdio** (`espacio mcp`) que reutiliza `SpaceCore`. Herramientas:
  - `status`: disco y RAM.
  - `scan_folder`: totales por carpeta, con el alcance que se le indique.
  - `dev_report`: perfiles con tamaño, causa y comando.
  - `propose_cleanup`: devuelve un plan con un identificador.
- El MCP **no ejecuta**. Para ejecutar un plan hace falta `espacio apply <plan-id>` en la terminal del usuario o el botón «Aplicar» en la app. Así un modelo nunca obtiene autorización de borrado por sí mismo, como ya exige el PROYECTO.md.
- Skill `liberar-espacio` para Claude Code: consulta el MCP, presenta el plan y le indica a Jorge el comando para aplicarlo. Sustituye las sesiones manuales.

### 0.6 · Análisis inteligente y pulido (esfuerzo: medio) — ✅ hecha el 2026-11-18 (salvo lo pendiente abajo)

Hecho el 2026-11-17 (pedido por Jorge, al estilo de CleanMyMac):

- Pantalla **Inicio** con «Análisis inteligente» (perfiles en paralelo, unos 12 s) y tarjetas por categoría; «Revisar y limpiar» crea un plan solo con lo de bajo riesgo.
- Perfiles generales: cachés de apps (no las de macOS), registros, instaladores viejos en Descargas, copias de iPhone.
- **Vaciar Papelera**, la única acción de borrado definitivo, autorizada expresamente por Jorge: va aparte de los planes, la hace Finder, tiene confirmación propia, no la propone ningún perfil ni la expone el MCP y está bloqueada en modo de prueba.

También hecho el 2026-11-17:

- **Mapa** (treemap «squarified») en Carpetas, con vista Lista/Mapa, clic para entrar en una carpeta y botón «Subir»; el resto de un nivel aparece como «Otros» para que las áreas sumen el total.
- **Memoria RAM**: presión real de macOS (`kern.memorystatus_vm_pressure_level`: Normal, Advertencia o Crítica) y las 12 apps que más memoria usan (huella física por app, sumando sus procesos auxiliares). Sin purgas ni cierres.
- **Selección y atajos**: casillas en Archivos (además de ⌘/⇧ y clic), menú «Analizar» con carpetas frecuentes (⌘⇧H personal, ⌘⇧L Descargas, ⌘⇧D Escritorio, ⌘⇧P Developer), ⌘O para elegir carpeta y ⌘R para el análisis inteligente, y botones de atajo en el estado vacío de Carpetas.

También hecho el 2026-11-18: pruebas de interacción con clics reales (mapa, casillas, plan, menú) y cinco correcciones, entre ellas la selección arrastrada entre análisis y el bloqueo de comandos globales en modo de prueba. Ver VERIFICACION.md.

Pendiente:

- Probar a mano los atajos de teclado como pulsaciones y el menú contextual del mapa («Analizar esta carpeta»), que no se pueden automatizar en segundo plano.

- Comprobación manual del selector de carpetas del sistema, que corre en otro proceso y no se puede automatizar.
- Opcional: aviso cuando el disco baje de un umbral (LaunchAgent ligero). Solo si Jorge lo quiere.

### 0.7 · Barra del disco, ajustes, idiomas y nuevo nombre (pedido por Jorge) — ✅ hecha el 2026-11-18, ver VERIFICACION.md

- **Barra del disco** en Inicio: el total del volumen por categorías (apps, documentos, datos de apps, desarrollo, macOS, Papelera, purgable, otros) y el disponible. Se mide en segundo plano con caché (`StorageAnalyzer`, `margin disco`) y el MCP la incluye en `disk_status`. Las demás pestañas muestran «disponible de total».
- **Ajustes** (barra lateral y ⌘,): general, análisis (días de inactividad, carpetas de proyectos), tema, idioma, accesibilidad (paleta Okabe-Ito para daltonismo, más contraste, reducir movimiento) y datos.
- **Idiomas**: español e inglés en caliente, con tamaños y fechas en el formato de cada idioma. Las explicaciones del análisis se tradujeron después de la 0.8.
- **Nuevo nombre: Margin** (primero se eligió «Margen»; Jorge prefirió «Margin» el mismo día). App `Margin.app` (`local.margin.mac`) con icono propio, comando `margin` (alias `margen` y `espacio`), MCP `margin`, carpeta de datos `Margin` (migra `GestorEspacio` o `Margen`) y variables `MARGIN_*` (las `MARGEN_*` y `ESPACIO_*` siguen valiendo). La carpeta del repositorio conserva su nombre.

### 0.8 · Navegación y Liquid Glass (pedido por Jorge) — ✅ hecha el 2026-11-18, ver VERIFICACION.md

- Barra lateral nativa (la sección elegida hace de título; se quitan los encabezados repetidos), acciones en la barra de herramientas, búsqueda nativa en Archivos, ⌘1–⌘5.
- Liquid Glass (`glassEffect`, `GlassEffectContainer`, botones `.glass`/`.glassProminent`) en tarjetas, paneles y barras flotantes, sobre un fondo de malla de color por sección. Mínimo: macOS 26.
- Animaciones y efectos de símbolos, con «Reducir movimiento» y «Reducir transparencia» respetados.

Hecho después de la 0.8 (18-11-2026, «primero lo pendiente»):

- **Análisis inteligente más rápido**: de unos 14 s a unos 8 s (los artefactos de proyectos se miden en paralelo con una cola propia y cada carpeta se mide una sola vez). `MARGIN_TIMING=1` muestra el tiempo de cada perfil.
- **Explicaciones del análisis en inglés** (motivos, consecuencias, notas y mensajes de los planes) cuando la app está en inglés. La CLI y el MCP siguen en español. Los planes valen en los dos idiomas.
- **Aviso de poco espacio** opcional (Ajustes): un agente de inicio comprueba cada hora el espacio libre y avisa como mucho una vez al día, salvo que siga bajando.
- **Acceso total al disco**: estado en Ajustes y atajo a Ajustes del Sistema (también desde la tarjeta de la Papelera).

### 0.9 · Desinstalación completa de apps — ✅ hecha el 2026-11-18, ver VERIFICACION.md

- Sección **Apps**, `margin apps` y herramienta MCP `apps_report`. Cada app con sus restos en `~/Library`, encontrados por identificador exacto; por nombre solo en Application Support, y entonces como «revisar».
- Desinstalar va por plan, igual que el resto de la limpieza. La regla de rutas admite solo una app de primer nivel de /Applications: nunca en modo de prueba, nunca de Apple salvo las de la App Store, nunca Margin. Si macOS no deja moverla, la mueve Finder, que pide tu contraseña.
- **Restos de apps ya borradas**: identificadores que ninguna app del Mac usa, comprobados con Spotlight, siempre como «revisar».

Pendiente después de la 0.9:

- **Comprobaciones que solo puede hacer Jorge**: dar acceso total al disco, activar el aviso y mandar el de prueba (permiso de notificaciones), desinstalar de verdad una app de la App Store o de administrador (Finder pide la contraseña), y los atajos, el menú contextual del mapa y los efectos al pasar el ratón.
- ~~Firma estable~~ ✅ hecha el 2026-11-18: la app se firma con la identidad local «Margin Local» (`scripts/firma-local.sh`) en vez de ad hoc, así que macOS conserva sus permisos entre versiones.
- ✅ 2026-11-18: «Marcar todos» en restos de apps borradas; «Vaciar Papelera» siempre a mano (tarjeta sin análisis, menú con ⇧⌘⌫, botón tras un plan) con una confirmación propia en la que Retorno cancela.
- ✅ 2026-11-18, **decisión de Jorge**: borrado definitivo opcional. Cambia la regla «no hay borrado permanente» de la 0.4: ahora es un ajuste de la app, apagado por defecto, con confirmación al activarlo y el riesgo siempre a la vista. Solo afecta a los planes de la app; la CLI y el MCP siguen usando la Papelera, y las apps de /Applications también.
- ✅ 2026-11-18: README de presentación con capturas en claro y oscuro (`docs/capturas/`), hechas sobre una carpeta personal ficticia (`scripts/demo-home.sh`). La documentación técnica que tenía el README pasó a `docs/REFERENCIA.md`. Desde el 2026-11-18 está en GitHub como repositorio **privado** (`jorgebuitragor/margin`); hacerlo público, y con qué licencia, queda como decisión de Jorge.

## Decisiones que necesita Jorge

1. **App Sandbox.** Con sandbox no se puede leer `~/Library` ni ejecutar `sdkmanager`, `docker` o `brew`, que son justo los perfiles de la 0.3. **Recomendación:** sin sandbox, para uso personal y firmada ad hoc, documentado como decisión. Contradice la «siguiente opción» que dejó la 0.1.
2. **Orden.** **Recomendación:** 0.2 → 0.3 → 0.4 antes que la interfaz, porque el valor está en los perfiles de desarrollador. Alternativa: validar primero la interfaz (0.6).
3. **Inactividad de proyectos** para proponer `node_modules` y similares. **Recomendación:** 30 días sin commits ni cambios, configurable.
4. **¿Se mantiene la parte de RAM?** Hoy aporta poco frente al Monitor de Actividad. Se puede congelar para centrarse en el disco.
