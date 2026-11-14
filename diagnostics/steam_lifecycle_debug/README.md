# Steam Lifecycle Debug

Extensión SourceMod independiente para observar el problema descrito en
[la investigación Windows](../../docs/WINDOWS_SHUTDOWN_INVESTIGATION.md).
No depende de Custom-Fakelag, Left4DHooks ni DHooks. Se compila por separado y no
forma parte del paquete normal de Custom-Fakelag.

## Activación

Instala solo el binario de esta extensión en el servidor privado y cárgalo:

```text
sm exts load steam_lifecycle_debug
sm_steam_lifecycle_debug 2
```

La extensión registra su propia ConVar, sin necesitar un plugin SourcePawn:

| Valor | Registro |
|---|---|
| `0` | Apagado: sin muestras, lecturas del contexto ni archivo abierto |
| `1` | Muestras en cambio de modo, LevelInit/LevelShutdown pre y post, conexión/desconexión y descarga de extensión |
| `2` (predeterminado) | Lo anterior y muestreo a 10 Hz; escribe solo cambios, con heartbeat cada 10 segundos |

El diagnóstico se activa automáticamente al cargar la extensión. Una
configuración del servidor que asigne otro valor a la ConVar puede cambiarlo.

Para detenerlo, usa `sm_steam_lifecycle_debug 0`. Si falla la apertura/escritura,
se suspende el registro y se informa una vez al error log de SourceMod. Volver
a activar la ConVar permite reintentar. Descarga usando el ID real mostrado
por `sm exts list`; los hooks y el listener se retiran antes de liberar el módulo.

Ruta: `addons/sourcemod/logs/steam_lifecycle_debug/trace.log`. Cada registro se
vacía a disco desde el buffer de C; no equivale a persistencia garantizada ante
un corte de energía. Rota a `trace.log.1` al alcanzar 5 MiB; conserva un respaldo.
Los registros contienen hora Unix, milisegundos desde la carga, secuencia,
evento, `sv_lan` y estado del contexto. No contienen SteamID, nombre, IP, chat
ni payload de paquetes. Las direcciones de memoria son locales al proceso/ASLR.

## Qué observa y qué no demuestra

En Windows x86 identifica el archivo del módulo **server.dll realmente cargado**
por SHA-256 `a93ec916a8f26fbea85688c321d2ba8dd346d435fab09a0b926dd950c2e1ea12`,
comprueba cabecera PE32 y tamaño cargado, y observa el contexto en RVA `0x7f77dc`.
Los offsets +4/+8 y slots +0x28/+0x24 proceden del análisis de ese binario.
Un módulo distinto o una identidad ilegible produce un diagnóstico sin leer
esos offsets. La identidad del archivo no certifica que cada byte cargado esté
intacto; el observador no autoriza ningún parche ni llamada a esas interfaces.

Cada puntero se copia mediante `ReadProcessMemory`, nunca se invoca. El registro
incluye objeto, vtable, método candidato, pertenencia a `steamclient.dll`, permiso
ejecutable y máscara de lecturas completadas: 1=objeto, 2=vtable, 4=slot.
Un cero o error de lectura se conserva como observación. Una dirección legible o
ejecutable **no prueba** que el objeto siga vivo ni que el método sea llamable.
Las copias pueden intercalarse con modificaciones del motor; no son una captura
atómica. No se identifican definitivamente los nombres de las interfaces.

En Linux registra los mismos eventos y `sv_lan`, con
`context_unsupported_on_this_platform`: no reutiliza offsets de Windows.
Los hooks de interfaces públicas son observadores SourceHook; no se instalan
detours en SteamGameServer_Shutdown/SteamInternal_GameServer_Init, ni se escriben
contextos, se altera LAN o se modifica la validación de Custom-Fakelag.

Los límites pre/post son de LevelInit/LevelShutdown, no de cada llamada interna
Steam. El muestreo puede perder cambios que ocurran y se reviertan entre muestras,
o no llegar a ejecutarse antes de un crash/modal wait. No recoge excepciones ni
demuestra que el proceso terminó: conserva CDB y el monitor externo para eso.
Para probar sin Custom-Fakelag basta cargar esta extensión con SourceMod; esa
prueba ya no es vanilla estricto, por lo que conserva también un control sin mods.

