# Steam Lifecycle Debug

Extensión SourceMod independiente, sin dependencia de Custom-Fakelag,
Left4DHooks o DHooks. Observa el ciclo de interfaces de Steam; no implementa
un fix. Se compila y distribuye separada del paquete normal, sin autoload.

## Uso

En una instancia privada, instala el binario de tu plataforma y ejecuta:

```text
sm exts load steam_lifecycle_debug
sm_steam_lifecycle_debug 2
```

| Valor de sm_steam_lifecycle_debug | Registro |
|---|---|
| 0, predeterminado | Sin muestras, lecturas del contexto ni archivo abierto |
| 1 | Cambio de modo, LevelInit/LevelShutdown pre/post, conexión, desconexión y descarga |
| 2 | Eventos y muestras a 10 Hz; escribe cambios y heartbeat cada 10 s |

Para apagar: `sm_steam_lifecycle_debug 0`. El muestreo depende de GameFrame;
la hibernación puede detenerlo. Descarga con el ID real de `sm exts list`.
Se retiran hooks/listener/callback y ConVar antes de liberar el módulo.

Log: `addons/sourcemod/logs/steam_lifecycle_debug/trace.log`, rotación a 5 MiB
y un respaldo `.1`. Cada registro incluye hora Unix, elapsed_ms, secuencia,
evento y sv_lan; no incluye identidad/IP del cliente, chat ni payload.
Se vacía el buffer C por registro, sin garantizar persistencia ante corte eléctrico.
Un fallo de archivo suspende el logger y avisa una vez; reactivar permite reintentar.

## Contexto observado

Windows x86 admite únicamente server.dll SHA-256
`a93ec916a8f26fbea85688c321d2ba8dd346d435fab09a0b926dd950c2e1ea12`.
Comprueba identidad del archivo, PE32 y límites cargados; lee RVA `0x7f77dc`,
campos +4/+8 y slots +0x28/+0x24 mediante ReadProcessMemory. Un módulo desconocido
no habilita esas lecturas. La identidad del archivo no certifica todos sus bytes
cargados ni autoriza ejecutar los punteros.

El log conserva objeto, vtable, método candidato, pertenencia a steamclient y
permiso ejecutable. La máscara reads usa 1=objeto, 2=vtable, 4=slot. Un reads=7
no prueba que el objeto siga vivo. Las copias son no atómicas y pueden perder
transiciones. Las direcciones son locales al proceso/ASLR; nunca se invocan.

En Linux registra eventos y sv_lan con `context_unsupported_on_this_platform`;
no reutiliza offsets Windows. Los límites pre/post corresponden a los callbacks
de mapa, no a cada llamada interna Steam. No se escriben contextos ni se cambia
LAN o el validador. Para excepciones y terminación real conserva CDB y el monitor
externo. Cargar este observador requiere SM: no es un control vanilla estricto.

## Compilación

Reutiliza SDK/AMBuild del repo y un build nuevo. Linux requiere multilib i386:

```bash
mkdir -p .build/steam-debug
cd .build/steam-debug
../../.deps/exts-linux/.venv-linux/bin/python ../../configure.py \
  --sdks l4d2 --hl2sdk-root ../../.deps/exts-linux \
  --mms-path ../../.deps/exts-linux/mmsource-1.12 \
  --sm-path ../../.deps/exts-linux/sourcemod-1.12 \
  --enable-optimize --steam-lifecycle-debug
../../.deps/exts-linux/.venv-linux/bin/ambuild
```

Windows: abre MSVC x86 y usa el Python con AMBuild de tus dependencias. Desde
un build nuevo bajo `.build`:

```powershell
python ../../configure.py --sdks l4d2 --hl2sdk-root ../../.deps/exts-windows `
  --mms-path ../../.deps/exts-windows/mmsource-1.12 `
  --sm-path ../../.deps/exts-windows/sourcemod-1.12 `
  --enable-optimize --steam-lifecycle-debug
ambuild
```

Salida relativa al build:
`diagnostics/steam_lifecycle_debug/package/addons/sourcemod/extensions/`, nombre
`steam_lifecycle_debug.ext.2.l4d2.so` o `.dll`. El .so no sirve en Windows.
No uses los scripts de empaquetado normal para instalar este diagnóstico.

## Validación

[CI y límites actuales](../../docs/VALIDATION.md): builds/fixtures x86 en ambas
plataformas; pruebas Linux ASan/UBSan. Compila `tests.cpp` con C++14 y pásale un
directorio temporal existente; en Windows enlaza advapi32.lib. Cubre lecturas
válidas/fallidas, identidad desconocida, null/overflow, flush, append y rotación.

La [matriz Windows](../../docs/WINDOWS_STEAM_DEBUG_VALIDATION.md) reúne 18 procesos
con cliente real: LAN 1 falló 9/9 y LAN 0 cerró 9/9, en vanilla/SM/observador.
La DLL de esos ensayos tenía predeterminado 2. El código actual carga en 0;
su carga/recarga real debe verificarse por separado. El recolector
`tests/windows_steam_debug_trial.py` espera 0 y activa 2 explícitamente; para
repetir la DLL histórica usa `--expected-default 2`, registrando su hash.
