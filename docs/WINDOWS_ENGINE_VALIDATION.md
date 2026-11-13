# Validación del adaptador Windows

Fecha: 2026-11-13. Base `develop`: `7c72156974257b5a2d460af049409b04176c5332`.
Rama local: `feat/windows-engine-validation`. Se clonó el repositorio bajo
`work/Custom-Fakelag`: no se encontró checkout previo en las ubicaciones
inspeccionadas. Árbol inicial limpio; fetch confirmó origin/develop en esa base.
No se publicó la rama ni se modificó la API pública SourcePawn.

## Resultado actualizado

La DLL dedicada y su módulo cargado quedaron identificados. Pasaron 32 casos UDP,
17 comprobaciones de la API con cliente Steam real, comandos del plugin normal,
reconexión en el mismo slot, cambio de mapa y descarga/recarga con tráfico.
Se ejecutaron tanto el build opt-in como el build normal sin comandos cf_probe.

La aceptación funcional está comprobada para esta identidad Windows x86.
**El cierre completo del proceso SRCDS falla en este host**, incluso en un proceso
nuevo sin Metamod, SourceMod ni Custom-Fakelag: exit `0xc0000409`.
Se conserva como fallo, separado de la retirada correcta del detour/extensión.
No se parcheó el motor ni Steam para ocultarlo. No se certifican otros builds,
x64, cargas de producción ni runtime Linux nuevo.

## Identidad y entorno

- Ruta analizada: `C:\Program Files (x86)\Steam\steamapps\common\Left 4 Dead 2\bin\engine.dll`.
- SHA-256: `8a6d468059394bf4cfce32f11dcba12ef45de88da1373084d5a2916d0bf7ba86`.
- I386 `0x14c`, PE32 `0x10b`, timestamp `0x6a440ed6`, SizeOfImage `0x73f000`,
  base preferida `0x10000000`; FileVersion/ProductVersion ausentes.
- steam.inf: PatchVersion 2.2.4.3. Steam app 550 cliente, build 23990068.
  El build Linux 23990100 no se atribuye a esta instalación Windows.
- CodeView RSDS GUID `74953c8e-a15b-43d9-bbf3-6fb8f0a85876`, age 34,
  ruta engine.pdb en el manifiesto. No se obtuvo PDB; nombres inferidos del código.
- Windows 11 Pro 10.0.26300, PowerShell 7.6.9, Python 3.12.13, AMBuild 2.0.
- Instalados Build Tools 2022 17.14.45, MSVC 19.44/14.44.35207 x86,
  SDK 10.0.26100.0 y componente VC.ASAN para esta validación.
- pefile 2024.8.26 y Capstone 5.0.9 en venv privado.
- HL2SDK L4D2 `2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6`;
  SourceMod `3f7460671f7adc4a3c6791a47d21ba3e7b5fba91`;
  Metamod `4e031eb571f5978eea8207b5d915c9cd0e8d6c58`;
  AMBuild `5b0aa725beef33c9cf6a1b00659a010c3d9120d3`.
- SourcePawn compiler 1.12.0.7260. Runtime dedicado posterior: SM 1.12.0.7260 / Metamod 1.12.0-dev+1229.
- Linux: WSL2 Ubuntu 24.04, GCC 13.3.0, Python 3.12.3; mismos SDK reutilizados.
- Espacio inicial C: ~1012 GB y D: ~551 GB libres. Dependencias/builds privados;
  no se modificaron addons/config de Steam ni instalaciones de uso real.

## Contrato Windows comprobado estáticamente

[Manifiesto](runtime/windows-engine-2.2.4.3.json),
[bytes/desensamblado](runtime/windows-static-2026-11-13.json) y
[resultados/hashes](runtime/windows-validation-2026-11-13.json).
RVA relativas al módulo; las instrucciones del JSON muestran VA preferidas.

