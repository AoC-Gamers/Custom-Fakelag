#!/usr/bin/env python3

import argparse
import shutil
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Copy a prepared package tree to a target directory.")
    parser.add_argument("--source", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    source = Path(args.source).resolve()
    output = Path(args.output).resolve()

    if not source.exists():
        raise FileNotFoundError(f"Source tree not found: {source}")

    if output.exists():
        shutil.rmtree(output)

    shutil.copytree(source, output)
    print(f"Package tree copied to: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
