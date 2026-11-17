# Definición del proyecto

Estado: incremento 0.1 implementado y compilado; núcleo y CLI verificados. Interfaz completa pendiente de validación manual. Fecha: 2026-09-18.

## Problema y valor

El usuario quiere una aplicación Desktop para gestionar espacio en disco y diagnosticar RAM, para uso personal en su Mac. Todavía no conocemos la falta de espacio real, síntomas de lentitud ni frecuencia de uso. No se han analizado sus archivos personales.

Separar dos funciones en la interfaz:

- **Almacenamiento:** encontrar archivos que ocupan disco y ayudar a decidir cuáles retirar.
- **Memoria RAM:** explicar consumo y presión de memoria; no equiparar RAM libre con rendimiento ni prometer aceleración.

Hipótesis de valor: una revisión guiada, con tamaño, ubicación y acciones explícitas, permite decidir mejor qué conservar. Validarla con el usuario antes de ampliar funcionalidades.

## Alternativas y recomendación

| Alternativa | Ventaja | Límite |
|---|---|---|
| Almacenamiento de macOS + Finder + Monitor de Actividad | Ya disponibles; baseline para comparar valor | Flujo repartido entre herramientas |
| App nativa Swift/SwiftUI | Interfaz e integración con macOS; recomendación para este proyecto exclusivo de Mac | Requiere desarrollo específico de Apple |
| Interfaz web empaquetada con puente nativo | Interesante si se confirma soporte para otros sistemas | Añade una capa sin necesidad multiplataforma confirmada |

No se propone IA en ejecución: clasificar por tamaño y aplicar decisiones explícitas no requiere un modelo. No hay backend, cuenta, telemetría ni envío de nombres o contenido de archivos en el MVP propuesto.

## Alcance propuesto

Recorrido: elegir carpeta → analizar → clasificar con explicación → revisar archivos → seleccionar → confirmar traslado a Papelera → ver resultado por archivo.

Requisito adicional confirmado: explicar qué archivos son candidatos a borrado y cuáles conservar. [Contrato de clasificación](CLASIFICACION.md): bajo riesgo, revisar, protegido y no determinado. Forma parte de la primera entrega de análisis.

Primera entrega implementable: análisis de disco de solo lectura y diagnóstico de RAM. Segunda entrega para completar el MVP: traslado selectivo a Papelera. Ambas áreas forman parte del alcance confirmado; el orden de implementación es una propuesta.

Fuera del MVP: eliminación permanente, vaciado automático de Papelera, purga forzada de RAM, cierre forzado de procesos, limpieza indiscriminada de cachés, desinstalación con residuos, antivirus, duplicados, tareas residentes y acceso como administrador. Son límites de producto propuestos para reducir complejidad y validar primero el recorrido básico.

Mover a Papelera no equivale a liberar espacio inmediatamente. La aplicación debe separar bytes seleccionados, bytes trasladados y capacidad disponible observada; no atribuir toda variación del disco a sus acciones.

## Requisitos y aceptación

