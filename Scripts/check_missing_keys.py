#!/usr/bin/env python3
"""Verify that English and Khmer localization files contain identical keys."""

from pathlib import Path
import re
import sys


KEY_PATTERN = re.compile(r'^\s*"([^"]+)"\s*=', re.MULTILINE)
REPOSITORY_ROOT = Path(__file__).resolve().parent.parent


def parse_strings_file(file_path: Path) -> set[str]:
    return set(KEY_PATTERN.findall(file_path.read_text(encoding="utf-8")))


def main() -> int:
    en_path = REPOSITORY_ROOT / "QuaraMoney/en.lproj/Localizable.strings"
    km_path = REPOSITORY_ROOT / "QuaraMoney/km.lproj/Localizable.strings"

    en_keys = parse_strings_file(en_path)
    km_keys = parse_strings_file(km_path)
    missing_in_km = sorted(en_keys - km_keys)
    missing_in_en = sorted(km_keys - en_keys)

    print(f"English keys: {len(en_keys)}")
    print(f"Khmer keys:   {len(km_keys)}")
    print("Missing in KM:")
    for key in missing_in_km:
        print(key)

    print("\nMissing in EN:")
    for key in missing_in_en:
        print(key)

    if missing_in_km or missing_in_en:
        print("\nLocalization parity check failed.")
        return 1

    print("\nLocalization parity check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
