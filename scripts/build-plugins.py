#!/usr/bin/env python3

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path


def detect_spcomp(root: Path) -> Path:
    scripting_dir = root / ".deps" / "sourcemod-package" / "addons" / "sourcemod" / "scripting"
    candidates = [
        scripting_dir / "spcomp.exe",
        scripting_dir / "spcomp",
        scripting_dir / "spcomp64.exe",
        scripting_dir / "spcomp64",
    ]
    for candidate in candidates:
        if candidate.exists():
            if candidate.suffix in {"", ".exe"}:
                try:
                    candidate.chmod(candidate.stat().st_mode | 0o111)
                except OSError:
                    pass
            return candidate
    raise FileNotFoundError(f"SourcePawn compiler not found in {scripting_dir}")


def load_manifest(root: Path) -> dict:
    manifest_path = root / "plugin-package-map.json"
    return json.loads(manifest_path.read_text(encoding="utf-8"))


def run_spcomp(spcomp: Path, source_file: Path, include_dirs: list[Path], output_file: Path) -> None:
    cmd = [str(spcomp), str(source_file)]
    for include_dir in include_dirs:
        cmd.append(f"-i{include_dir}")
    cmd.append(f"-o{output_file}")
    print(f"Compiling {source_file.name} -> {output_file}", flush=True)
    result = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    if result.returncode != 0:
        raise RuntimeError(f"spcomp failed for {source_file.name}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Compile Custom-Fakelag SourcePawn plugins.")
    parser.add_argument("--root", default=".")
    parser.add_argument("--output-root", default=".build/plugins")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    output_root = (root / args.output_root).resolve()
    manifest = load_manifest(root)
    plugin_buckets = manifest.get("build", {}).get("plugins", {})
    spcomp = detect_spcomp(root)

    scripting_dir = root / "scripting"
    include_dir = scripting_dir / "include"
    source_mod_include_dir = spcomp.parent / "include"
    include_dirs = [include_dir, scripting_dir, source_mod_include_dir]

    artifact_plugins_root = output_root / "addons" / "sourcemod" / "plugins"
    if output_root.exists():
        shutil.rmtree(output_root)
    artifact_plugins_root.mkdir(parents=True, exist_ok=True)

    for bucket, plugins in plugin_buckets.items():
        bucket_root = artifact_plugins_root if bucket == "root" else artifact_plugins_root / bucket
        bucket_root.mkdir(parents=True, exist_ok=True)
        for plugin_stem in plugins:
            source_file = scripting_dir / f"{plugin_stem}.sp"
            if not source_file.exists():
                raise FileNotFoundError(f"Missing plugin source declared in manifest: {source_file}")
            output_file = bucket_root / f"{plugin_stem}.smx"
            run_spcomp(spcomp, source_file, include_dirs, output_file)

    print(f"Plugin build completed in: {output_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
