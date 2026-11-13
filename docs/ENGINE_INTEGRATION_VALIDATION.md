# Integración del motor y resultados de operación

> Informe histórico de Linux. El trabajo Windows posterior y sus pendientes
> están en [WINDOWS_ENGINE_VALIDATION.md](WINDOWS_ENGINE_VALIDATION.md).

Fecha: 2026-11-13. Revisión de partida: `2ce01ff`.
Código de esta integración: `8bad69f26b4dc96901ef99e1654094c742e562d9`.

## Resultado y alcance

Implementado el adaptador para el `engine_srv.so` Linux x86 identificado en el
[manifiesto](runtime/linux-engine-2.2.4.3.json). Captura payload y metadatos sin
leer el lector no preparado; obtiene capacidad de la asignación verificada;
restaura sobre el buffer prestado y deja que el caller reconstruya el lector.
La comprobación de build ID/direcciones/layout ocurre antes de activar el hook.
Windows y motores con otra identidad conservan el rechazo de activación.

`ProfileChangeResult` separa `Applied`, `Unchanged`, `Vetoed` y `Error`.
El bridge también separa veto y fallo al ejecutar el forward. `Plugin_Handled`
y `Plugin_Stop` no cambian perfiles ni notifican éxito; las natives devuelven
normalmente ante un veto. Valores inválidos, reentrada, fallos de ejecución,
resolución o detour siguen siendo errores. Las declaraciones públicas SourcePawn
se conservan.

`ApplyPatch`, `DisableDetour`, `DeleteDetour`, `Destroy`, desactivación y shutdown
propagan resultado. Si falla la protección no se escriben bytes, no cambia el
estado adjunto y no se liberan trampolín, callback, política ni colas. Los cambios
de modo recuperan su valor anterior si falla sincronizar el hook; reset y clear
propagan ese error a las natives. Un retry exitoso permite completar la retirada.
La instalación también usa la escritura comprobada y evita stores desalineados.

**Límite de descarga forzada:** SourceMod tiene un callback de unload `void` y
continúa con la descarga de la biblioteca al retornar. No permite vetar desde
ese callback. Si una descarga real no logra restaurar el código, la extensión
registra error fatal y aborta el proceso antes de permitir un `dlclose` que deje
un callback vivo apuntando a código descargado. La desactivación ordinaria falla
sin liberar infraestructura y permite retry; el fail-stop es exclusivo de la
ruta de descarga irrecuperable. Esta condición se prueba mediante fallos
inyectados en lógica aislada, sin provocar un fallo de memoria deliberado en SRCDS.

## Compilación y pruebas aisladas

- GCC 13.3, Ubuntu 24.04 en contenedor, extensión ELF32 i386: compilación aprobada
  con `--no-undefined`, sin warnings en las fuentes cambiadas.
- Suite con ASan/UBSan y `-Wall -Wextra -Werror`: x86 y x64 aprobados.
- Regresiones nuevas: cuatro resultados del servicio, veto Handled/Stop sobre
  perfiles nuevos/existentes, error de ejecución del forward, protección fallida
  sin escritura ni cambio de saved bytes, retiro/destrucción fallidos sin liberar,
  retry/idempotencia, error de reset propagado y codec con lector envenenado.
- Se conservan las regresiones de memoria, sesiones, límites, GE y reentrada.

Comandos utilizados (desde el repositorio):

```bash
SANITIZE=1 make test-exts-linux
python3 tests/verify_linux_engine.py tmp/engine-evidence/engine_srv.so

docker run --rm -v "$PWD:/work" -w /work --user "$(id -u):$(id -g)" \
  custom-fakelag-validation:local bash -c '
    TEST_ARCH=32 SANITIZE=1 make test-exts-linux &&
    VENV_DIR=/work/.deps/exts-linux/.venv-container make build-exts-linux'
```

El Dockerfile del toolchain permanece en `tests/Dockerfile.linux-validation`.
Revisiones SDK/SM usadas: HL2SDK `2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6`,
SourceMod `3f7460671f7adc4a3c6791a47d21ba3e7b5fba91`.

## CI comprobado