| Elemento | Evidencia Windows |
|---|---|
| Hook | 0x1c9ba0: cdecl, bool [ebp+8], paquete [ebp+12], retorno AL; caller limpia pila |
| Firmas | Una coincidencia de cada patrón en .text; net_time firma 0x1c9d6a, operando +2 |
| Reloj | Double writable 0x6b2b48; fld qword/fstp [packet+0x10]; sin otra indirección |
| Paquetes | CUtlVector: puntero 0x6b2e04, count 0x6b2e10; stride 0x50 en 0x1cdd29/0x1cc5c9 |
| SDK real | netadr 12/align4, lector 36/align4, paquete 80/align8 (Linux align4) |
| Offsets | from=0, source=12, received=16, data=24, message=28, size=64, wiresize=68, stream=72, next=76 |
| Asignación | 0x1cdee5 pide 0x37ab8; 0x1cdef8 suma 4; fallback pide 0x37ab0; capacidad mínima 0x37ab0 |
| Reutilización | 0x1ce177 vuelve a pasar el mismo buffer a NET_GetPacket en 0x1ce17f |
| Recepción | 0x1cd6bc pasa 0x37ab0; split comprueba límite en 0x1cd4e4/0x1cd55e |
| Comprimidos | Split/descompresión copian al buffer vivo; 0x1cd948/0x1cd94e, sin sustituir packet.data |
| Loopback | Copia a packet.data en 0x1cc966/0x1cc96b; hook false/true 0x1cc93b/0x1cc99c |
| Lector | Solo se prepara vtable en 0x1cdd71 antes del hook; punteros/cursor pueden ser antiguos |
| Reconstrucción | Datos entregados convergen en 0x1cddcd; StartReading(data,size,0,-1) en 0x1cdddc |
| Hora al liberar | Restauración nativa 0x1c9d6a carga net_time actual y escribe received |
| Byte stream | No preparado en constructor/rutas inspeccionadas; Windows preserva el destino sin leerlo como bool |

Cuatro calls directos al hook: loopback, recepción y NET_GetPacket. Los dos calls
a NET_GetPacket son lectura inicial/repetida de NET_ProcessSocket con el mismo
buffer. No se deduce capacidad de size o campos del lector. No se copia/lee el
lector ni se guarda ningún puntero suyo en la cola. El stream Windows permanece
opaco en la entrada viva y no pasa a metadato propietario. La ruta Linux conserva
su semántica anterior. La alineación MSVC procede de representación compilada;
el stride y los accesos a campos se contrastan con instrucciones independientes.

La restauración valida antes de escribir, conserva buffer y byte stream, copia
payload propio/metadatos preparados y pone pNext=null como el nativo. received
usa el reloj actual; recepción original y releaseAt permanecen separados.
Antes de conceder capacidad se valida región, count y entrada de tabla.
La procedencia se apoya en el código del módulo exacto; no se certifican cambios del contrato de paquetes. Left4DHooks modifica
FillServerInfo fuera de ese contrato; su orden de carga se registra más abajo.

GetModuleHandleEx/GetModuleFileNameW determinan el propietario de las direcciones.
Se compara SHA-256 del archivo y toda sección ejecutable cargada contra bytes
reubicados IMAGE_REL_BASED_HIGHLOW. Windows modifica ImageBase en la cabecera;
se normaliza ese campo y el resto debe coincidir. Se exigen base+RVA exactos,
operando net_time correcto, regiones válidas y reloj finito. Identidad y bytes
completos implican las firmas únicas documentadas. Gamedata no cambió.
Se registran módulo/base/direcciones al aceptar en runtime. No se presenta este
control de compatibilidad como defensa contra un proceso hostil.

## Comandos reproducibles

El make del PATH resultó ser BusyBox, no GNU Make. Al no soportar funciones GNU
resolvió DEPS_DIR a /.deps. Se trasladaron esas dependencias creadas por la tarea
a .deps/exts-windows y se creó venv nuevo; se usaron scripts equivalentes.
En la ejecución se verificó exit code y log, no solo existencia de artefactos.

