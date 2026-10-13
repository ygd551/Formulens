# Formulens · 公式镜

**English** | [简体中文](README.zh-CN.md)

**Fully offline** screenshot-to-LaTeX/Markdown.
Press a shortcut, select a formula, text or table on screen, and get LaTeX or Markdown ready to paste in seconds.

Recognition runs on your own machine with the [PaddleOCR-VL-1.6](https://www.modelscope.cn/models/PaddlePaddle/PaddleOCR-VL-1.6) model. Screenshots are never uploaded anywhere.

## Platform support

| Platform | Status | Inference backend |
|---|---|---|
| macOS (Apple Silicon) | ✅ Released v1.0.0 | [MLX](https://github.com/ml-explore/mlx), running on the Apple GPU |
| Windows | 🚧 Planned | TBD (NVIDIA GPU / CPU) |
| Linux | 🚧 Planned | TBD (NVIDIA GPU / CPU) |

See the [roadmap](#roadmap) for what's next.

## Features (macOS)

- **⌃⌘M** to snip a screen region; the result is copied to the clipboard automatically
- Detects the content type: a single formula → LaTeX; text with inline math → Markdown (`$...$`); tables → Markdown tables
- Result window with the original image, a rendered preview, editable LaTeX / Markdown source, and history
- Paste images with ⌘V, drag images in, or re-recognize with a specific mode
- English and Simplified Chinese UI: follows the system language by default; switch any time from the ∑ menu bar icon → "Language" or the 🌐 button in the window
- Speed (measured on M4): about 1–2 s per formula, about 2 s for a paragraph with inline math

## Requirements (macOS)

- Mac with Apple Silicon (M1 or later); Intel Macs are not supported
- macOS 14 or later
- About 3 GB of free disk space; about 2.1 GB of RAM while running (16 GB RAM recommended, 8 GB works)

## Install (macOS)

1. Download `Formulens-<version>.dmg` and its `.sha256` file from [Releases](../../releases)
2. **Verify the download** (recommended):
   ```bash
   shasum -a 256 -c Formulens-1.0.0.dmg.sha256
   ```
   It must print `OK`. Only download from this repository's Releases page.
3. Open the DMG and drag **Formulens** into Applications
4. First launch: the app is not notarized by Apple, so macOS will say it cannot verify the developer.
   Open System Settings → Privacy & Security and click **Open Anyway** at the bottom.
   If the app opens but keeps showing "Model failed to start", run this once in Terminal and reopen the app:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/Formulens.app"
   ```
5. On your first snip, grant permission: System Settings → Privacy & Security → **Screen & System Audio Recording** → turn on Formulens, then choose "Restart Formulens" from the ∑ menu

## Usage (macOS)

| Action | What it does |
|---|---|
| ⌃⌘M | Select a region and recognize it; Esc to cancel |
| ⌘V / drag an image | Recognize an image from the clipboard or a file, in the result window |
| ⇧⌘C | Copy the LaTeX / Markdown currently shown |
| ∑ in the menu bar | Recognition mode, copy format, language, launch at login, restart, quit |

The menu bar icon shows `∑·` while the model is loading and `∑…` while recognizing.

## Privacy & security

- **Fully offline**: screenshots are recognized on your machine. The inference service runs in offline mode and never downloads anything.
- **Screen recording permission**: the app calls the system tool `screencapture` only when you press the shortcut, and only captures the region you select. It never records in the background.
- **The local inference service is protected**:
  - The inference service (mlx-vlm) listens only on `127.0.0.1` and cannot be reached from the network
  - Every request must carry a random access key. The key is generated on first launch and stored in `~/Library/Application Support/Formulens/server.key`, readable only by your user
  - Web pages in your browser and other programs on your Mac don't have the key, so they cannot use the service
  - Before connecting, the app checks that the service on the port *requires this app's key*, so screenshots are never sent to some other program that happens to use the port
  - Python code shipped with the model is never executed (`trust_remote_code` is off)
  - When the app exits (including crashes and force quits), the inference service exits too and doesn't stay in memory
- **Result preview**: screenshot content can be arbitrary text, so the preview page cannot load any network resources or navigate anywhere, and KaTeX commands such as links are disabled (`trust: false`)
- **Image size limits**: images over 50 MB or 100 megapixels are rejected before decoding, so crafted images cannot exhaust memory
- **Data location**: history and logs are stored in `~/Library/Application Support/Formulens/`, accessible only by your user. Delete that folder to clear everything.
- **Verifiable builds**: the model, the Python runtime and every Python dependency are checked against SHA-256 hashes after download. Any replaced file makes the build fail.
- To report a security issue, please follow [SECURITY.md](SECURITY.md) (private report via the Security tab) instead of opening a public issue.

## Uninstall (macOS)

Quit the app → delete Formulens from Applications → delete `~/Library/Application Support/Formulens`.

---

## Roadmap

### ✅ Done

- [x] Native macOS app (Swift / SwiftUI): menu bar app, global shortcut snipping, result window, history
- [x] Recognition modes: auto / formula / text with inline math / table
- [x] LaTeX and Markdown output, with an offline KaTeX preview inside the app
- [x] Local inference: PaddleOCR-VL-1.6 on the Apple GPU via MLX
- [x] Hardened inference service: localhost only, random access key required
- [x] English / Simplified Chinese UI, switchable inside the app
- [x] Self-contained installer (DMG) bundling the Python runtime and the model, with no external dependencies
- [x] Reproducible builds: pinned dependencies; model and runtime verified with SHA-256 after download
- [x] Command-line recognizer

### 🚧 To do

**Cross-platform**

- [ ] Extract the recognition logic (prompts, auto-mode detection, table conversion, formatting) into a core shared by all platforms
- [ ] Windows version: screen capture and global shortcut, tray icon, installer
- [ ] Linux version: X11 / Wayland capture, tray icon, packaging
- [ ] Inference backend for Windows / Linux: evaluate NVIDIA GPU and CPU-only options (e.g. vLLM, Transformers, llama.cpp)
- [ ] Choose a cross-platform UI approach (e.g. Tauri, Qt, or native UI per platform)

**macOS**

- [ ] Customizable global shortcut
- [ ] Unload the model when idle to free memory
- [ ] Full-page document / PDF parsing (layout analysis, multi-column reading order)
- [ ] Apple Developer ID signing and notarization, so no manual "Open Anyway" step is needed
- [ ] In-app update check
- [ ] Verify compatibility on macOS 14 / 15 and 8 GB RAM machines

**Recognition & UX**

- [ ] Evaluate and improve handwritten formula recognition
- [ ] More output formats: MathML, Word equations, plain text
- [ ] More UI languages
- [ ] Search in history

Ideas and pull requests are welcome, especially for the Windows and Linux versions. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Build from source (macOS)

Requires the Xcode Command Line Tools (`xcode-select --install`); the full Xcode is not needed.

```bash
# 1. Download the model (about 1.9 GB from ModelScope; every file is verified with SHA-256)
./download_model.sh

# 2. Prepare the bundled Python runtime (about 650 MB; installed from macapp/runtime-requirements.lock with SHA-256 checks)
macapp/setup_runtime.sh

# 3. Build the installer macapp/dist/Formulens-<version>.dmg and its .sha256
macapp/package.sh
```

Optional: run `macapp/make_cert.sh` to create a local code-signing certificate in your keychain. When the app is signed with it, rebuilding does not require granting the screen recording permission again. Without it, the build uses ad-hoc signing.

### Project structure

```
macapp/Sources/                  App source (Swift / SwiftUI)
  main.swift                     Menu bar, global shortcut, screen capture, window
  AppModel.swift                 App state, recognition flow, history
  Recognizer.swift               Calls the inference service, formats output as LaTeX / Markdown; image size checks
  Services.swift                 Inference service startup, access key and port selection, history storage
  Views.swift                    Result window UI
  Localization.swift             UI language (follow system or choose manually)
macapp/Resources/                Preview page, KaTeX, UI translations (en.lproj / zh-Hans.lproj)
macapp/tools/check_l10n.sh       Checks that every UI string has a Chinese translation
macapp/build.sh                  Builds the app only
macapp/install.sh                Development install, using this repo's models/ and Python environment
macapp/package.sh                Builds the installer (checks translations and minimum macOS version, strips local paths, signs, creates DMG and SHA-256)
macapp/setup_runtime.sh          Prepares the bundled Python runtime
macapp/runtime-constraints.txt   Exact dependency versions
macapp/runtime-requirements.lock Dependency lock file: versions + SHA-256 (macOS 14 arm64)
download_model.sh                Downloads and verifies the model
checksums/                       SHA-256 manifests for the model and the Python runtime
cli/recognizer.py                Command-line recognizer
env.sh / start_server.sh         Inference service for the CLI and development builds
```

### Updating dependencies

1. Change the versions in `macapp/runtime-constraints.txt`
2. Regenerate the lock file (resolved for macOS 14 so older systems keep working; opencv-python is excluded):
   ```bash
   cd macapp
   runtime/python/bin/python3 -I -m pip install --dry-run --ignore-installed --report /tmp/r.json \
     --only-binary=:all: --platform macosx_14_0_arm64 --python-version 3.12 --implementation cp \
     --target /tmp/t -c runtime-constraints.txt mlx-vlm mlx mlx-metal transformers
   ```
   Update `runtime-requirements.lock` with each package's `version` and `download_info.archive_info.hashes.sha256` from `/tmp/r.json`
3. Run `./setup_runtime.sh`, test recognition, then run `./package.sh`

### Translations

UI strings are written in English in the code (`L("...")`); the Chinese translations live in `macapp/Resources/zh-Hans.lproj/Localizable.strings`.
After adding strings, run `macapp/tools/check_l10n.sh`. To add a language, create `<language-code>.lproj/Localizable.strings`
and add the language to `AppLanguage` in `Localization.swift` and to `CFBundleLocalizations` in `build.sh`.

### Command line

```bash
./start_server.sh &                         # start the inference service
source env.sh
$PY cli/recognizer.py image.png auto        # auto / formula / text / table
```

`env.sh` uses the Python in `macapp/runtime` by default; set `FORMULENS_PYTHON` to use another environment with mlx-vlm installed.
If the Formulens app is running, the CLI reads its access key automatically and reuses the same inference service.

### How recognition works

1. Preprocess the screenshot: upscale very small images, downscale very large ones
2. Auto mode first recognizes with the `OCR:` prompt. If the result contains nothing but math, it re-runs with `Formula Recognition:` for higher accuracy; if the output is a table structure (OTSL), it re-runs with `Table Recognition:`
3. Convert `\( \)` and `\[ \]` to Markdown `$ $` and `$$ $$`, and OTSL tables to Markdown tables

## Acknowledgements

- [PaddleOCR-VL](https://github.com/PaddlePaddle/PaddleOCR): document-parsing vision-language model by PaddlePaddle (Baidu)
- [MLX](https://github.com/ml-explore/mlx) and [mlx-vlm](https://github.com/Blaizzy/mlx-vlm): running the model on Apple Silicon
- [KaTeX](https://katex.org): formula rendering
- [python-build-standalone](https://github.com/astral-sh/python-build-standalone): a redistributable standalone Python

## License

The code in this project is released under the [MIT](LICENSE) license.
Third-party components bundled in the installer, such as the model and the Python runtime, are under their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This project is not affiliated with Mathpix, PaddlePaddle (Baidu) or Apple.
