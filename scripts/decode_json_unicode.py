"""Rewrite a JSON file with readable UTF-8 text instead of \\uXXXX escapes."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


DEFAULT_TARGET = Path("app/assets/default_ledger_template.json")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Decode JSON unicode escapes and write UTF-8 JSON.",
    )
    parser.add_argument(
        "input",
        nargs="?",
        default=str(DEFAULT_TARGET),
        help=f"JSON file to rewrite, defaults to {DEFAULT_TARGET}",
    )
    parser.add_argument(
        "-o",
        "--output",
        help="Optional output path. If omitted, the input file is rewritten.",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output) if args.output else input_path

    data = json.loads(input_path.read_text(encoding="utf-8"))
    output_path.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
