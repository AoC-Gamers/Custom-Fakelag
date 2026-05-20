#!/usr/bin/env python3

import shutil
import sys
from pathlib import Path


def copy_if_exists(source: Path, destination: Path) -> None:
    if not source.exists():
        return
    if source.is_dir():
        shutil.copytree(source, destination, dirs_exist_ok=True)
    else:
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("Usage: stage-artifact.py <root_dir> <smx_package_dir> <exts_package_dir>")

    root_dir = Path(sys.argv[1]).resolve()
    smx_package_dir = Path(sys.argv[2]).resolve()
    exts_package_dir = Path(sys.argv[3]).resolve()
    artifact_dir = root_dir / "dist" / "sourcemod" / "artifact"

    if artifact_dir.exists():
        shutil.rmtree(artifact_dir)
    artifact_dir.mkdir(parents=True, exist_ok=True)

    copy_if_exists(exts_package_dir / "addons", artifact_dir / "addons")
    copy_if_exists(smx_package_dir / "addons", artifact_dir / "addons")
    copy_if_exists(root_dir / "README.md", artifact_dir / "README.md")
    copy_if_exists(root_dir / "plugin-package-map.json", artifact_dir / "plugin-package-map.json")
    copy_if_exists(root_dir / "docs", artifact_dir / "docs")

    print(f"SourceMod artifacts generated in {artifact_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
