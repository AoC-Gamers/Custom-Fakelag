#!/usr/bin/env python3

import argparse
import os
import platform
import shutil
import tarfile
import urllib.error
import urllib.request
import zipfile
from pathlib import Path


def detect_platform() -> str:
    system = platform.system().lower()
    if system.startswith("win"):
        return "windows"
    if system == "linux":
        return "linux"
    raise RuntimeError(f"Unsupported platform for plugin deps: {platform.system()}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Download SourceMod package dependencies for SourcePawn plugin compilation.")
    parser.add_argument("--root", default=".", help="Repository root")
    parser.add_argument("--version", default="1.12", help="SourceMod version branch")
    parser.add_argument("--platform", choices=("windows", "linux"), help="Override detected platform")
    parser.add_argument("--deps-dir", help="Override dependency root")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    deps_dir = Path(args.deps_dir).resolve() if args.deps_dir else Path(os.environ.get("DEPS_DIR", root / ".deps")).resolve()
    package_dir = deps_dir / "sourcemod-package"
    package_platform = args.platform or detect_platform()
    archive_suffix = "zip" if package_platform == "windows" else "tar.gz"
    archive_path = deps_dir / f"sourcemod-package-{package_platform}.{archive_suffix}"
    url = f"https://www.sourcemod.net/latest.php?os={package_platform}&version={args.version}"

    if package_dir.exists():
        shutil.rmtree(package_dir)
    deps_dir.mkdir(parents=True, exist_ok=True)

    print(f"Downloading SourceMod package for {package_platform} from: {url}")
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0",
            "Accept": "*/*",
        },
    )
    try:
        with urllib.request.urlopen(request) as response, archive_path.open("wb") as fh:
            shutil.copyfileobj(response, fh)
    except urllib.error.HTTPError as exc:
        raise RuntimeError(f"Failed to download SourceMod package: HTTP {exc.code}") from exc

    if package_platform == "windows":
        with zipfile.ZipFile(archive_path, "r") as zf:
            zf.extractall(package_dir)
    else:
        package_dir.mkdir(parents=True, exist_ok=True)
        with tarfile.open(archive_path, "r:gz") as tf:
            tf.extractall(package_dir)

    print(f"Plugin dependencies ready in: {package_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