La [ejecución 43428629240](https://github.com/AoC-Gamers/Custom-Fakelag/actions/runs/43428629240)
del commit `2ce01ff9010a93314cbe734154d2dbd40f25ee03` terminó en success:
regresiones y build Linux, regresiones y build Windows, SourcePawn, ambos
paquetes y publicación. Sustituye al estado "Windows no compilado" de la entrega
inicial. Es evidencia de compilación/prueba aislada de esa revisión, no del ABI
Windows ni de SRCDS. También terminó en **success** el [CI 43437536878](https://github.com/AoC-Gamers/Custom-Fakelag/actions/runs/43437536878)
del código de integración `8bad69f26b4dc96901ef99e1654094c742e562d9`:
regresiones y builds Linux/Windows, SourcePawn, ambos paquetes y publicación.
La compilación Windows actual queda comprobada, aunque su ABI de motor permanezca
pendiente.

## SRCDS Linux real

Instancia temporal con Ubuntu 26.04.1, SRCDS `2.2.4.3` build 10097 y SourceMod
`1.12.0.7259`. Se reutilizó el volumen Vanilla **solo lectura**, con un árbol
separado de unos 71 MiB para addons/configuración/logs. Los VPK y mapas se
referenciaron mediante enlaces; no se copió una instalación completa ni se
modificaron los servidores originales. Sin puertos publicados en el host; tráfico
UDP de loopback dentro de la instancia. No se usaron cuentas Steam de jugadores.

El build de prueba incluye `tests/engine_runtime_harness.cpp` solo con
`CUSTOM_FAKELAG_ENGINE_HARNESS=1`. Los comandos `cf_probe_*` y el acceso de
observación no se compilan en el build normal; se comprobó su ausencia con `nm`.
El arnés inyecta una identidad/resolver de perfil para la dirección UDP de prueba,
pero los datagramas pasan por `NET_ReceiveDatagram`, el detour real, la cola y la
restauración del motor. No emula la autenticación ni la elegibilidad de un jugador.

Se ejecutaron 17 comprobaciones: [resultados completos](runtime/linux-probe-2026-11-13.json).

| Comprobación | Resultado observado |
|---|---|
| Perfil 120 ms, 6 datagramas | 6 despachados; media retenida 136.351 ms; cero errores de captura/restauración |
| Bernoulli 100 % | 6 descartados por pérdida, cero despachados |
| GE 100 % | 6 descartados, un estado de pérdida; sin división inválida |
| Cambio directo de ConVar de modelo | Hook desactivado, cola/bytes/estados de pérdida en cero |
| Reset con pendientes | 4 paquetes / 92 bytes antes; cero después; 4 descartes de ciclo de vida |
| Invalidación de sesión | 3 pendientes eliminados; misma dirección reaplicada despacha solo los 3 nuevos |
| Lazy → always-on → lazy | Pendientes eliminados; estados de activación 1 y 0 coherentes |
| Cambio `c1m1_hotel` → `c1m2_streets` | 2 pendientes eliminados, hook desactivado y bytes/estado GE en cero |
| Descarga con cola pendiente y recarga | Retirada real, extensión descargada, estado limpio al recargar; 3 nuevos datagramas despachados |

La media se calcula con `net_time` al despachar menos la recepción original;
no es RTT de un cliente. Las respuestas A2S no se usaron como criterio porque
los sondeos iniciales no respondieron en este entorno. La evidencia certifica
entrada UDP, retención/descarte y despacho dentro del motor, no gameplay ni la
conexión/desconexión de un jugador Steam.

Reproducción con un servidor aislado ya preparado (no usar en producción):

```bash
# Compilar en el contenedor de toolchain, con salida separada:
CUSTOM_FAKELAG_ENGINE_HARNESS=1 BUILD_DIR="$PWD/.build/linux-harness" \
  make build-exts-linux
# Montar el motor identificado y mapas existentes en modo lectura,
# preparar un gamedir privado con Metamod/SourceMod y cargar custom_fakelag.
python3 tests/run_engine_probe.py \
  --container custom-fakelag-runtime-probe \
  --log tmp/srcds-runtime/serverfiles/left4dead2/addons/sourcemod/logs/L20261113.log \
  --output tmp/validation/linux-engine-runtime-final.json --change-map
```

El script requiere un container dedicado a pruebas y controla su stdin. La
extensión debe ser el ID indicado por `--extension-id` (2 en esta instancia).
No crea servidores, no instala juegos ni descarga depots.

El JSON de evidencia contiene los SHA-256 del build normal y del arnés usados.
Los logs complementarios se conservaron localmente en `tmp/validation/`.

## Matriz y pendientes

| Nivel | Linux x86 identificado | Windows x86 |
|---|---|---|
| Compilación/pruebas aisladas | Local ASan/UBSan y CI 8bad69f aprobados | CI 8bad69f aprobado; sin MSVC local |
| Binario objetivo y ABI | Identificados, comprobados en carga y tráfico UDP | No disponible; falta `engine.dll` |
| Adaptador activable | Sí, solo build ID permitido | No, rechazo controlado |
| Carga/descarga/mapa/UDP en SRCDS | 17 checks aprobados con arnés | No ejecutado |
| Jugadores Steam, latencia/pérdida bajo gameplay y reconexión real | Pendiente | Pendiente |

No se descargó el servidor Windows completo: el usuario indicó falta de binarios
y espacio. Se eliminó la copia temporal de SteamCMD (212 MiB). Queda pendiente
obtener `engine.dll` con identidad verificable para implementar su contrato,
validar patrones y realizar SRCDS Windows. Linux todavía requiere aceptación con
jugadores reales antes de dar por completada la validación de producción.
