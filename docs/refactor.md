# Model service, source editing and history management

This guide covers model loading/unloading, local compatible model registration, source editing and confirmed history deletion.

## Usage

- The sidebar and ∑ menu provide **Load Model**, **Unload Model** and **Cancel Loading**. Startup still loads the selected model automatically. Unloading stops and reaps only this app's inference process; model files remain on disk. Recognition must finish before unloading/switching. Loading is ready only after a successful model inference warmup. A failed load leaves a persistent error in the sidebar.
- Edit LaTeX or Markdown anywhere in the source field. Native editing preserves selection and input-method composition. The preview follows the active source format after 150 ms of inactivity. Formula LaTeX edits update the Markdown formula too. Raw model output is read only. If a save fails, the draft remains in memory and a **Retry Save** control appears; retry before closing the app.
- **Manage Models… → Add Local Model…** registers a local, complete MLX-VLM-compatible directory (config, tokenizer config, processor config and safetensors weights). Choose **PaddleOCR compatible** for `paddleocr_vl`, or **General vision-language model** for other image-to-text models supported by the installed mlx-vlm. Registration checks local assets; actual architecture/weight/processor compatibility is verified during loading. A directory that merely passes structural checks is not guaranteed to work. No downloads or custom Python execution are enabled. The existing model is unloaded on selection change; explicitly load the new selection. **Remove from List** deletes only the registration, preserving user model files. Removing a selected registration resets selection to the bundled model.
- Check history rows individually, or use **Select All**, then **Delete Selected**. The confirmation states the count and includes saved images. Single-record deletion uses the same confirmation. Cancelling changes nothing. Deletion uses the captured IDs, validates filenames and directory boundaries, removes PNG/JSON pairs and clears cached thumbnails. A failed record remains visible and is reported; other selected records can still succeed. If PNG removal succeeds but a later JSON removal fails, the JSON index is restored; the saved image may already be gone. No claim of a cross-file atomic transaction is made.
- Another app/CLI's authenticated server is skipped instead of adopted, so unloading cannot kill a process this instance does not own. Running two app instances can consume memory twice; quit the original app before using the development build.

## Verification

No tests existed upstream. `macapp/tools/test.sh` compiles the actual app sources (excluding the app entry point) into a native behavioral test executable. It uses temporary histories, synthetic fixtures, fixture-only authentication and isolated model catalogs. It does not load, edit or delete real user history.

```sh
macapp/tools/test.sh                         # 21 default regression cases
macapp/tools/check_l10n.sh                    # all 105 UI strings translated
macapp/build.sh
codesign --verify --deep --strict macapp/build/Formulens.app
```

On a machine whose Command Line Tools lack SwiftUI macro support, select the full Xcode toolchain for each command:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer macapp/tools/test.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer macapp/build.sh
```

Optional real-model integration (uses the specified local runtime/model, no downloading):

```sh
FORMULENS_TEST_PYTHON=/absolute/path/to/python3 \
FORMULENS_TEST_MODEL=/absolute/path/to/local/model \
macapp/tools/test.sh
```

This adds a real MLX load, sample recognition, process RSS measurement, unload/reap check and reload. The test validates process removal, not an exact global system-memory counter. Metal allocations belong to the terminated process; system memory accounting may update asynchronously.

Optional synthetic-window snapshot:

```sh
FORMULENS_TEST_SNAPSHOT=/absolute/path/to/preview.png macapp/tools/test.sh
```

## Coverage limits

Real inference was checked with the bundled PaddleOCR-VL-1.6 and MLX-VLM 0.7.6 on this Apple Silicon host. Other model families were checked through validation/prompt/request fixtures, not by downloading and evaluating another checkpoint. General-model OCR quality and auto-mode classification depend on the chosen model. macOS 14/15 and other hardware have not been tested here. Hotkey/Screen Recording permission, live paste/drag and real clipboard interaction still need user acceptance; tests avoid changing those permissions or clipboard contents. No notarization or standalone DMG was produced.

Code remains MIT, with `THIRD_PARTY_NOTICES.md` and existing dependency/model/runtime checksum files retained. There are no new package dependencies or changes to the existing key-storage format.

## Development startup follow-up

The first development build failed validation when the bundled-model path was a symbolic link: Foundation directory enumeration returned ENOTDIR. Validation now resolves that directory before enumerating assets. A regression covers this exact path. Real inference was rerun through the actual development start_server.sh and watchdog using the symlink model path (22 tests passed including the 21 standard cases), rather than only direct Python startup. For this route set FORMULENS_TEST_PROJECT_DIR to the checkout root alongside the two real-model environment variables.
