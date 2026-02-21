# ARCHITECTURE — Prompt Improver (macOS)

Versión: v0.1 (MVP)
Objetivo: describir arquitectura técnica y estructura de repo para implementar PRD.md.

## 1. Decisiones clave (Design Decisions)
D1. App nativa: SwiftUI + Swift Concurrency.
D2. Backend: CLIs locales (`codex`, `claude`) en modo headless. La app NO usa APIs directas.
D3. No RAG: los agentes leen ficheros Markdown desde un workspace efímero.
D4. Contrato de salida: JSON `{ optimized_prompt: string }` siempre que sea posible.
D5. Streaming:
  - Codex: `--json` (JSONL events).
  - Claude: `--output-format stream-json` (+ verbose + include partial messages).
  - Si falla parse final en Claude: fallback a `--output-format json --json-schema`.
D6. Seguridad: no tocar filesystem del usuario; workspace temporal; sandbox restrictivo en Codex.

## 2. Flujo de datos (Data Flow)
1) UI recoge: (tool, targetModel, inputPrompt)
2) WorkspaceManager crea /tmp/<app>/run-<uuid>/
3) WorkspaceManager escribe:
   - INPUT_PROMPT.txt
   - TARGET_MODEL.txt
   - templates: AGENTS.md / CLAUDE.md / .claude/settings.json
   - PROMPT_GUIDEs
   - optimized_prompt.schema.json
4) Provider (Codex/Claude) ejecuta CLI con `cwd = workspace`.
5) ProcessRunner streamea stdout/stderr.
6) StreamParser produce deltas para UI.
7) Provider produce resultado final:
   - preferente: parse JSON schema -> optimized_prompt
   - error si schema mismatch
8) UI muestra optimized_prompt y permite Copy.

## 3. Invariantes (deben cumplirse siempre)
I1. La app nunca escribe fuera del workspace temporal.
I2. Nunca se muestra nada salvo el prompt final (sin metadatos).
I3. El prompt final no puede ser vacío.
I4. Cancelación mata el proceso y libera recursos.
I5. Parser de streaming no debe reventar con líneas parciales o UTF-8 cortado.

## 4. Chequeos de estabilidad (streaming / buffers)
Aunque no hay cómputo numérico, hay estabilidad de parsing:
S1. Parsing incremental por líneas (JSONL / NDJSON): solo decodificar cuando haya '\n'.
S2. Control de tamaño de buffer:
  - maxLineBytes (p.ej. 8 MiB). Si se excede: abort con error.
  - maxBufferedBytes (p.ej. 32 MiB). Si se excede: backpressure o abort.
S3. UTF-8 safety: no convertir Data->String si el chunk no es UTF-8 completo; acumular y reintentar.
S4. Timeout por run (p.ej. 120s) + cancelación manual.

## 5. Estructura de repo (propuesta)
.
├─ PRD.md
├─ ARCHITECTURE.md
├─ README.md
├─ LICENSE
├─ PromptImprover.xcodeproj
├─ PromptImprover/
│  ├─ App/
│  │  ├─ PromptImproverApp.swift        # entrypoint
│  │  └─ RootView.swift                 # UI single-screen
│  ├─ UI/
│  │  ├─ PromptEditorView.swift
│  │  ├─ OutputView.swift
│  │  └─ Components/...
│  ├─ Core/
│  │  ├─ Models.swift                   # Tool, TargetModel, RunState, etc.
│  │  ├─ Errors.swift                   # error taxonomy
│  │  └─ Contracts.swift                # schema / output contract helpers
│  ├─ Execution/
│  │  ├─ ProcessRunner.swift            # Process + pipes + cancel + timeout
│  │  ├─ StreamLineBuffer.swift         # incremental newline buffering
│  │  └─ Logging.swift                  # local debug logs
│  ├─ Providers/
│  │  ├─ Provider.swift                 # protocol + RunEvent stream
│  │  ├─ CodexProvider.swift
│  │  ├─ ClaudeProvider.swift
│  │  └─ Parsers/
│  │     ├─ CodexJSONLParser.swift
│  │     └─ ClaudeStreamJSONParser.swift
│  ├─ Workspace/
│  │  ├─ WorkspaceManager.swift         # create temp dir, write files, cleanup
│  │  └─ Templates.swift                # load templates from app bundle
│  ├─ CLI/
│  │  ├─ CLIDiscovery.swift             # locate codex/claude
│  │  └─ CLIHealthCheck.swift           # --version, basic smoke
│  ├─ Resources/
│  │  └─ templates/
│  │     ├─ AGENTS.md
│  │     ├─ CLAUDE.md
│  │     ├─ .claude/settings.json
│  │     ├─ CLAUDE_PROMPT_GUIDE.md
│  │     ├─ GPT5.2_PROMPT_GUIDE.md
│  │     └─ schema/optimized_prompt.schema.json
└─ Tests/
   ├─ Unit/
   │  ├─ StreamLineBufferTests.swift
   │  ├─ CodexJSONLParserTests.swift
   │  ├─ ClaudeStreamJSONParserTests.swift
   │  └─ WorkspaceManagerTests.swift
   └─ Fixtures/
      ├─ codex_stream_sample.jsonl
      └─ claude_stream_sample.ndjson

