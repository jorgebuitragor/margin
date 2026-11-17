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
