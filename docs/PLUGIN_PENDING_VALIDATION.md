# Pendientes del plugin: entrega local del 16-11-2026

Base: `dcf8d8e2387a7e6547730199c760135dfacd2bba` (`origin/develop`).
Código corregido: `d08d0e4`. Rama local: `codex/fakelag-plugin-pending`.
Sin push, release ni despliegue. La evidencia del arnés registra además el SHA
exacto ejecutado; los cambios posteriores de documentación no cambian el plugin.

## Actualización posterior al push

El bloque anterior y las pruebas descritas más abajo conservan el estado de la
entrega local original. Después se integró `77f1200` en `develop` y pasó el
[workflow 43904516633](https://github.com/AoC-Gamers/Custom-Fakelag/actions/runs/43904516633)
(Linux, Windows, SourcePawn y canal develop), consultado de nuevo el 16-11-2026.
No equivale a aceptación con clientes.

La revisión posterior detectó el remanente FL-02 de las tablas. Su
[corrección y evidencia nuevas](BALANCE_REPORT_VALIDATION.md) están en una rama
local: CI remoto nuevo y pruebas con clientes reales siguen pendientes.
El runner de la receta inferior incorpora ahora las comprobaciones de tablas.

## Correcciones

- **FL-01:** timer por mapa. SourceMod entrega `OnMapStart` también en carga
  tardía (`core/logic/PluginSys.cpp`). `OnMapEnd` retira el timer antes de
  `RemoveMapChangeTimers` (`core/sourcemod.cpp`); los cambios de settings
  reinician las muestras. La descarga deja al runtime liberar sus handles.
- **FL-02:** consultas anterior/posterior, userid y generación delimitan cada
  operación. Solo cambios efectivos generan avisos y contadores. Un estado
  idéntico no permite distinguir veto de estado satisfecho: no se inventa el
  motivo. Una limpieza modificada a un perfil activo cuenta como ajuste y
  conserva persistencia; los mensajes manuales usan los valores efectivos.
  Los errores nativos siguen abortando, sin confirmación posterior.
- **FL-03:** `lag > 0 || loss > 0` incluye pérdida sin latencia en restauración
  por cuenta/equipo y snapshots. El marcador de desconexión se consulta antes
  y solo se consume tras aplicación confirmada. El cambio externo de modo
  mantiene el contrato de reset, sin restauración universal.
- **FL-04:** clear-all descarta primero los tres mapas y el trabajo diferido,
  incluso con cero activos. Generaciones invalidan callbacks antiguos, incluso
  si el userid coincide con una intención nueva. El voto propio se invalida
  antes de cancelarlo; un voto ajeno no se cancela. La guarda cubre los forwards
  y se libera también ante excepción mediante `Call_Finish`; el error se
  propaga. No quedan marcas de olvido individuales previas a una native.

Los cuatro defectos eran heredados y se confirmaron en la base. El veto nativo,
la propiedad de paquetes, el adaptador ABI, los límites y la política LAN ya
estaban corregidos y se conservaron. No hay cambios de C++ ni de API pública.
La política LAN no corrige el fallo histórico de cierre Steam.

## Evidencia y límites

[Registro del arnés](runtime/plugin-regressions-2026-11-16.json).

| Casos del encargo | Ejecución local | Pendiente de aceptación |
|---|---|---|
| T01–T05 | Timers reales de SourceMod; cambios de settings, dos mapas y dos recargas | Repetir con jugadores y en Windows |
| T06 | Reset de muestras por callback de sesión | Desconexión/reutilización real del slot |
| T07–T15 | Forward real, perfiles/identidades simulados; veto Handled/Stop, modificación, contadores, errores y reentrancia | Natives reales y mensajes a jugadores; reset durante forward |
| T16–T20 | Cuenta/equipo/sesión simulados; pérdida sola, snapshot y reset externo | Autenticación, reconexión y equipos reales |
| T21–T28 | StringMaps, RequestFrame, generaciones y callbacks reales; transporte/voto simulados | BuiltinVotes real, voto propio/ajeno y mensajes públicos |
| T29 | Excepción inyectada: intención vacía, guarda liberada y sin éxito falso | Fallo real de sincronización/retirada del detour |
| L01, L02, L05 | Consumidor con política simulada: limpiar, bloquear y no resucitar | Transiciones de la ConVar y extensión reales |
| L01–L09 completos | No certificados por este arnés | SRCDS Linux y Windows independientes |

La suite incluye 44 aserciones funcionales y cinco ejecuciones del muestreador.
Usa los fuentes del producto, no una reimplementación del algoritmo. El host
es SRCDS Linux aislado, sin red, con contenido Valve en solo lectura. No conecta
jugadores. `sb_all_bot_game 1` mantiene la simulación del servidor de pruebas
activa; sus bots no son evidencia humana. No se valida ABI ni tráfico.
El arnés no se incluye en el paquete del producto. El core emitió el aviso de
fallback de `gEntList` a entidades networkables; no se certifica ese gamedata.
Runtime: L4D2 2.2.4.3/10097, SourceMod 1.12.0.7260 y Metamod 1.12.0-dev+1228.
SHA limpio ejecutado: `bed6f6f3a41b589f536afe9d84c91cd4a5701d4b`.
La integración posterior de esta evidencia cambia solo documentos/JSON.

Validación local adicional:

- `make build-smx`: SourcePawn 1.12.0.7260, sin warnings.
- Compilación explícita de `plugin_regressions.sp`, `windows_public_api.sp`,
  `windows_shutdown_consumer.sp` y `windows_shutdown_fill_consumer.sp`.
- `SANITIZE=1 make test-exts-linux`: suite nativa completa, transporte sintético.
- Contenedor `custom-fakelag-validation:local` (Ubuntu 24.04, GCC 13):
  `TEST_ARCH=32 SANITIZE=1 make test-exts-linux` y
  `VENV_DIR=/work/.deps/exts-linux/.venv-container make build-exts-linux`.
- Seis tests Python de exportadores y verificador con `pefile` en el venv.
  El collector Win32 requiere Windows; no se considera fallido ni ejecutado
  como aceptación Linux. Un discovery general inicial no pudo importarlo.
- El workflow compila ahora el arnés. **CI del nuevo trabajo pendiente:** no se
  publicaron los commits para ejecutarlo. El CI histórico no certifica esta rama.

## Repetir el arnés Linux

Se requiere un contenido Valve y Metamod ya instalados y autorizados. Crear un
contenedor nuevo; nunca apuntar el arnés a un servidor compartido. Desde la raíz:

```bash
make build-smx
mkdir -p .build/plugin-regressions
.deps/smx/sourcemod-package/addons/sourcemod/scripting/spcomp \
  tests/plugin_regressions.sp -iscripting/include \
  -i.deps/smx/sourcemod-package/addons/sourcemod/scripting/include \
  -o.build/plugin-regressions/plugin_regressions.smx
# VALVE_VOLUME contiene serverfiles/left4dead2 y su Metamod.
docker run --rm --user "$(id -u):$(id -g)" \
  -v VALVE_VOLUME:/source:ro -v "$PWD:/work" \
  custom-fakelag-validation:local bash /work/tests/prepare_plugin_regressions.sh
docker run -di --name cf-plugin-regressions --network none \
  --user "$(id -u):$(id -g)" -v VALVE_VOLUME:/source:ro -v "$PWD:/work" \
  -w /source/serverfiles -e LD_LIBRARY_PATH=/source/serverfiles/bin \
  custom-fakelag-validation:local /source/serverfiles/srcds_linux \
  -console -insecure -norestart -ip 127.0.0.1 -port 27035 -condebug \
  -game /work/.build/plugin-regressions/game +sv_lan 1 +map c1m1_hotel
python3 tests/run_plugin_regressions.py --container cf-plugin-regressions \
  --game .build/plugin-regressions/game \
  --output .build/plugin-regressions/results.json
docker stop cf-plugin-regressions
docker rm cf-plugin-regressions
```

Usar un gamedir nuevo por ejecución completa; el preparador rechaza directorios
existentes sin la marca privada. No reejecutarlo sobre un servidor vivo. Los
logs de excepciones inyectadas son esperados; el runner rechaza las inesperadas.

## Aceptación pendiente con clientes reales

En **cada plataforma**, construir el mismo SHA y registrar versión de SRCDS,
SourceMod, BuiltinVotes, Left4DHooks, hashes del motor/plugin/extensión y logs
sanitizados. Usar servidor de pruebas y cliente Steam humano. Compilar/cargar
el consumidor `tests/windows_public_api.sp` para controlar veto/modificación;
los casos de fallos inyectados necesitan además el fixture nativo apropiado.

1. Ejecutar T01–T06: carga inicial/tardía, dos mapas, cambiar intervalo/ventana
   antes y después de cada mapa, dos recargas y reconexión/reutilización de slot.
2. Ejecutar T07–T15 con Continue, Handled, Stop y modificación 100→40:
   comparar perfil consultado, mensajes, mapas persistidos y contadores de
   balances global/pares/voto. Repetir durante desconexión, reset y bloqueo LAN.
3. Ejecutar T16–T20 con `0 ms / 15 %`: espectador→equipo, reconexión, modo del
   plugin y modo externo; comprobar que cero/cero permanece vacío.
4. Ejecutar T21–T29: desconectados como única persistencia, activos mezclados,
   RequestFrame/snapshot ya encolados, votos propio/ajeno, dos clears vacíos,
   escritura desde forward y solicitud nueva posterior. Inyectar error de
   retirada y comprobar intención borrada, error visible, infraestructura
   nativa retenida y reintento seguro.
5. Ejecutar L01–L09: partir de `sv_lan 0`, crear perfiles, colas y pérdida;
   pasar a `sv_lan 1` con `sm_custom_fakelag_allow_lan 0` y comprobar vaciado y
   bloqueo de todas las rutas. Con override 1 solo deben entrar solicitudes
   nuevas. Revocarlo también en detour always-on; volver a LAN 0 sin resucitar
   perfiles. Repetir con desconectados, snapshots, votos, forwards reentrantes,
   mapas y recargas. Medir latencia/pérdida y observar reset en tráfico real.

Falta tanto esa aceptación como CI remoto/Windows del SHA nuevo. No declarar
lista para producción esta entrega solo con compilación y las pruebas aisladas.