| ID | Comportamiento | Aceptación observable |
|---|---|---|
| RF-001 | Selección explícita de carpeta | Cancelar el selector no inicia análisis; permiso denegado produce explicación y opción de elegir otra carpeta |
| RF-002 | Escaneo asíncrono de solo lectura | Lista archivos regulares por tamaño; informa elementos omitidos y fallidos; no modifica archivos ni sigue enlaces simbólicos |
| RF-003 | Revisar resultados | Muestra nombre, ubicación, tamaño lógico y asignado cuando esté disponible; filtra por tamaño y permite mostrar en Finder; ninguna selección inicial |
| RF-004 | Cancelar y reiniciar | Cancelación detiene trabajo; resultados parciales se identifican; un análisis anterior no reemplaza resultados de otro posterior |
| RF-005 | Traslado selectivo a Papelera | Resumen previo y confirmación; revalida identidad, ubicación y cambios del archivo; registra éxito o error individual; nunca usa eliminación permanente como fallback |
| RF-006 | Comunicar resultado real | Archivos enviados a Papelera se etiquetan como tales; no se presentan como espacio ya liberado; fallos parciales no aparecen como éxito total |
| RF-007 | Diagnóstico de RAM | Muestra métricas con fuente y hora; si una API no está disponible lo indica; no inventa presión de memoria a partir del porcentaje usado |
| RF-008 | Clasificar archivos | Todo resultado incluye categoría explícita según CLASIFICACION.md |
| RF-009 | Explicar la causa | Presenta evidencia, consecuencia y condiciones pendientes sin inferir que edad o tamaño implican que sobra |
| RF-010 | Respetar clasificación al limpiar | Revalida antes de actuar y bloquea protegidos, desconocidos y ubicaciones sincronizadas |
| RNF-001 | Privacidad y permisos mínimos | Procesamiento local, sin peticiones de red; acceso limitado a carpetas autorizadas; sin permisos de administrador |
| RNF-002 | Protección de archivos | Excluye raíces del sistema, bibliotecas de usuario, paquetes de aplicaciones y bibliotecas de fotos del flujo inicial; tampoco recorre enlaces ni descarga archivos remotos |
| RNF-003 | Interfaz utilizable | Estados vacío, progreso, parcial, cancelado, error y final; navegación con teclado y etiquetas de accesibilidad |

Umbrales propuestos: en un conjunto sintético conocido, detectar el 100 % de archivos elegibles y cero modificaciones durante el análisis. Para Papelera, cero operaciones sobre elementos no seleccionados. Medir tiempo, CPU y memoria con tamaño de muestra y hardware registrados antes de fijar un presupuesto de rendimiento.

## Arquitectura propuesta

Una aplicación local con SwiftUI para ventanas y AppKit donde se necesiten selector y acciones de Finder. SwiftUI se integra con AppKit según la documentación oficial de Apple.

- `ScanService`: enumera metadatos en segundo plano, gestiona cancelación y emite resultados parciales y errores. Sin lectura de contenido en el análisis inicial.
- `AccessService`: mantiene el acceso a la carpeta concedido por el usuario; probar App Sandbox y acceso mediante URLs con ámbito de seguridad en la app empaquetada.
- `SafetyPolicy`: valida raíces permitidas, archivos elegibles y exclusiones antes de listar acciones y de ejecutarlas. Debe controlar también selección directa de una carpeta excluida.
- `ClassificationService`: aplica reglas locales versionadas y produce categoría, causa, evidencia, condiciones y acción permitida; se integra con SafetyPolicy según CLASIFICACION.md.
- `TrashService`: valida de nuevo y usa la API nativa de Papelera. Una identidad o fecha modificada exige volver a revisar el elemento. Probar carreras entre validación y operación antes de habilitar limpieza.
- `MemoryService`: primera entrega; elegir y verificar APIs públicas y disponibilidad real antes de prometer métricas por proceso o equivalencia con Monitor de Actividad.
- Estado en memoria por sesión, con identificador de análisis. Persistir solo preferencias inicialmente; no guardar inventarios de rutas personales ni contenidos en registros.

Contrato de resultado: identificador de sesión, raíz autorizada, entradas con identidad, URL, tamaño lógico, tamaño asignado opcional y modificación; resumen con omitidos, errores y estado de completitud. Un valor no disponible se representa como desconocido, nunca como cero.

Tamaños no son una promesa de recuperación: enlaces duros, clones APFS, instantáneas, compresión y archivos en la nube pueden impedir que sumas lógicas representen espacio recuperable. Identificar enlaces duros por identidad; no descargar archivos de nube para medirlos. Si el almacenamiento remoto no puede identificarse de manera fiable, excluirlo del flujo de limpieza hasta verificarlo.

### Decisiones pendientes

- Swift/SwiftUI es recomendación, no stack impuesto por el usuario.
- Probar App Sandbox con carpetas elegidas como primera opción. El canal de distribución puede cambiar capacidades; no presuponer acceso a todo el disco.
- Versión mínima de macOS, arquitecturas soportadas y canal de instalación por definir. El entorno consultado tiene macOS 26.5.2 y una ruta de Swift en Xcode; esto no demuestra compilación ni compatibilidad.
- Uso personal confirmado; instalación local propuesta. Distribución comercial excluida del alcance actual. No se han estimado precios ni plazos.

