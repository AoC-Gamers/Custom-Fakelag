set -euo pipefail
make test-python
compiler=.deps/smx/sourcemod-package/addons/sourcemod/scripting/spcomp
includes=.deps/smx/sourcemod-package/addons/sourcemod/scripting/include
mkdir -p .build/shutdown-consumers
for consumer in windows_shutdown_consumer windows_shutdown_fill_consumer plugin_regressions balance_report_consumer; do
  "$compiler" "tests/integration/$consumer.sp" -iaddons/sourcemod/scripting/include -iscripts/deps/includes -i"$includes" -o".build/shutdown-consumers/$consumer.smx"
done
