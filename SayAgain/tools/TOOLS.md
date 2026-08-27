# SayAgain — offline model conversion tools

Scripts here run **off-device, once per model pair** to produce CoreML artifacts
that get bundled with the app. Nothing here runs at app runtime.

## OPUS-MT translation (slice 3)

Converts a Helsinki-NLP OPUS-MT pair-specific translation model to CoreML.

### Setup (one time)

Requires Python 3.11+ on macOS (Apple Silicon or Intel).

**Important:** create the venv at the **repo root**, not inside `SayAgain/tools/`.
Xcode auto-syncs everything under `SayAgain/SayAgain/` into the app target, so a
venv there would bloat the build and cause `Multiple commands produce …` errors.

```bash
cd /path/to/SayAgain               # repo root
python3.11 -m venv .venv-opus       # or python3.13 — anything ≥ 3.11
source .venv-opus/bin/activate
pip install --upgrade pip
pip install "optimum[coreml]" transformers sentencepiece torch
```

### Convert a pair

```bash
# From repo root, with venv activated:
python SayAgain/tools/convert_opus_to_coreml.py --pair en-ro --out SayAgain/tools/models/
```

Produces `models/opus-en-ro/` with:

- `encoder.mlpackage` — CoreML encoder graph
- `decoder.mlpackage` — first-step decoder
- `decoder_with_past.mlpackage` — subsequent-step decoder (uses key-value cache)
- `tokenizer/` — SentencePiece + vocab + special-tokens config

Total size: ~300 MB per pair.

### Bundle into the Xcode project

1. In Finder, locate the produced `models/opus-en-ro/` directory.
2. In Xcode, right-click **SayAgain/Resources/** → **Add Files to "SayAgain"…**
3. Select the `opus-en-ro/` directory. **Important:** in the dialog, choose
   *"Create folder references"* (blue folder), not *"Create groups"* (yellow).
   That preserves the sub-directory structure inside the app bundle.
4. Ensure **Target: SayAgain** is checked.

The Swift runtime finds it via
`Bundle.main.url(forResource: "opus-en-ro", withExtension: nil)`.

### Available pairs

- `en-ro`, `ro-en`
- `en-hu`, `hu-en`
- `en-th`, `th-en` (may not exist on HF; use `en-mul`/`mul-en` as fallback)
- `en-mul`, `mul-en` — multilingual fallbacks

### Ship-size guidance

Each pair adds ~300 MB. To keep the app manageable:

- Ship only the pairs users are likely to want (start with `ro-en`, `hu-en`, `th-en`
  — one-way to English gives us useful coverage via chaining).
- Optionally move the `.mlpackage`s into an **on-demand resources** tag so they
  download the first time a user selects a non-native language (future work).