## Backlog por recorridos

| Historia | Resultado y aceptación | Dependencia | Esfuerzo relativo |
|---|---|---|---|
| HU-001 | Como usuario elijo una carpeta y veo archivos grandes sin modificar nada. Cumple RF-001–004, RNF-001–003 aplicables; verifica fixtures y UI | Ninguna | Medio |
| HU-002 | Como usuario envío archivos seleccionados a Papelera y entiendo fallos parciales. Cumple RF-005–006; verifica revalidación, exclusiones y recuperación manual desde Finder con archivos sintéticos | HU-001 | Alto por integridad de datos |
| HU-003 | Como usuario entiendo el estado de RAM con métricas verificadas y acceso al Monitor de Actividad. Cumple RF-007 sin acciones automáticas sobre procesos | Prueba de APIs; primera entrega junto a HU-001 | Medio, sujeto a permisos |
| HU-004 | Como usuario distingo qué revisar o conservar y entiendo la causa por archivo. Cumple RF-008–009; RF-010 se integra en HU-002 | HU-001; antes de HU-002 | Medio; reglas conservadoras y abstención |

Después: duplicados por contenido con verificación adicional, cachés específicas con reglas documentadas por aplicación, e historial local opcional. Cada extensión necesita su propio criterio de seguridad y evidencia.

## Operación y costes

Sin servicio remoto ni coste por llamada de IA en la arquitectura propuesta. Costes aún sin estimar: desarrollo, pruebas, mantenimiento y eventualmente distribución. No se requieren cuentas para la definición actual.

La recuperación del traslado se realizará desde la Papelera de Finder mientras el archivo siga allí; no prometer restauración después de vaciarla. Pruebas de escritura solo con archivos sintéticos dedicados. No limpiar el Mac real para demostrar el proyecto.

## Fuentes oficiales consultadas

Consultadas el 18 de septiembre de 2026:

- [Memoria en Monitor de Actividad](https://support.apple.com/es-es/guide/activity-monitor/actmntr1004/mac): presión, compresión, caché e intercambio.
- [Liberar almacenamiento](https://support.apple.com/es-es/102624): herramientas integradas y distinción entre trasladar a Papelera y liberar almacenamiento.
- [Acceso desde App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox): carpetas elegidas y permisos de acceso. La integración sigue pendiente de prueba.
- [SwiftUI](https://developer.apple.com/swiftui/): interfaz nativa e interoperabilidad con AppKit.

## Implementación 0.1 y decisiones efectivas

Swift 6 / SwiftUI, sin dependencias externas. App macOS local firmada ad hoc, sin App Sandbox aún; los permisos del sistema siguen aplicando. La alternativa de App Sandbox se mantiene para el siguiente incremento, y todavía no se habilita ninguna operación de escritura.

HU-001/HU-004: núcleo implementado con pruebas de tamaños, orden, cancelación, permisos, exclusiones y causas. Interfaz compilada y apertura observada; recorrido completo de selector, filtros y detalle pendiente de validación manual por limitación de la automatización de UI.

HU-003: métricas nativas implementadas, salida CLI real comprobada. No se calcula presión de memoria ni consumo por proceso; se ofrece acceso al Monitor de Actividad. `vm.swapusage` está restringido bajo el entorno de ejecución de Codex; se devuelve no disponible, no cero.

HU-002/RF-005/RF-010: traslado a Papelera y revalidación previa a escritura pendientes. El motor actual solo ofrece metadatos; todas las entradas tienen `canDelete: false`. No hay reglas aprobadas de bajo riesgo. No se detectan proveedores de nube distintos de iCloud; no habilitar limpieza antes de resolverlo.

Interfaz de comandos añadida para consultas desde terminal autorizada de Codex/Claude Code. MCP no implementado. Los informes JSON incluyen nombres/rutas; el usuario decide qué compartir con agentes externos.
