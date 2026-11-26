import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCENES = ("01-home", "02-log", "03-period", "04-health", "05-day")
SHOT = re.compile(r"^(store-(?:en|zh-Hans|zh-Hant)-\d{2}-[a-z]+|paid-01-paywall)(?=$|[. _-])")
PNG_HEADER = b"\x89PNG\r\n\x1a\n"


def named_shots(folder):
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    found = {}
    for case in manifest:
        for attachment in case["attachments"]:
            match = SHOT.match(attachment.get("suggestedHumanReadableName") or "")
            if not match:
                continue
            name = match[1]
            source = folder / attachment["exportedFileName"]
            if source.resolve().parent != folder.resolve():
                raise ValueError(f"Unsafe screenshot path: {source}")
            with source.open("rb") as handle:
                if handle.read(8) != PNG_HEADER:
                    raise ValueError(f"Expected PNG: {name}")
            if name in found:
                raise ValueError(f"Duplicate screenshot: {name}")
            found[name] = source
    return found


def export(folder, output, listing=None):
    expected = {f"store-{lang}-{scene}" for lang in ("en", "zh-Hans", "zh-Hant") for scene in SCENES}
    expected.add("paid-01-paywall")
    found = named_shots(folder)
    if not found:
        raise ValueError("No named screenshots in xcresult attachments")
    if listing is not None and listing.is_file() and set(found) != expected:
        raise ValueError(f"Unexpected screenshot inventory: missing={sorted(expected - found.keys())}; extra={sorted(found.keys() - expected)}")
    output.mkdir(parents=True, exist_ok=True)
    for name, source in found.items():
        shutil.copy2(source, output / f"{name}.png")
    if listing is not None and listing.is_file():
        paywall = listing.parent / "截图/zh-Hans/paywall.png"
        paywall.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(found["paid-01-paywall"], paywall)
    print(f"Exported {len(found)} screenshots to {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("result", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--attachments", action="store_true")
    args = parser.parse_args()
    if args.attachments:
        export(args.result, args.output, ROOT / "上架资料/listing.json")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=args.output.parent) as folder:
            subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(args.result),
                            "--output-path", folder], check=True)
            export(Path(folder), args.output, ROOT / "上架资料/listing.json")
