# PRD — Prompt Improver (macOS)

Versión: v0.1 (MVP)
Estado: Draft “freeze para implementación”
Owner: Jaime

## 1. Resumen
Prompt Improver es una app nativa de macOS (SwiftUI) que mejora prompts.
Flujo: el usuario pega un prompt → selecciona una herramienta local (Codex CLI o Claude Code) → selecciona el “target model” (Claude 4.6 / GPT-5.2 / Gemini 3.0) → la app devuelve SOLO el prompt optimizado (en inglés) y permite copiarlo.

La app no integra APIs ni credenciales: ejecuta los binarios locales `codex` o `claude` en modo headless y deja que el agente lea instrucciones/guías desde un workspace efímero.

## 2. Objetivos (Goals)
G1. “Tool rápido”: una sola pantalla, mínimo fricción.
G2. Output estrictamente: SOLO el prompt mejorado (texto plano).
G3. Output siempre en inglés (responsabilidad de las instrucciones del agente).
G4. Soporte a herramientas: Codex CLI y Claude Code.
G5. Selección de target model: Claude 4.6, GPT-5.2, Gemini 3.0.
G6. Streaming si está disponible (mejor UX), pero la verdad fuente es el resultado final.

## 3. No objetivos (Non-goals)
N1. Historial, versionado, proyectos, guardar prompts.
N2. RAG / vector DB / embeddings.
N3. Integraciones con APIs directas (OpenAI/Anthropic/Google).
N4. Edición de ficheros del usuario, lectura de repositorios del usuario, o tool-use real en filesystem del usuario.
N5. Distribución por Mac App Store (solo descarga directa).

## 4. Usuarios y casos de uso
Usuario objetivo: ingenieros que ya usan Codex CLI y/o Claude Code y quieren estandarizar “prompting” para distintos modelos.

Caso de uso principal:
- Pegar prompt en caja de texto.
- Elegir Tool: Codex / Claude.
- Elegir Target model: Claude 4.6 / GPT-5.2 / Gemini 3.0.
- Click “Improve”.
- Ver streaming (si aplica).
- Copiar prompt final.

## 5. UX / UI (Single-screen)
Componentes:
- Input: TextEditor (prompt original).
- Dropdown: Tool (Codex CLI | Claude Code).
- Dropdown: Target model (Claude 4.6 | GPT-5.2 | Gemini 3.0).
- Botón: Improve.
- Botón: Stop (visible mientras corre).
- Output: TextEditor read-only con botón Copy.
- Estado: indicador “Running/Done/Error”.

Reglas:
- El output mostrado en “Done” es el “prompt optimizado” final (sin metadata).
- Streaming: se actualiza el output incrementalmente mientras llega.

## 6. Requisitos funcionales
FR1. Detectar si `codex` y/o `claude` están instalados (discovery + health check).
FR2. Si el tool seleccionado no está disponible, bloquear “Improve” y mostrar instrucción clara.
FR3. Crear workspace efímero por run y poblarlo con:
  - Instrucciones del agente: `AGENTS.md` (Codex) y/o `CLAUDE.md` + `.claude/settings.json` (Claude).
  - Guías: `CLAUDE_PROMPT_GUIDE.md`, `GPT5.2_PROMPT_GUIDE.md` (y mecanismo best-effort para Gemini).
  - Input runtime: `INPUT_PROMPT.txt`, `TARGET_MODEL.txt` (o `RUN_CONFIG.json`).
  - Schema: `optimized_prompt.schema.json`.
FR4. Ejecutar el tool en modo headless:
  - Codex: `codex exec` con JSONL streaming y output final a fichero.
  - Claude: `claude -p` con `--output-format stream-json` para streaming; fallback a `--output-format json --json-schema` si el parse final falla.
FR5. Extraer SOLO el prompt optimizado:
  - Preferente: parse de JSON (schema `{ optimized_prompt: string }`).
  - Fallback (estricto): si no hay JSON válido, tratar como error (no mostrar “basura”).
