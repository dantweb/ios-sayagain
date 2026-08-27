#!/usr/bin/env python3
"""One-time offline conversion of a Helsinki-NLP OPUS-MT translation model to CoreML.

Produces the encoder + decoder .mlpackages and tokenizer files that the app's
`OpusMTTranslator` loads at runtime for fully-offline translation.

Usage
-----

    # Set up (one time)
    python3.11 -m venv .venv-opus
    source .venv-opus/bin/activate
    pip install "optimum[coreml]" transformers sentencepiece torch

    # Convert one pair — repeat per pair you want to ship
    python tools/convert_opus_to_coreml.py --pair en-ro --out models/

    # Result: models/opus-en-ro/{encoder.mlpackage, decoder.mlpackage, decoder_with_past.mlpackage, tokenizer/}

Then in Xcode: drag `models/opus-en-ro/` into SayAgain/Resources/Models/ as a
**folder reference** (blue folder) so the sub-structure is preserved in the app
bundle. The Swift runtime looks under `Bundle.main.url(forResource: "opus-en-ro", ...)`.

Notes
-----
- Each pair is ~300 MB uncompressed. Ship only the pairs you actually need.
- `en-th` / `th-en` may not exist on the HuggingFace hub under Helsinki-NLP.
  In that case, use `en-mul` / `mul-en` as a fallback (worse quality, one model
  covers many source/target languages).
- Conversion needs a Mac (coremltools is macOS-only).
- Conversion RAM: ~4 GB per pair. Close other apps if it OOMs.
"""

import argparse
import subprocess
import sys
from pathlib import Path

# Curated pairs — extend as needed. Each is a HuggingFace model ID.
PAIRS = {
    "en-ro": "Helsinki-NLP/opus-mt-en-ro",
    "ro-en": "Helsinki-NLP/opus-mt-ro-en",
    "en-hu": "Helsinki-NLP/opus-mt-en-hu",
    "hu-en": "Helsinki-NLP/opus-mt-hu-en",
    "en-th": "Helsinki-NLP/opus-mt-en-th",
    "th-en": "Helsinki-NLP/opus-mt-th-en",
    # Multilingual fallbacks — one model covers many languages, lower quality.
    "en-mul": "Helsinki-NLP/opus-mt-en-mul",
    "mul-en": "Helsinki-NLP/opus-mt-mul-en",
}


def convert(pair: str, out_root: Path) -> None:
    model_id = PAIRS[pair]
    out_dir = out_root / f"opus-{pair}"
    out_dir.mkdir(parents=True, exist_ok=True)

    # Export encoder + decoder + with-past variant via optimum's CoreML exporter.
    cmd = [
        sys.executable, "-m", "optimum.exporters.coreml",
        f"--model={model_id}",
        "--task=text2text-generation-with-past",
        str(out_dir),
    ]
    print(f"→ {' '.join(cmd)}")
    subprocess.check_call(cmd)

    # Save the tokenizer next to the models so the Swift runtime can load it.
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(model_id)
    tok_dir = out_dir / "tokenizer"
    tok.save_pretrained(tok_dir)
    print(f"✓ Wrote {out_dir}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--pair", required=True, choices=sorted(PAIRS.keys()),
                    help="Language pair to convert (e.g. en-ro)")
    ap.add_argument("--out", type=Path, default=Path("models"),
                    help="Output root directory (default: ./models/)")
    args = ap.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    convert(args.pair, args.out)


if __name__ == "__main__":
    main()
