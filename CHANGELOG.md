# Novedades de Margin

Cada versión publicada en [GitHub Releases](https://github.com/jorgebuitragor/margin/releases). Las anteriores a la 0.10 eran solo locales: su detalle está en [PLAN.md](PLAN.md) y [VERIFICACION.md](VERIFICACION.md).

## 0.10.5

- El tamaño de una carpeta con clones es el espacio real: las copias idénticas cuentan una sola vez en el árbol de Carpetas, en el total de la carpeta analizada y en la barra del disco. En la 0.10.4 solo «libera ≥ X» lo tenía en cuenta, y la carpeta de WhatsApp seguía marcando 131 GB.

## 0.10.4

- Las carpetas protegidas (la Biblioteca, datos de apps…) se pueden analizar en modo «solo medir»: se ve qué ocupa cada subcarpeta, sin listar archivos ni proponer nada. Antes, Margin se negaba a analizarlas. También desde el árbol y el mapa (clic derecho › Analizar esta carpeta).
- Margin mide el espacio real: en APFS, las copias que macOS hace sin duplicar datos («clones») ya no cuentan como espacio propio.
  - Al analizar una carpeta, si lo que se liberaría al borrarla es mucho menor que lo que ocupa, se ven las dos cifras («libera ≥ X»).
  - «Recuperable» y la barra del disco usan el espacio real. Antes, una carpeta llena de clones podía parecer cien veces más grande: la de WhatsApp marcaba 131 GB y libera menos de 1 GB.
- WhatsApp en el análisis inteligente: mide sus chats y archivos y explica que se gestionan dentro de WhatsApp (Ajustes › Almacenamiento), con un botón para abrirlo. Nunca entra en un plan.
- Con «Acceso total al disco», la barra del disco cuenta también los contenedores de otras apps como «Datos de apps».

## 0.10.3

- Al vaciar la Papelera, Margin dice exactamente qué se borró («Se borraron para siempre 3 elementos (1,2 GB)»), medido justo antes de vaciarla, y el espacio disponible ahora. Antes solo comparaba el espacio antes y después, que con poco contenido salía igual por el redondeo y que macOS a veces tarda unos segundos en actualizar.

## 0.10.2

- La Papelera aparece en la barra del disco de Inicio con su tamaño y su porcentaje en cuanto tiene algo, y desaparece al vaciarla, sin esperar a volver a medir el disco (necesita acceso total al disco).
- Con la Papelera vacía, el botón de Inicio dice «Papelera vacía».
- La Papelera incluye lo borrado de iCloud Drive (que macOS guarda en una Papelera aparte), como la muestra Finder. En la barra del disco, iCloud Drive cuenta como «Documentos y archivos» en vez de «Datos de apps».
- Limpieza, rehecha para poder revisar:
  - Filtro Todo / Sin riesgo / Para revisar.
  - La lista a la izquierda y un panel de detalle fijo a la derecha: qué es, por qué revisarlo, qué pasa si lo quitas, dónde está (con «Mostrar en Finder»), cómo se quitaría y un botón para incluirlo en el plan.
  - Un clic en la fila la selecciona; la casilla solo la incluye en el plan. Antes, toda la fila era la casilla y el detalle no se podía abrir.
  - Las tarjetas «Recuperable sin riesgo» y «Para revisar» de Inicio llevan a Limpieza ya filtrada.

## 0.10.1

- Margin gasta mucha menos CPU:
  - Rendimiento, mientras está abierta, pasa del 14–23 % de un núcleo a un 5–10 %: un solo recorrido de procesos para memoria y CPU, sin animar cada actualización y cada 5 segundos.
  - El idioma de la interfaz se guarda en memoria en vez de leerse en cada texto.
  - En Inicio, el icono del análisis inteligente ya no se anima sin fin: Inicio pasa del 8,8 % al 2 %.
- Se puede instalar con Homebrew: `brew trust jorgebuitragor/tap` y `brew install --cask jorgebuitragor/tap/margin`.
- Descarga directa en `.dmg` desde el README.
- El servidor MCP informa la versión real de Margin.

## 0.10.0

- Actualizaciones automáticas: Margin busca versiones nuevas en GitHub una vez al día y las instala con tu permiso. Margin › Buscar actualizaciones… lo hace en el momento, y en Ajustes › Actualizaciones se puede elegir que se instalen sin preguntar.
- Rendimiento (antes «Memoria RAM»): además de la memoria, uso de CPU y apps que más CPU usan, temperatura del Mac, tiempo encendido y, en portátiles, carga, capacidad máxima y ciclos de la batería. Se actualiza cada 3 segundos mientras está abierta.
- El intercambio (swap) aparece aparte en la barra del disco, en vez de mezclado con macOS.
- Vaciar la Papelera, más a mano: botón con su tamaño en la barra de Inicio, y clic en el tramo «Papelera» de la barra del disco.
- Ajustes › Permisos: acceso total al disco, notificaciones y control de Finder, cada uno con su estado y un botón para activarlo.
- «Marcar todos» en los restos de apps borradas.
- Borrado definitivo opcional (Ajustes › Borrado definitivo), apagado por defecto y con el riesgo siempre a la vista.
- La herramienta de la terminal `margin` va dentro de la app y se actualiza con ella.
- Licencia GPL-3.0.