FR6. Botón Stop cancela el proceso y deja el estado en “Cancelled”.
FR7. Copiar output al clipboard con un click.

## 7. Requisitos no funcionales
NFR1. “No sorpresas”: la app no lee ni modifica archivos del usuario.
NFR2. Seguridad: workspace en directorio temporal; ejecución con sandbox restrictivo cuando sea posible (Codex read-only).
NFR3. Performance: TTFB streaming < 1–3s (dependiente del CLI y red).
NFR4. Robustez del streaming:
  - parser incremental (JSONL / stream-json).
  - límites de memoria y longitud de línea.
NFR5. Observabilidad local:
  - logging local (solo debug), sin telemetría por defecto (open source).
NFR6. Offline: NO (siempre remoto a través del CLI).

## 8. Contrato de salida (Output Contract)
El output final que la app muestra y copia debe cumplir:
OC1. Texto plano (sin fences ```).
OC2. No incluir explicación/rationale.
OC3. No incluir encabezados tipo “Here’s the improved prompt:”.
OC4. No vacío.
OC5. En inglés.

Estrategia de enforcement:
- Pedir al agente output JSON `{ optimized_prompt: "<text>" }` y validar.
- Normalización al render:
  - trim de whitespace
  - si el prompt viene entre comillas JSON -> decodificar correctamente
  - si detectamos fences o prefijos -> tratar como inválido (error)

## 9. Errores y estados
E1. Tool no instalado: “Install Codex CLI / Claude Code and ensure it’s accessible.”
E2. Tool instalado pero no autenticado: mostrar stderr y “Login from Terminal and retry.”
E3. Timeout: “Timed out. Try again.”
E4. Output inválido: “Tool returned invalid output (schema mismatch).”
E5. Cancelled: estado “Cancelled”.

## 10. “Target model” support (definición exacta)
- Claude 4.6: el agente debe optimizar el prompt para Claude 4.6 (según guía Claude).
- GPT-5.2: el agente debe optimizar el prompt para GPT-5.2 (según guía GPT5.2).
- Gemini 3.0: soporte “best-effort” (sin guía dedicada en MVP). El agente optimiza siguiendo mejores prácticas generales y/o reglas en instrucciones.
  - (Futuro): añadir `GEMINI3_PROMPT_GUIDE.md`.

## 11. Criterios de aceptación (Acceptance Criteria)
AC1. En una máquina con `codex` instalado, el flujo “Codex + GPT-5.2” devuelve un prompt final no vacío y copiable.
AC2. En una máquina con `claude` instalado, el flujo “Claude + Claude 4.6” devuelve un prompt final no vacío y copiable.
AC3. Si no existe el binario seleccionado, el botón Improve está deshabilitado y se muestra un mensaje claro.
AC4. Streaming: durante ejecución, el output se actualiza incrementalmente (cuando el tool lo soporte).
AC5. Stop cancela el proceso sin dejar procesos huérfanos.
AC6. La app no requiere configurar keys dentro de la UI.

## 12. Riesgos / supuestos
R1. Cambios de flags/formatos en CLIs → mitigación: capability detection o fijar versiones mínimas.
R2. Contaminación por instrucciones globales del usuario → mitigación:
  - Codex: aislar con `CODEX_HOME` y plantillas de AGENTS.
  - Claude: desactivar auto-memory y forzar project settings.
R3. Gemini 3.0 sin guía dedicada en MVP → calidad best-effort.

## 13. Roadmap
v0.1 (MVP)
- UI single-screen
- Discovery de `codex` / `claude`
- Workspace efímero + plantillas
- Codex adapter con schema + streaming
- Claude adapter con streaming + fallback a json-schema
- Copy + Stop
- Notarización + release (direct download)

v0.2
- Preferencias avanzadas: ruta manual de binarios
- Añadir guía Gemini
- Mejores errores (diagnóstico de login / permisos)

v0.3
- Modo “strict only” (sin streaming) para reproducibilidad total
- Suite de tests de regresión con fixtures de streams