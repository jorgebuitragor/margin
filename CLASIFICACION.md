# Clasificación explicada de archivos

Requisito confirmado por el usuario: indicar qué archivos se pueden borrar, cuáles conviene conservar y la causa. Motor conservador implementado en 0.1 y probado con fixtures sintéticos. Sin reglas de bajo riesgo ni operaciones de borrado; no se ha realizado un análisis de los archivos personales del usuario.

## Categorías de la interfaz

| Categoría | Condición | Explicación que debe mostrar | Acción propuesta |
|---|---|---|---|
| Candidato de bajo riesgo | Regla específica validada, origen conocido y regeneración comprobada; todas las condiciones satisfechas | Qué lo creó, por qué es prescindible y qué coste o efecto tendrá regenerarlo | Revisión y selección explícita; nunca borrado automático |
| Revisar antes de borrar | Archivo personal o potencialmente reutilizable: documentos, vídeos, descargas, instaladores, archivos comprimidos | Puede contener información única o ser necesario para reinstalar; la app no conoce su valor para el usuario | Mostrar en Finder y permitir decisión del usuario si la política de acceso lo admite |
| Conservar / protegido | Sistema, datos de aplicaciones, credenciales, copias de seguridad, bibliotecas y proyectos con dependencias conocidas | Riesgo concreto: pérdida de datos, configuración, recuperación o funcionamiento | Bloquear limpieza desde esta aplicación; orientar a la herramienta propietaria cuando corresponda |
| No determinado | Metadatos insuficientes, permisos denegados, origen o función desconocidos, reglas contradictorias | Qué información falta para clasificar | Sin recomendación de borrado ni acción de limpieza |

«Bajo riesgo» no garantiza que el usuario no lo necesite. Inicialmente no habrá reglas genéricas que otorguen esta categoría por extensión, nombre, edad o ubicación en una carpeta llamada Cache. Es válido que el primer análisis no encuentre ningún archivo de bajo riesgo.

## Ejemplos ilustrativos, no diagnósticos del Mac

- `Descargas/Instalador.dmg`: **revisar**. Puede ser un instalador que ya no se use, pero también la única copia de una versión necesaria. La extensión no demuestra que esté instalado ni que pueda descargarse de nuevo.
- `Documentos/Declaracion.pdf`: **revisar**. Documento personal; antigüedad y tamaño no permiten determinar si sobra.
- `Library/Application Support/...`: **protegido**. Puede contener bases de datos, partidas u otros datos necesarios para una aplicación. No confundir con caché.
- Biblioteca de Fotos o copia de seguridad reconocida: **protegido**. Puede ser la única colección de fotos o vía de recuperación; gestionar desde la aplicación correspondiente.
- Archivo temporal producido por nuestro propio programa, con registro de creación y trabajo terminado: **bajo riesgo**, si una regla comprueba que no es salida del usuario ni está en uso y no afecta recuperación. No implica permiso para limpiar temporales de otras aplicaciones.
- Archivo desconocido o inaccesible: **no determinado**. No se puede establecer su función con la información disponible.

## Motor de reglas

Servicio local determinista `ClassificationService`; no requiere IA. Cada resultado incluye categoría, motivo legible, evidencia observada, condiciones pendientes, efecto esperado, acción permitida e identificador y versión de regla.

Orden de evaluación: exclusiones y protección → restricciones de acceso/sincronización → reglas específicas validadas → revisión de archivos personales reconocidos → no determinado. Una regla de bajo riesgo nunca anula una exclusión. Coincidencias contradictorias no habilitan limpieza.

No inferir que un archivo no está en uso por antigüedad. Cuando una regla necesite comprobarlo y no sea posible, indicar condición no verificada y abstenerse de recomendarlo. No inferir duplicados por nombre o tamaño; detectar duplicados por contenido sigue fuera del MVP, y ni siquiera contenido idéntico prueba que ambas ubicaciones sean prescindibles.

La protección puede basarse en una raíz o paquete sin inspeccionar su contenido. Mostrar «carpeta protegida; contenido no analizado» en vez de fingir una clasificación de cada archivo inaccesible. Se mantienen las exclusiones de Library y del sistema del MVP.

Los archivos de ubicaciones sincronizadas se excluyen de limpieza en el MVP. La interfaz distingue borrar del servicio de retirar una descarga local. Si el proveedor o estado de sincronización es desconocido, no afirmar que la operación solo afecta al Mac.

Revalidar clasificación, identidad, ruta y permisos antes de trasladar a Papelera. Un cambio invalida la selección previa. No mostrar porcentajes de certeza inventados ni sumar bytes protegidos o desconocidos como espacio recuperable.

## Presentación

Columnas: archivo, tamaño, categoría y motivo breve. Un panel «Por qué» muestra evidencia y consecuencias, por ejemplo: «Documento personal. No sabemos si tienes otra copia. Revísalo antes de eliminarlo». Filtros por categoría, etiquetas además de colores y selección inicial vacía.

## Aceptación

- RF-008 / HU-004: todo elemento listado tiene categoría y motivo no vacío; la abstención es explícita.
- RF-009 / HU-004: las causas se apoyan en datos observados o declaran lo desconocido; no inventan una app propietaria, respaldo o regeneración.
- RF-010 / HU-002: la acción respeta la clasificación revalidada; protegidos, desconocidos y sincronizados no se trasladan.
- Probar fixtures sintéticos de documento antiguo, instalador, nombre engañoso de caché, enlace, archivo modificado, regla contradictoria, permisos insuficientes y ubicación protegida/sincronizada.
- Umbral propuesto: cero casos protegidos o desconocidos habilitados para limpieza en el conjunto de pruebas. Superar este conjunto no demuestra seguridad universal.

## Fuentes

- [Apple: liberar almacenamiento](https://support.apple.com/es-es/102624): herramientas de gestión y significado de Datos del sistema, que no es sinónimo de basura.
- [Apple: uso del sistema de archivos](https://developer.apple.com/documentation/foundation/using-the-file-system-effectively): distinción entre datos de soporte y cachés. Las reglas por aplicación requieren validación adicional antes de habilitarse.