```powershell
$env:DEPS_DIR = Join-Path $PWD '.deps\exts-windows'
$env:VENV_DIR = Join-Path $env:DEPS_DIR '.venv-native'
$env:VCVARSALL_PATH = 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvarsall.bat'
pwsh -NoProfile -File scripts/fetch-windows-deps.ps1
python -m venv $env:VENV_DIR
& "$env:VENV_DIR\Scripts\python.exe" -m pip install "$env:DEPS_DIR\ambuild"
pwsh -NoProfile -File scripts/run-windows-tests.ps1
$env:CUSTOM_FAKELAG_ASAN = '1'
pwsh -NoProfile -File scripts/run-windows-tests.ps1
pwsh -NoProfile -File scripts/test-windows-sdk-contract.ps1 -EnginePath '<DLL identificada>'
Remove-Item Env:CUSTOM_FAKELAG_ASAN
pwsh -NoProfile -File scripts/build-windows-l4d2.ps1
$env:CUSTOM_FAKELAG_ENGINE_HARNESS = '1'
$env:BUILD_DIR = Join-Path $PWD '.build\windows-harness'
pwsh -NoProfile -File scripts/build-windows-l4d2.ps1
Remove-Item Env:CUSTOM_FAKELAG_ENGINE_HARNESS,Env:BUILD_DIR
python tests/windows_console.py
# En venv de análisis con pefile/capstone:
python tests/verify_windows_engine.py '<DLL identificada>' --output offline.json
python -m unittest discover -s tests -p test_windows_verifier.py
$env:DEPS_DIR = Join-Path $PWD '.deps\smx'
python scripts/fetch-plugin-deps.py --root . --deps-dir .deps/smx
python scripts/build-plugins.py --root . --output-root .build/plugins
& .deps/smx/sourcemod-package/addons/sourcemod/scripting/spcomp.exe scripting/custom_fakelag_test.sp -iscripting/include -i.deps/smx/sourcemod-package/addons/sourcemod/scripting/include -o.build/custom_fakelag_test.smx
```

Linux, desde WSL y el checkout: `DEPS_DIR="$PWD/.deps/exts-windows" SANITIZE=1
bash scripts/run-linux-tests.sh`, y otra ejecución con `TEST_ARCH=32`. Build:
`DEPS_DIR="$PWD/.deps/exts-windows" VENV_DIR="$PWD/.deps/venv-linux"
bash scripts/build-linux-l4d2.sh`; incremental posterior con el mismo ambuild.
No se interpreta WSL como una ejecución del servidor Windows o Linux.

La suite conserva semillas 0xCF123+porcentaje, 2,000,000 muestras en cada nivel GE
0/1/10/20/50/80/99/100 y tolerancias de ocho sigma con correlación. Se conservan
memoria/movimientos, cleanup, sesiones, límites, veto/reentrada y fallo de retirada
sin escrituras/liberaciones con retry. No se sustituyeron por checks de texto.
El test SDK mapea PE con DONT_RESOLVE_DLL_REFERENCES; no ejecuta engine.dll.
Manipula datos y un byte de código exclusivamente en su propio proceso para
comprobar rechazo, y restaura los bytes. Usa SDK real, lector/stream envenenados,
clock/count/capacidad/transacción y reconstrucción StartReading del SDK.
ASan instrumenta el ejecutable/adaptador del test, no el motor ni todas las libs
precompiladas. No se ejecutó UBSan Windows.

Errores resueltos: enlace Winsock (ws2_32.lib); htons del arnés (winsock2.h);
ImageBase reubicada; venv Windows relocado; LIBVCASAN faltante (instalación ASan).
El intento alternativo de venv Linux sin build isolation falló por bdist_wheel;
el venv Linux original completó build e incremental. Los builds finales terminan
exit 0 sin warnings de compilación. El script verifica retornos y valida el destino
antes de borrarlo. Los logs de la entrega retienen intentos y resultados finales.

## Ejecución dedicada y evidencia final

[evidencia estructurada](runtime/windows-runtime-2026-11-13.json).
Se descargaron con DepotDownloader 3.4.0 únicamente el depot Windows 222862
(manifest 3949057889917418048, 62,773,088 bytes descargados / 161,492,365 en disco)
y bootstrap/config/platform del común 222861 (manifest 4827977561765481436,
7,532,144 descargados / 14,649,422 en disco). Fuente oficial Steam app 222860,
build 23990100. No se descargaron los 9.5 GB del depot común completo.

