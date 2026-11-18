<p align="center">
  <img src="Resources/AppIcon-1024.png" width="128" alt="Icono de Margin: una barra de disco con un margen libre a la derecha">
</p>

<h1 align="center">Margin</h1>

<p align="center">
  <strong>Libera espacio en tu Mac sin sorpresas.</strong><br>
  Margin te enseña en qué se va el disco, te explica qué se puede quitar y por qué, y no borra nada sin tu confirmación.
</p>

<p align="center">
  macOS 26 o posterior · Español e inglés · Versión 0.9
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/capturas/inicio-oscuro.jpg">
  <img src="docs/capturas/inicio-claro.jpg" alt="Inicio de Margin: la barra del disco por categorías y tarjetas con lo recuperable sin riesgo y lo que conviene revisar">
</picture>

## Qué hace

### Ve en qué se va el disco

La pantalla de **Inicio** reparte el disco en apps, documentos, datos de apps, desarrollo, macOS, Papelera y lo que macOS puede purgar por sí mismo. Con el **análisis inteligente**, en unos segundos revisa los lugares donde se acumula espacio (cachés, registros, instaladores viejos, copias del iPhone, herramientas de desarrollo y la Papelera) y separa lo que se puede quitar sin riesgo de lo que conviene revisar.

### Limpia con explicaciones

<img src="docs/capturas/limpieza-claro.jpg" alt="Limpieza: lista de elementos de Xcode, proyectos inactivos, npm y Gradle, cada uno con su riesgo y su tamaño, y una barra con el plan de 4 elementos">

Cada elemento dice qué es, por qué sobra, qué pasa si lo quitas y cuánto cuesta regenerarlo. Margin conoce bien las herramientas de desarrollo: `node_modules` y compilaciones de proyectos que llevan semanas sin tocarse, DerivedData y simuladores de Xcode, SDK y emuladores de Android, Gradle, Maven, npm, pnpm, yarn, Docker, Homebrew y versiones viejas de Node. Cuando una herramienta tiene su propio comando de limpieza (`brew cleanup`, `pnpm store prune`, `xcrun simctl delete unavailable`…), Margin usa ese.

### Desinstala apps con todo lo que dejan

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/capturas/apps-oscuro.jpg">
  <img src="docs/capturas/apps-claro.jpg" alt="Apps: lista de apps con su tamaño y último uso, y el detalle de una app con su caché, sus datos y sus preferencias">
</picture>

Cada app aparece con lo que ocupa junto con sus restos en `~/Library` y cuándo la usaste por última vez. Eliges qué quitar: la app, su caché, sus datos o sus preferencias, cada uno con su nivel de riesgo. También encuentra **restos de apps que ya borraste**, y puedes marcarlos todos de una vez.

<img src="docs/capturas/restos-claro.jpg" alt="Restos de apps borradas: carpetas de apps que ya no están instaladas, con la casilla «Marcar todos»">

### Explora cualquier carpeta

<img src="docs/capturas/carpetas-claro.jpg" alt="Carpetas: mapa de áreas de la carpeta personal, con Library, Documents, Developer y otras carpetas proporcionales a su tamaño">

El mapa de **Carpetas** muestra cada carpeta en proporción a lo que ocupa; con un clic entras en ella. **Archivos** lista los más grandes con una explicación de cada uno. Lo que está sincronizado con iCloud, Google Drive, Dropbox u OneDrive se mide pero nunca se propone.

### Y además

- **Vaciar la Papelera** desde la app: tarjeta en Inicio, menú Margin o ⇧⌘⌫ como en Finder.
- **Aviso de poco espacio**: una notificación cuando el disco baja del umbral que elijas.
- **Memoria RAM**: la presión de memoria real y las apps que más usan.
- **Accesibilidad**: colores aptos para daltonismo, más contraste, «Reducir movimiento», tema claro u oscuro.
- **Terminal y agentes**: la CLI `margin` y un servidor MCP para Claude Code o Codex. Los agentes pueden proponer limpiezas, pero solo tú las aplicas.

## Nada sin tu confirmación

- **Primero un plan.** Lo que elijas se reúne en un plan que revisas entero antes de ejecutar nada.
- **Todo se vuelve a comprobar justo antes de actuar.** Si un archivo cambió, si un proyecto volvió a usarse o si la app dueña está abierta, ese paso se bloquea.
- **A la Papelera.** Margin mueve las cosas a la Papelera, así que puedes recuperarlas desde Finder hasta que la vacíes. El borrado definitivo existe, pero viene **apagado** y, si lo activas en Ajustes, cada plan te lo recuerda.
- **Lo tuyo no se toca.** Documentos, configuración, credenciales, carpetas sincronizadas y las apps de Apple se miden, pero nunca se proponen.
- **Sin red.** Margin no envía nada a internet ni lee el contenido de tus archivos; solo mira tamaños y fechas.

## Instalar

Con Xcode y Swift 6 instalados, desde la carpeta del proyecto:

```bash
bash scripts/install.sh
```

Instala `~/Applications/Margin.app` y el comando `~/.local/bin/margin`, sin permisos de administrador. Para que macOS recuerde los permisos que le des a Margin entre versiones, crea antes una identidad de firma local (solo existe en tu llavero):

```bash
bash scripts/firma-local.sh
```

Opcional: dale **Acceso total al disco** en Ajustes del Sistema › Privacidad y seguridad para que también pueda medir la Papelera y las copias del iPhone.

## Desde la terminal

```bash
margin disco --text          # la barra del disco por categorías
margin dev --text            # el análisis de desarrollo, con un id por elemento
margin plan <id> <id>        # crea un plan; no ejecuta nada
margin apply <plan>          # lo revisa otra vez y pide escribir el código del plan
```

`margin apply` solo funciona en una terminal interactiva: un agente puede crear planes, pero no aplicarlos. Para conectar Margin con Claude Code o Codex: `bash scripts/install-agentes.sh`.

## Más información

- [Referencia técnica](docs/REFERENCIA.md): cada función, las garantías de los planes, la CLI, el servidor MCP y las pruebas.
- [Cómo clasifica Margin](CLASIFICACION.md) lo que encuentra.
- [Plan por versiones](PLAN.md) y [evidencias de verificación](VERIFICACION.md).

Las capturas son de una carpeta personal ficticia creada con `scripts/demo-home.sh`: ninguna muestra datos reales.

Margin es un proyecto personal, sin notarizar ni distribuir en la App Store.
