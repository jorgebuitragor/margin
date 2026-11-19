# Novedades de Margin

Cada versión publicada en [GitHub Releases](https://github.com/jorgebuitragor/margin/releases). Las anteriores a la 0.10 eran solo locales: su detalle está en [PLAN.md](PLAN.md) y [VERIFICACION.md](VERIFICACION.md).

## Sin publicar

- La Papelera aparece en la barra del disco de Inicio con su tamaño y su porcentaje en cuanto tiene algo, y desaparece al vaciarla, sin esperar a volver a medir el disco (necesita acceso total al disco).
- Con la Papelera vacía, el botón de Inicio dice «Papelera vacía».

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
