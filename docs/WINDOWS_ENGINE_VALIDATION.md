# Validación del adaptador Windows

Fecha: 2026-11-13. Base `develop`: `7c72156974257b5a2d460af049409b04176c5332`.
Rama local: `feat/windows-engine-validation`. Se clonó el repositorio bajo
`work/Custom-Fakelag`: no se encontró checkout previo en las ubicaciones
inspeccionadas. Árbol inicial limpio; fetch confirmó origin/develop en esa base.
No se publicó la rama ni se modificó la API pública SourcePawn.

## Resultado y límite de aceptación

Hay implementación candidata para **una DLL PE32 concreta**, compilada y probada
con SDK real en un proceso aislado. **La aceptación completa sigue pendiente.**
No se encontró srcds.exe ni dedicated.dll en Steam, D:, los directorios de trabajo
y Program Files inspeccionados. No se descargó ni duplicó el servidor completo.
La DLL procede del cliente; no se afirma que represente el módulo de un servidor.
No existe extensión instalada en SRCDS ni versión/build SRCDS observada.
No se ejecutó tráfico UDP en SRCDS Windows ni conexión de jugadores humanos.

El adaptador acepta solo el SHA del manifiesto y bytes ejecutables cargados
idénticos tras reubicación. Rechaza otros módulos y parcheos previos de .text.
No existe una ConVar/booleano que omita esa validación. La aceptación de identidad
implementa el contrato estático; no certifica gameplay, producción u otros builds.

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
- SourcePawn compiler 1.12.0.7260. No runtime SM/Metamod en SRCDS ejecutado.
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
La procedencia se apoya en el código del módulo exacto; no se certifican plugins
que sustituyan punteros o parcheen el motor después de inicializar el adaptador.

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

## Matriz

| Nivel/caso | Estado | Alcance |
|---|---|---|
| PE, patrones, operandos, callers, capacidad y lector | Aprobado | Análisis estático de DLL cliente exacta |
| SDK real, imagen mapeada y ASLR | Aprobado | Proceso aislado con ASan |
| Suite MSVC x86 | Aprobado | Sintética, final con ASan |
| Build Windows normal/opt-in | Aprobado | PE32; normal sin cf_probe_, arnés con 4 nombres |
| Transporte consola nativa | Aprobado | Child Python recibe WriteConsoleInputW; no SRCDS |
| SourcePawn normal y custom_fakelag_test | Aprobado | Compilación explícita, API en servidor no ejecutada |
| Linux x86/x64 ASan/UBSan y ELF32 | Aprobado | WSL Ubuntu 24.04; sin runtime de servidor |
| Módulo SRCDS y hash extensión instalada | No ejecutado | No existe instancia; hashes son de artefactos compilados |
| SRCDS activación, sin perfiles, UDP baseline/50/120/300 ms | No ejecutado | Falta srcds.exe/dedicated.dll compatible |
| SRCDS pérdidas 0/intermedia/100 Bernoulli/GE y límites | No ejecutado | Falta instancia Windows |
| SRCDS generaciones, reset, modos, mapa, unload/reload | No ejecutado | Solo regresiones aisladas disponibles |
| Humanos: API/plugin, Handled/Stop, errores, reconexión | No ejecutado | Falta instancia y sesión humana conectada |
| Nueva ejecución SRCDS Linux | No ejecutado | Volumen/módulo identificado no disponible en este host |

## Continuación pendiente

Obtener SRCDS Windows ejecutable compatible y verificar **su** engine.dll antes
de activar. Otro SHA exige análisis nuevo y seguirá rechazándose. Reutilizar
VPK/mapas existentes mediante searchpaths de solo lectura; crear gamedir privado
con gameinfo, addons/config/logs propios, SourceMod/Metamod Windows y Left4DHooks
para el plugin normal. Registrar hashes del módulo/extensión instalados y módulo
real del proceso. No hay un artefacto instalado que pueda confundirse con el build.

El runner ahora admite `--srcds <srcds.exe> --game <gamedir-privado> --log <logSM>
--output <json> --change-map` en lugar de --container. Exige marcador
.custom-fakelag-isolated en el gamedir y log dentro de ese directorio; crea un
proceso/consola oculta propios y solo controla ese proceso. Su transporte nativo
fue ejecutado en el self-test; el runner completo no está validado en SRCDS.
La matriz heredada del runner cubre 120 ms y extremos de pérdida/ciclo de vida;
completar baseline, 50/300 ms, porcentajes intermedios y límites antes de aceptar
el encargo. No se inventaron resultados para esos casos.

Conectar un humano para API/plugin, Handled/Stop en perfil nuevo/existente,
forward inválido, sesiones pendientes/reconexión y slot reutilizado, mapa, reset,
modos y descarga/recarga. UDP sintético no acredita autenticación ni elegibilidad.
Mantener consola local para recuperar 100% pérdida. Inyectar fallos de protección
solo en arneses aislados. Registrar reloj/tick y distinguir retención entrante de
RTT. La entrega no certifica otros binarios, x64 ni producción.
