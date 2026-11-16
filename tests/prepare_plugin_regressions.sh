#!/usr/bin/env bash
# Run inside the isolated validation container. Valve content is read-only at
# /source; only this task's marked private gamedir under /work is written.
set -euo pipefail
TASK=/work/.build/plugin-regressions/game
if [[ -e "$TASK" && ! -f "$TASK/.custom-fakelag-isolated" ]]; then
  echo "Refusing an unmarked existing gamedir: $TASK" >&2
  exit 1
fi
mkdir -p "$TASK/addons/metamod" "$TASK/addons/sourcemod" "$TASK/cfg"
cp -a /source/serverfiles/left4dead2/addons/metamod/bin "$TASK/addons/metamod/"
cp /source/serverfiles/left4dead2/addons/metamod.vdf "$TASK/addons/"
printf '"Metamod Plugin" { "alias" "sourcemod" "file" "addons/sourcemod/bin/sourcemod_mm" }\n' > "$TASK/addons/metamod/sourcemod.vdf"
for d in bin extensions gamedata configs translations; do cp -a /work/.deps/smx/sourcemod-package/addons/sourcemod/$d "$TASK/addons/sourcemod/"; done
mkdir -p "$TASK/addons/sourcemod/plugins"
cp /work/.build/plugin-regressions/plugin_regressions.smx "$TASK/addons/sourcemod/plugins/"
cp /work/translations/player_fakelag.phrases.txt "$TASK/addons/sourcemod/translations/"
cat > "$TASK/gameinfo.txt" <<'EOF'
"GameInfo"
{
 game "Left 4 Dead 2"
 type multiplayer_only
 FileSystem
 {
  SteamAppId 550
  SearchPaths
  {
   Game |gameinfo_path|.
   Game /source/serverfiles/update
   Game /source/serverfiles/left4dead2_dlc3
   Game /source/serverfiles/left4dead2_dlc2
   Game /source/serverfiles/left4dead2_dlc1
   Game /source/serverfiles/left4dead2
   Game /source/serverfiles/hl2
  }
 }
}
EOF
printf 'sv_lan 1\nsv_cheats 1\nsb_all_bot_game 1\n' > "$TASK/cfg/server.cfg"
# No SDKTools/entity hooks or automatic updater are needed by this mock host.
rm -f "$TASK/addons/sourcemod/extensions/sdktools.autoload" "$TASK/addons/sourcemod/extensions/sdkhooks.autoload"
python3 - "$TASK/addons/sourcemod/configs/core.cfg" <<'PYTHON'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
p.write_text(re.sub(r'("DisableAutoUpdate"\s+)"no"', r'\1"yes"', p.read_text()))
PYTHON
touch "$TASK/.custom-fakelag-isolated"
