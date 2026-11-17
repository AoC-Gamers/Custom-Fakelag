set -euo pipefail
root="$PWD"
deps="$root/.deps/exts-linux"
python="$deps/.venv-linux/bin/python"
mkdir -p .build/steam-debug/test-data
g++ -m32 -std=c++14 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer diagnostics/steam_lifecycle_debug/tests.cpp -o .build/steam-debug/tests
.build/steam-debug/tests .build/steam-debug/test-data
cd .build/steam-debug
"$python" "$root/configure.py" --sdks l4d2 --hl2sdk-root "$deps" --mms-path "$deps/mmsource-1.12" --sm-path "$deps/sourcemod-1.12" --enable-optimize --steam-lifecycle-debug
"$python" -c 'import sys; from ambuild2.run import cli_run; sys.exit(cli_run())'
