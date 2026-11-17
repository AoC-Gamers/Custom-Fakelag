#!/usr/bin/env bash
# Explicit host-tool preparation; no system package installation or server changes.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
folder="$root/.deps/sonar-tools"
mkdir -p "$folder/debs" "$folder/root"
cd "$folder/debs"
apt-get download cppcheck libtinyxml2-10
for package in ./*.deb; do dpkg-deb -x "$package" "$folder/root"; done
ln -sfn ../lib/x86_64-linux-gnu/cppcheck/cfg "$folder/root/usr/bin/cfg"
mkdir -p "$folder/bin"
cat > "$folder/bin/cppcheck" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail
base="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export LD_LIBRARY_PATH="$base/root/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$base/root/usr/bin/cppcheck" "$@"
WRAPPER
chmod 0755 "$folder/bin/cppcheck"
printf 'SONAR_CPPCHECK=%s\n' "$folder/bin/cppcheck"