57,810 hardlinks reutilizan 13,440,099,938 bytes de VPK, mapas, sonido, escenas y
otros assets inmutables. Addons, binarios, configuración, logs, navegación y
cachés son privados. La comprobación posterior encontró **0 assets originales
cambiados** (tamaño/mtime). El registro completo permanece en la instancia de
trabajo. No se modificó la instalación real de Steam. El servidor quedó apagado,
con el build normal restaurado y el plugin de aceptación deshabilitado.

Runtime: SourceMod 1.12.0.7260, Metamod 1.12.0-dev+1229, Left4DHooks 1.175,
Builtin Votes 0.8.1 compilado localmente. Revisiones y hashes están en el JSON.
El módulo real fue `work/windows-srcds/bin/engine.dll`, con SHA del manifiesto;
el cliente de Steam tiene los mismos bytes. El build normal efectivamente
cargado y probado tiene SHA-256
`b67bd608e3f6d4d709011cd5aaf7deb4562bcee2f9a7aa147391113c4e626017`.

### Resultados funcionales

- 50/120/300 ms medidos con net_time en despacho frente a recepción original;
  la retención añade la granularidad del frame. Con el humano, 120 ms configurados
  retuvieron aproximadamente 138 ms. No es RTT ni el promedio de net_graph.
- Bernoulli y GE: 0/50/100% en series de 400 datagramas; contabilidad de recepción,
  despacho y pérdida separada de saturación/restauración. Cero fallos de captura
  o restauración. Un porcentaje intermedio observado no se presenta como exacto.
- Límite de sesión: 256 pendientes / 5,888 bytes y 44 descartes de saturación tras
  300 datagramas. Reset deja cero paquetes/bytes y es idempotente.
- Edición invalida generación; solo despachan paquetes nuevos. Modos, mapa y
  descarga/recarga eliminan pendientes y estado GE.
- Cliente Steam autenticado real, no bot: aplicación/consulta/limpieza, Handled y
  Stop en perfil nuevo/existente sin error ni éxito notificado, modificación
  permitida, error de callback, entrada inválida, Action inválida y reentrada.
- Corrección encontrada en runtime: `CForward::Execute` devuelve SP_ERROR_NONE
  aunque un listener arroje excepción. El bridge ahora ejecuta cada callback,
  conserva handles/serials para evitar punteros caducados, propaga errores y
  mantiene la agregación ET_Hook/Stop. No cambió la API pública.
- Comandos normales probados mediante FakeClientCommand sobre el humano real;
  permisos temporales restaurados. El plugin puede derivar packet loss según su
  política; el arnés dejó de asumir siempre 0%. Los primeros fallos de esa
  expectativa y del cambio a un modo ya vigente se conservan en los logs.
- Reconexión: mismo slot/IP/puerto, nuevo userid, entrada inicial sin perfil y cola
  anterior vacía. El plugin normal restauró después un perfil persistido de 5 s,
  conforme a su política; se distingue de conservar paquetes antiguos.
- Mapa con tráfico real y perfil 5 s: limpieza y reconexión sin perfil residual.
  El build normal pasó nuevamente las 17 comprobaciones después del mapa y de
  la recarga. Se leyeron los primeros cinco bytes en el proceso: originales
  `55 8b ec 51 57` antes/después y salto E9 durante activación.

### Transporte, errores e investigación

SRCDS recrea su consola: retener CONIN del launcher perdía comandos. El transporte
reabre el handle y renueva la conexión a la consola. Desactiva QuickEdit, usa
CREATE_BREAKAWAY_FROM_JOB y una ruta -game relativa. Algunas órdenes de carga
requieren esperar a que termine el trabajo de SourceMod. El runner reintenta solo
consultas de estado, nunca mutaciones. El último arranque nativo sobrevivió al
cambio de mapa/reconexión y al control externo; no se atribuye con certeza una
única causa a todas las interrupciones de los primeros intentos.

127.0.0.1 recibió UDP pero no produjo respuestas observables para el cliente;
la IP privada 192.168.1.87 respondió y permitió la conexión real. No se cambiaron
firewall/router. El baseline connectionless sin perfil comprueba cola cero;
el RTT del challenge de loopback sigue sin medida válida.