Nota:
- Para open source, Resources/templates se versiona en el repo. En binarios distribuidos, van dentro del app bundle.

## 6. Módulos: responsabilidades e interfaces

### 6.1 Core (Domain)
- enum Tool { codex, claude }
- enum TargetModel { claude46, gpt52, gemini30 }
- struct RunRequest { tool, targetModel, inputPrompt }
- enum RunEvent { delta(String), completed(String), failed(Error), cancelled }

### 6.2 CLIDiscovery
- `resolve(tool) -> URL?`
Estrategia:
- ejecutar `/bin/zsh -lc "command -v codex"` / `"command -v claude"`
- fallback a rutas comunes (/opt/homebrew/bin, /usr/local/bin)

### 6.3 WorkspaceManager
- `createRunWorkspace(request) -> WorkspaceHandle`
WorkspaceHandle:
- path
- cleanup()

Escrituras:
- INPUT_PROMPT.txt (UTF-8)
- TARGET_MODEL.txt
- templates (AGENTS/CLAUDE + guides + schema)
Nota: el contenido de AGENTS.md y CLAUDE.md debe instruir al agente a:
- leer INPUT_PROMPT.txt y TARGET_MODEL.txt
- leer la guía correspondiente (Claude/GPT)
- producir SOLO JSON final con optimized_prompt

### 6.4 ProcessRunner
- `run(command: [String], cwd: URL, env: [String:String]) -> AsyncStream<ProcessOutput>`
ProcessOutput:
- stdout(Data)
- stderr(Data)
- exit(Int32)

Debe soportar:
- cancel()
- timeout
- no deadlocks (lectura continua de pipes)

### 6.5 Providers
#### CodexProvider
Construye comando (MVP) tipo:
- `codex exec --json --output-schema <schemaPath> --output-last-message <outPath> --ask-for-approval never --sandbox read-only --skip-git-repo-check -`
y env:
- CODEX_HOME = <workspace>/codex_home
CWD = workspace

Streaming:
- parse JSONL events (línea a línea) y emitir RunEvent.delta

Resultado final:
- leer <outPath>, parse JSON, extraer optimized_prompt

#### ClaudeProvider
Comando streaming:
- `claude -p "<small run prompt>" --output-format stream-json --verbose --include-partial-messages`
Env recomendado:
- CLAUDE_CODE_DISABLE_AUTO_MEMORY=1
- CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1
CWD = workspace

Streaming:
- parse NDJSON y extraer text deltas

Final:
- acumular texto completo y parsear JSON final
Fallback on failure:
- re-run con:
  `claude -p "<small run prompt>" --output-format json --json-schema '<schema>'`
y extraer `.structured_output.optimized_prompt`

### 6.6 Parsers
CodexJSONLParser:
- input: líneas JSON
- output: deltas relevantes (texto)
- tolerar líneas malformadas: contabilizar + seguir (hasta cierto umbral)

ClaudeStreamJSONParser:
- input: eventos NDJSON
- output: deltas donde:
  - type == stream_event
  - event.delta.type == text_delta
- tolerar eventos no-text

## 7. Seguridad y aislamiento
- Workspace en /tmp; cleanup post-run.
- Codex sandbox read-only; nunca usar danger-full-access.
- No pedir allowedTools en Claude (no necesitamos tool-use); si aparece, bloquear.
- No enviar ficheros del usuario: todo vive dentro del workspace efímero.

## 8. Testing strategy
Unit tests (sin CLIs):
- buffers y parsers con fixtures
- workspace content exactness
- output contract normalization

Integration tests (opcionales, gated por env var):
- si CODX/CLAUDE están instalados, ejecutar un “smoke run” con prompt muy corto.

## 9. Packaging / Release
- Direct download: GitHub Releases
- Code signing + notarization
- DMG o ZIP
- README con prerequisitos: tener `codex` o `claude` instalado y logueado.

## 10. Extensiones futuras (no MVP)
- Settings UI para paths manuales
- Guía Gemini dedicada
- Provider vía APIs (sin depender de CLIs)
- Historial/versionado