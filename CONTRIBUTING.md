# Contributing to AI Offline

Thanks for helping! Bug reports, translations, docs and code are all welcome.

## Run it from source

```bat
git clone https://github.com/Mr-sdn/ai-offline.git
cd ai-offline
"AI Offline.bat"
```

The repository is the app: there is no build step. The first run downloads the engine and a model into `runtime\` and `models\` (both git-ignored).

Useful environment variables while developing:

| Variable | What it does |
|---|---|
| `AIO_NO_BROWSER=1` | Start the server without opening a window |
| `AIO_MODELS=D:\path\to\models` | Use an existing Ollama models folder |
| `AIO_OLLAMA_EXE=...\ollama.exe` | Use an existing Ollama |
| `AIO_OPENCODE_EXE=...\opencode.exe` | Use an existing OpenCode |

## Where things are

| Path | What |
|---|---|
| `AI Offline.bat` | The launcher users double-click |
| `app\server.ps1` | Local server: serves the UI, stores chats, runs setup, starts/stops the engine |
| `app\setup.ps1` | First-time setup: downloads with resume, checksum checks, model download |
| `app\common.ps1` | Shared paths, hardware detection, shortcuts, the coding-agent config |
| `app\config.json` | Pinned versions, download checksums, ports and the model list |
| `app\ui\` | The interface: `index.html`, `app.css`, `app.js`, `i18n.js` |
| `More\` | Extra actions for users: stop, coding agent in a folder, right-click menu, uninstall |

Rules of thumb:
- PowerShell scripts must run on **Windows PowerShell 5.1** (no `??`, no ternary) and stay ASCII-only (5.1 reads files without a BOM as ANSI). Put non-English text in JSON files.
- `.bat` files use CRLF line endings.
- The UI must work with no internet: no CDNs, no remote fonts.

## Add an interface language

1. Open `app/ui/i18n.js` and copy the `en` block under a new key (for example `de`).
2. Translate the values. Keep the `{placeholders}`.
3. Add the language to the language switcher in `app/ui/app.js` (`langToggle` and the settings window). Right-to-left languages also need the `dir` handling in `applyLang`.

## Update the engine or the coding agent

Change the version, URL and `sha256` in `app/config.json`. Get the checksums from the release's `sha256sum.txt` (Ollama) or by hashing the downloaded ZIP. Test a clean setup before opening a pull request.

## Pull requests

- Keep changes focused and describe how you tested them (Windows version, RAM, GPU).
- Screenshots help for UI changes.