Un reload con Left4DHooks activo fue correctamente rechazado: modifica cinco
bytes en RVA 0x133cb0 (`CBaseServer::FillServerInfo`, firma de su gamedata).
La comprobación de toda .text no se debilitó. La recarga validada descarga
player_fakelag y Left4DHooks antes de reinicializar Custom-Fakelag y los carga
después. Los offsets del contrato del paquete no se trasladaron de Linux.

Los primeros WER mostraban SourceMod durante LdrShutdownProcess. CDB
10.0.29680.1004 capturó una primera AV en server.dll durante un quit después de
retirar la extensión. Una comparación nueva sin todos los mods reprodujo el
mismo exit 0xc0000409 que el último runner. El fallo de salida permanece abierto;
no demuestra un fallo de retirada de nuestro detour y tampoco se oculta.
El runner ahora termina exit 1 si el proceso sale mal, aunque los 32 casos
funcionales hayan pasado. Dumps se mantienen solo localmente; el paquete entrega
stack/logs, no memoria completa de procesos.

### Reproducción del montaje y runtime

Herramienta usada: [DepotDownloader](https://github.com/SteamRE/DepotDownloader),
con soporte oficial -filelist/-manifest-only. Comandos reales, desde el workspace:

```powershell
DepotDownloader.exe -app 222860 -os windows -manifest-only -dir work/windows-srcds
DepotDownloader.exe -app 222860 -depot 222862 -dir work/windows-srcds
# filelist incluye gameinfo/steam.inf, cfg, platform y los .rc de bootstrap.
DepotDownloader.exe -app 222860 -depot 222861 -filelist work/common-bootstrap-files.txt -dir work/windows-srcds
python scripts/prepare-windows-server.py --client '<instalación Steam>' --server '<instancia privada>'
# Instalar SM/Metamod privados y copiar el build opt-in verificado.
python tests/run_engine_probe.py --srcds '<instancia>/srcds.exe' --game '<instancia>/left4dead2' --log '<log SM privado>' --output windows-probe.json --extension-id 3 --change-map --unload-sourcemod-id 1
```

Para UDP sintético se deshabilitaron player_fakelag/Left4DHooks y el plugin de API:
no se mezcló el resolver sintético con pruebas de elegibilidad/autenticación.
Para jugadores se inició un proceso nuevo, con manager real y plugins normales;
solo se usó cf_probe_status como observador en el build opt-in. Se repitió API,
plugin, mapa y recarga con la DLL normal. `tests/windows_public_api.sp` se compila
explícitamente y queda fuera del paquete normal. `tests/run_windows_session.py`
permite operar una consola privada con archivo de órdenes sin repetir mutaciones
anteriores. Los IDs concretos deben comprobarse con sm exts list/meta list.

## Matriz final

| Nivel/caso | Estado | Evidencia/alcance |
|---|---|---|
| Identidad PE/ABI/capacidad/lector y módulo real | Aprobado | Misma identidad exacta, ASLR y direcciones cargadas |
| SDK real y pruebas aisladas | Aprobado | 19 checks SDK con MSVC ASan |
| Builds Windows normal/opt-in y SourcePawn | Aprobado | Normal sin cf_probe; test plugin compilado aparte |
| UDP sin perfiles, 50/120/300 ms, pérdidas, límites | Aprobado | 32 checks funcionales, JSON y logs |
| API humana/vetos/error/reentrada | Aprobado | 17 checks finales con Steam real, cero fallos |
| Plugin normal, reconexión, mapa, unload/reload | Aprobado | Proceso nativo, slot reutilizado y bytes restaurados |
| Regresión Linux x86/x64 y ELF32 | Aprobado | WSL/GCC13, ASan/UBSan; sin servidor Linux nuevo |
| Salida limpia de todo SRCDS | Fallido | Mismo fallo en baseline vanilla sin mods; pendiente |
| Otras DLL, x64 Windows, producción/soak | No ejecutado | Compatibilidad no inferida |

Pendiente concreto: diagnosticar/corregir la salida completa de SRCDS de este host
sin alterar la instalación de juego real ni esconder el fallo. La aceptación
funcional de la extensión se limita al módulo y al entorno registrados.
