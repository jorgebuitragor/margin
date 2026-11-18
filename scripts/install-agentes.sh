#!/bin/bash
# Integra el Gestor de espacio con Claude Code (y Codex si está instalado): instala la skill `liberar-espacio` y registra el servidor MCP
# `gestor-espacio` (ámbito de usuario). Requiere haber ejecutado antes scripts/install.sh.
# Deshacer: claude mcp remove --scope user gestor-espacio && rm -rf ~/.claude/skills/liberar-espacio
#           codex mcp remove gestor-espacio && rm -rf ~/.codex/skills/liberar-espacio
set -euo pipefail
cd "$(dirname "$0")/.."
bin="$HOME/.local/bin/espacio"
[ -x "$bin" ] || { echo "Falta $bin: ejecuta antes scripts/install.sh" >&2; exit 1; }
mkdir -p "$HOME/.claude/skills/liberar-espacio"
cp integraciones/claude-code/liberar-espacio/SKILL.md "$HOME/.claude/skills/liberar-espacio/SKILL.md"
if command -v claude >/dev/null; then
  claude mcp remove --scope user gestor-espacio >/dev/null 2>&1 || true
  claude mcp add --scope user gestor-espacio -- "$bin" mcp
else
  echo "No se encontró la CLI de Claude Code; registra el MCP a mano: $bin mcp" >&2
fi
# Codex: misma skill y mismo servidor MCP.
if command -v codex >/dev/null; then
  mkdir -p "$HOME/.codex/skills/liberar-espacio"
  cp integraciones/claude-code/liberar-espacio/SKILL.md "$HOME/.codex/skills/liberar-espacio/SKILL.md"
  codex mcp remove gestor-espacio >/dev/null 2>&1 || true
  codex mcp add gestor-espacio -- "$bin" mcp
  echo "Codex: skill ~/.codex/skills/liberar-espacio · MCP gestor-espacio"
fi
echo "Skill: ~/.claude/skills/liberar-espacio · MCP: gestor-espacio → $bin mcp"
