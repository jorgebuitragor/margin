---
name: liberar-espacio
description: Libera espacio en el Mac de Jorge con su Gestor de espacio (servidor MCP `gestor-espacio` o CLI `espacio`). Úsala cuando pida liberar espacio, limpiar el disco, saber qué ocupa espacio o revisar cachés de apps y de desarrollo (Chrome, Firefox, Go, Android, Xcode, simuladores, node_modules, pnpm, Gradle, Docker, Homebrew), registros o instaladores viejos. Mide y crea planes; aplicarlos es siempre decisión de Jorge en su terminal.
---

# Liberar espacio con el Gestor de espacio

El proyecto vive en `~/Developer/gestor-espacio-mac` (ver su `README.md` y `PLAN.md`). Expone las mismas capacidades por dos vías:

- **MCP `gestor-espacio`** (preferida): herramientas `disk_status`, `scan_folder`, `dev_report`, `propose_cleanup`, `plan_result`.
- **CLI** de respaldo, si el MCP no está conectado: `espacio status`, `espacio scan <ruta> --text`, `espacio dev --text`, `espacio plan <id>…`.

## Regla que no se negocia

**Tú nunca aplicas un plan.** No ejecutes `espacio apply` (tampoco con `echo … |`, `run_in_terminal` ni ningún otro medio), no borres, no muevas a la Papelera y no lances tú los comandos de limpieza (`pnpm store prune`, `brew cleanup`, `xcrun simctl delete`…). Tu trabajo termina al entregar el código del plan; Jorge lo aplica escribiéndolo en su terminal. `espacio apply` exige una terminal interactiva precisamente por esto. Lo mismo vale para **vaciar la Papelera** (`espacio vaciar-papelera` o el botón de la app): es la única acción de borrado definitivo y solo la hace Jorge; tú, como mucho, le recuerdas que lo movido a la Papelera no libera espacio hasta vaciarla.

## Flujo

1. **Estado**: `disk_status` → espacio disponible.
2. **Qué se puede recuperar**: `dev_report` (unos 12 s; incluye cachés de apps, registros y Descargas). Si Jorge pregunta qué ocupa el disco en general, añade `scan_folder` con `path: "~"`, `depth: 2`, `min_mb: 500` (unos 3 min; avísale de la espera).
3. **Presenta** en español, agrupado por categoría y ordenado por espacio recuperable:
   - *Candidato de bajo riesgo*: regenerable, con la causa y el coste de regenerar.
   - *Revisar antes de borrar*: explica por qué hay que mirarlo (datos de emuladores, máquina virtual de Claude, versiones de Node con herramientas globales…).
   - Menciona brevemente lo grande que se conserva (`kept`) y por qué.
   - Señala condiciones previas (`condition`): por ejemplo, Claude Desktop debe estar cerrado para retirar sus cachés, y lo estás usando ahora: no las incluyas en el plan salvo que Jorge lo pida.
4. **Pregunta qué incluir**. Por defecto propone solo bajo riesgo. Los de «Revisar» entran únicamente si Jorge los elige uno por uno.
5. **Crea el plan**: `propose_cleanup` con los `id` elegidos (y `files` para archivos sueltos «Revisar antes de borrar»). Entrega a Jorge:
   - el resumen (pasos, recuperable estimado, lo que va a la Papelera frente a los comandos irreversibles);
   - el comando en un bloque `bash`: `espacio apply <plan>`;
   - que caduca a las 24 horas y que lo de la Papelera no se libera hasta vaciarla.
6. **Revisa el resultado** cuando Jorge diga que lo aplicó: `plan_result` con el código. Informa paso a paso (hecho, parcial, falló o bloqueado), el espacio antes y después, y la causa de cada fallo (la salida del comando viene en `output`). Si algo falló por un error del gestor, corrígelo en el repositorio con pruebas, no a mano en el sistema.

## Notas

- Las cifras son espacio asignado (como `du -x`); «recuperable» excluye archivos con enlaces duros compartidos (por eso un `node_modules` de pnpm recupera poco y el store se limpia con `pnpm store prune`).
- Lo protegido o sincronizado (Google Drive en `~/Documents`, iCloud, CloudStorage) no es accionable: no intentes rodearlo.
- Los informes incluyen rutas personales: no las envíes a servicios externos.