## Referencias revisadas

- [CSteam3Server::Shutdown (Linux)](https://binaries.l4d2node.org/b/engine_srv.so/f/0x00210d10):
  llama SteamGameServer_Shutdown y borra campos de su propio contexto.
- [CSteam3Server::Activate (Linux)](https://binaries.l4d2node.org/b/engine_srv.so/f/0x00211680):
  contiene selección según sv_lan, cierre y SteamInternal_GameServer_Init.
- [Netprops](https://netprops.l4d2node.org/) enumera SendTables de entidades;
  no se identificó allí el contexto privado de interfaces Steam.

El catálogo aporta pistas para comparar el ciclo de vida; no establece que sus
offsets/firmas Linux correspondan al binario Windows de la investigación ni
documenta por sí mismo una causa del crash observado.

## Compilación independiente

Reutiliza las dependencias del repositorio. Ejecuta desde un directorio de build
nuevo; no uses los scripts de empaquetado normales para este diagnóstico.

Linux, con toolchain x86/multilib y AMBuild instalado en el Python seleccionado:

```bash
mkdir -p .build/steam-lifecycle-debug-linux
cd .build/steam-lifecycle-debug-linux
../../.deps/exts-linux/.venv-linux/bin/python ../../configure.py \
  --sdks l4d2 --hl2sdk-root ../../.deps/exts-linux \
  --mms-path ../../.deps/exts-linux/mmsource-1.12 \
  --sm-path ../../.deps/exts-linux/sourcemod-1.12 \
  --enable-optimize --steam-lifecycle-debug
../../.deps/exts-linux/.venv-linux/bin/ambuild
```

Windows: abre el entorno MSVC **x86**, usa el Python con AMBuild ya instalado y
las dependencias Windows existentes. Desde un directorio nuevo bajo `.build`:

```powershell
python ../../configure.py --sdks l4d2 --hl2sdk-root ../../.deps/exts-windows `
  --mms-path ../../.deps/exts-windows/mmsource-1.12 `
  --sm-path ../../.deps/exts-windows/sourcemod-1.12 `
  --enable-optimize --steam-lifecycle-debug
ambuild
```

El binario queda bajo
`diagnostics/steam_lifecycle_debug/package/addons/sourcemod/extensions/` dentro
del directorio de build. El nombre producido incluye el sufijo de engine del
SDK (`steam_lifecycle_debug.ext.2.l4d2.so` / `.dll`). No se crea autoload.

Pruebas aisladas sin motor: compila `tests.cpp` con C++14 y ejecútalo pasando un
directorio temporal privado existente. En Windows enlaza `advapi32.lib`, usa
MSVC x86 y comprueba además lecturas nativas fallidas/permitidas y rechazo de
identidad. En Linux usa ASan/UBSan; cubre identidad desconocida, punteros nulos,
objetos ilegibles, overflow, cambios de estado, flush, append y rotación de logs.

## Validación y siguiente prueba

Compilación local Linux ELF32 y pruebas aisladas ASan/UBSan aprobadas. La
[validación Windows del 14-11-2026](../../docs/WINDOWS_STEAM_DEBUG_VALIDATION.md)
comprobó compilación MSVC x86, fixture nativo, modos 0/1/2, carga/descarga/recarga
y predeterminado 2. En 18 ensayos con cliente real, LAN 1 falló 9/9 y LAN 0 cerró
correctamente 9/9, tanto en vanilla como con SourceMod y con el observador.
Los logs detectaron las cadenas fuera de Steam después del mapa bajo LAN 1.
Es diagnóstico de ese binario/entorno, no un fix ni una validación de producción.

Para repetir en Windows comprueba: ConVar disponible sin Custom-Fakelag; modo 2 al cargar;
modo 0 sin crecimiento del log ni nuevas muestras; modos 1/2 y retorno a 0; carga/descarga/recarga; rechazo de
un módulo desconocido sin lecturas por RVA; identidad correcta y observación
con cliente real, mapa y desconexión bajo LAN 1 y LAN 0 en procesos nuevos.
Mantén CDB/monitor externo y compara con los ensayos sin este observador. No
declares arreglado un fallo por la última línea del log o por ausencia de crash.
