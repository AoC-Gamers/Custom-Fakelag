# Steam Lifecycle Debug: validación Windows

14-11-2026, America/Santiago. Extensión diagnóstica independiente, Windows x86.

## Resultado

La DLL compila, carga y registra directamente `sm_steam_lifecycle_debug=2`.
Pasaron el fixture nativo y la sesión con cliente real que comprueba modos
0/1/2, descarga, retirada de ConVar y recarga con predeterminado 2.

La matriz mínima tiene **18 procesos nuevos, tres por cada fila A1/A0/B1/B0/C1/C0**.
LAN 1 terminó en `0xc0000005` en los nueve ensayos, después de cambiar de mapa
y solicitar la desconexión del humano, antes de enviar quit. LAN 0 sobrevivió
a la desconexión, autenticó una sesión nueva del mismo cliente y terminó con
código 0 al enviar quit con el humano conectado, en los nueve ensayos.
Todos los handles reales quedaron señalados; no hubo terminaciones forzadas.

El observador capturó en los tres C1 cadenas objeto/vtable/método que dejaron
de pertenecer a steamclient después del mapa. En C0 permanecieron dentro del
módulo durante mapa/desconexión/reconexión; el primer registro posterior que
dejó de ser una cadena Steam fue el contexto nulo en `extension_unload` al cerrar.
No se detectó una diferencia en el resultado de cierre entre A, B y C para
un mismo LAN. Esta muestra no mide sobrecoste ni descarta perturbaciones de timing.

La reproducción en vanilla confirma que el observador, SourceMod y
Custom-Fakelag no son necesarios para este fallo bajo las condiciones probadas.
No atribuye todos los fallos posibles a una única causa ni valida producción.
No se implementó un arreglo del motor ni se cambió el validador de Custom-Fakelag.

## Procedencia y compilación

Base exacta: `070a71b1b7d64dc8cdc4cc6bcfaaab11cb5c28e4`.
Rama local nueva: `codex/windows-steam-lifecycle-debug`.
La consulta remota de develop obtuvo esa base; la referencia local antigua
origin/develop permanecía en `65031fb`. Se usó la base solicitada, sin mezclar
la rama anterior de investigación. No hubo push, PR ni publicación.

El ZIP de entrada se extrajo primero en una carpeta nueva y se inspeccionaron
sus diez entradas. Solo esas diez fuentes se aplicaron al worktree nuevo.
Sus SHA-256 siguen coincidiendo byte por byte con el ZIP. El commit de importación
y todos los hashes constan en `build/build-record.json`. Los cambios posteriores
son recolectores, exportación de evidencia, preparación del capturador e informe;
no hubo que corregir la extensión suministrada. El README de entrada describe
el estado previo a esta validación; los resultados Windows están en este informe.

ZIP SHA-256: `a143caec7c947d60c9d5eb68162b2cda1d53377dce3f2994b0786fc2295389a5`.
Se verificaron las cuatro entradas del manifiesto inicial; el `.so` Linux no se
ejecutó ni se usó como binario Windows.

Herramientas: MSVC x86 **19.44.35230.0**, Build Tools 2022 **17.14.45**,
Windows SDK **10.0.26100.0**, Python **3.12.13**, AMBuild **2.0**.
Las dependencias antiguas ya no estaban disponibles y se repusieron únicamente
SDK/AMBuild en una carpeta separada, sin descargar otra copia completa del juego.

| Dependencia de compilación | Commit |
|---|---|
| hl2sdk-l4d2 | 2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6 |
| sourcemod, 1.12-dev | 3f7460671f7adc4a3c6791a47d21ba3e7b5fba91 |
| metamod-source, 1.12-dev | 4e031eb571f5978eea8207b5d915c9cd0e8d6c58 |
| ambuild | 5b0aa725beef33c9cf6a1b00659a010c3d9120d3 |

Los submódulos se registran en build-record. Las revisiones de cabeceras SDK
no se presentan como idénticas al punto exacto del runtime instalado.
El build independiente terminó con código 0 y sin warnings nuevos del diagnóstico.
El primer intento en una ruta larga falló con C1083 antes de producir DLL;
se repitió en `.build/steam-debug-x86` usando temporalmente `subst S:` sobre
la carpeta work. La transcripción exitosa está en `build/build.log`.

| Artefacto | SHA-256 |
|---|---|
| steam_lifecycle_debug.ext.2.l4d2.dll | 04c54a453f115dc59e7df3198cea51150c9aca5459d583d9bca97735c06997ca |
| PDB correspondiente | b0801d47f658f34e4e5dd461c4eebbd00662d3398b9e8d47151e5522ee33356d |

PE32 I386; imports KERNEL32.dll, ADVAPI32.dll y tier0.dll.
Se cotejó el GUID/age del RSDS con el stream 1 del PDB:
`1f8aa4a4-b60c-40bf-800a-1fcdbe3f19e3`, age 1. No se distribuyen DLL de Valve.

El fixture `tests.cpp` se compiló con `/std:c++14 /EHsc /W4`, x86 y advapi32.lib,
y se ejecutó nuevamente en un directorio privado nuevo: código 0,
`Diagnostic tests passed (no SRCDS runtime claim)`.
Cubre identidad desconocida sin activar offsets, lectura válida/inválida,
PAGE_NOACCESS, null/overflow, diferencias del contexto, flush, append,
rotación con un respaldo y fallos de apertura/escritura. Esto no es una
prueba de SRCDS completo con ASan/UBSan.

## Entorno y protocolo

Se reutilizó el servidor privado marcado `.custom-fakelag-isolated`, con
assets del dedicado oficial en
`D:\SteamLibrary\steamapps\common\Left 4 Dead 2 Dedicated Server`.
Cfg, addons, logs y sprays escribibles permanecieron en almacenamiento privado.
No se duplicó el juego completo ni se modificaron sus archivos en Steam.
No se cambió firewall, router, credenciales ni políticas globales de dumps.

| Componente verificado | Identidad |
|---|---|
| Motor | L4D2 2.2.4.3, build 10097, x86 |
| engine.dll SHA-256 | 8a6d468059394bf4cfce32f11dcba12ef45de88da1373084d5a2916d0bf7ba86 |
| server.dll SHA-256 | a93ec916a8f26fbea85688c321d2ba8dd346d435fab09a0b926dd950c2e1ea12 |
| srcds.exe SHA-256 | acf716595c71b47913e86e5e33f07deeb9ec6c8e08265cc6f18e9ae371230cd7 |
| steam_api.dll SHA-256 | 25a1975363e587f7c64eee7cf2fdcb02eb7511e178f1ae0b38783322a2bd6339 |
| steamclient.dll oficial, realmente cargada desde bin del dedicado D: | b593058386086c3c1feecf9a9228f43872419bcb5ab7e45662cfbf7a9fe6993f |
| SourceMod runtime | 1.12.0.7260 |
| Metamod runtime | 1.12.0-dev+1229 |

Los JSON contienen PID, fechas Unix, revisión y hash del recolector utilizado,
hashes binarios, bases ASLR, módulos efectivos y ruta real del runtime Steam.
`SteamAppId=550`; SteamGameId y SteamOverlayGameId `222860` mantienen separado
el dedicado del cliente de escritorio. La selección temporal HKCU SteamClientDll
se restauró en finally y se verificó en cada ensayo. Steam no se reinició
durante esas ventanas. Se usó `-insecure` en la instancia privada: las conexiones
confirmaron validación Steam y estado active, sin afirmar cobertura VAC.

Cada proceso arrancó c1m1_hotel con el cfg original, cambiando solo sv_lan.
Se consultó LAN al inicio y después del cambio a c1m2_streets.
Un mismo cliente Steam real fue identificado privadamente en los 18 ensayos.
La entrega conserva únicamente los contadores y confirmación de igualdad,
sin exportar su identidad.

Actividad definida: humano autenticado en estado **active**, sesión de gameplay
estacionaria con tráfico normal durante al menos 15 s, sin automatizar movimiento
ni introducir paquetes sintéticos. Se verificó active antes de iniciar cada
intervalo y un humano al terminar. Tras el mapa se repitió el intervalo.
Se expulsó el userid actual leído de la última respuesta status, no del scrollback.
En LAN 0 se verificaron cero humanos, una nueva validación de sesión y otros
15 s antes de quit. Los intervalos exactos están en matrix-summary y trial.json.
La consola/MOTD del cliente podía estar visible; no se afirma una sesión de
combate o movimiento continuo.

El recolector retuvo el handle del proceso hijo hasta WaitForSingleObject señalado
y cotejó su exit code con GetExitCodeProcess. El final del recolector o de CDB
no se usó como sustituto de la salida real. No se transformaron timeouts en PASS.

## Matriz sin depurador

| Fila | Componentes efectivos | LAN | Repeticiones | Resultado |
|---|---|---|---:|---|
| A1 | Vanilla, sin Metamod/SM/observador | 1 | 3 | 3 × c0000005 tras kick, sin quit |
| A0 | Vanilla, sin Metamod/SM/observador | 0 | 3 | 3 × 0, reconexión y quit conectado |
| B1 | Metamod + SM mínimos | 1 | 3 | 3 × c0000005 tras kick, sin quit |
| B0 | Metamod + SM mínimos | 0 | 3 | 3 × 0, reconexión y quit conectado |
| C1 | B + observador, predeterminado 2 | 1 | 3 | 3 × c0000005 tras kick, sin quit |
| C0 | B + observador, predeterminado 2 | 0 | 3 | 3 × 0, reconexión y quit conectado |

Orden real intercalado:
C1_r1, A0_r1, B1_r1, C0_r1, A1_r2, B0_r2, A0_r2, C1_r2b,
B0_r3, A1_r3, C0_r2, B1_r2, B0_r4, A1_r4, C0_r3, B1_r3, A0_r3, C1_r3.
La eliminación/reintroducción bajo la misma configuración vanilla se observó
en A1_r2 → A0_r2 → A1_r3, con otras filas intercaladas. Solo LAN cambió en el cfg.
El número del sufijo es un identificador histórico, no el denominador estadístico.
`matrix-summary.json` enumera los 18 ensayos seleccionados y `trials/<id>/trial.json`
permite revisar cada evento y módulo. No hubo CF, DHooks, Left4DHooks ni plugins
opcionales cargados en esta matriz. No se ejecutó la pareja opcional ampliada
CF/Left4DHooks: esta entrega no añade validación de perfiles ni recarga de CF.

## ConVar y lectura del contexto

La sesión `preflight_C0_client` pasó con código final 0:

| Comprobación | Evidencia |
|---|---|
| Carga sin SourcePawn ni CF | DLL presente; consulta devuelve 2 sin asignación manual |
| Modo 0 | Mismo tamaño y SHA del log después de frames y cambio de mapa |
| Modo 1 | Sin muestras de frames durante 12 s; aparecen eventos de mapa |
| Modo 2 | Muestras/heartbeat durante 12 s con cliente activo |
| Vuelta a 0 y descarga | ID real 1 consultado; módulo ausente, ConVar desconocida, log estable incluso tras mapa |
| Recarga | Módulo vuelve; ConVar vuelve a predeterminado 2 |

Revisión de fuente: modo 0 retorna antes del sondeo y ejecuta Close del logger;
SDK_OnUnload retira frame hook, ClientListener, cuatro hooks de nivel y callback,
desregistra ConVar y cierra el archivo. La ausencia del módulo, ConVar y nuevas
escrituras se comprobó en ejecución; no se enumeró directamente cada estructura
interna de hooks ni se hizo un sondeo exclusivo del handle del archivo.

En un piloto sin humano, el servidor hibernaba y no se producía el heartbeat
esperado: GameFrame no avanzaba. Esa condición no demuestra avería del logger.
La repetición con cliente activo pasó. El muestreo a 10 Hz/heartbeat de 10 s
depende de recibir GameFrame; no es un temporizador externo al motor.

En C1/C0 el diagnóstico informó `identified_windows_server`, `identified=1`.
El fixture rechazó la identidad desconocida; no se modificaron DLL de Valve
para crear un caso negativo en vivo. Solo se admite el hash server.dll señalado,
RVA 0x7f77dc, campos +4/+8 y slots +0x28/+0x24.

| Ensayo | Primer estado no Steam posterior a cadena Steam, ambos campos | elapsed_ms |
|---|---|---:|
| C1_r1 | sample, después del mapa | 91185 |
| C1_r2b | sample, después del mapa | 60685 |
| C1_r3 | sample, después del mapa | 49281 |
| C0_r1 | extension_unload, contexto nulo | 157591 |
| C0_r2 | extension_unload, contexto nulo | 201870 / 201871 |
| C0_r3 | extension_unload, contexto nulo | 183407 |

Ejemplo C1_r1, campo +4: objeto 0x143cf1b0 inicialmente con vtable 0x6a70b930,
método 0x69d85b20, reads=7 y pertenencia/ejecución Steam=1. En seq 57,
elapsed_ms 91185, Unix 1794627536, el objeto sigue 0x143cf1b0, pero vtable pasa
a 0x143c0070 y método a 0x656e6967, reads=7 y pertenencia/ejecución=0.
El snapshot padre es sample seq 56. La correlación con PID/base ASLR y comandos
está en su trial.json y trace-summary.json. Más adelante aparecen métodos nulos.

reads=7 significa que las tres copias de memoria tuvieron éxito, no que la
interfaz siga viva. Tampoco se confunde el contexto nulo al cerrar C0 con
la cadena fuera de módulo observada después del mapa en C1.
Las copias ReadProcessMemory no son atómicas; no prueban liberación, identidad
definitiva de la interfaz ni causalidad. El observador nunca invoca esos punteros.
LevelInit/LevelShutdown pre/post no son límites de cada llamada interna Steam.
Puede perder transiciones entre frames o anteriores al fallo. Flush del buffer C
no equivale a persistencia garantizada ante corte eléctrico. La rotación de 5 MiB
con un respaldo se probó en fixture; las trazas de servidor no alcanzaron ese tamaño.

## Captura CDB posterior a la matriz

Ensayo adicional **A1_cdb**, PID servidor 28132, vanilla LAN 1.
CDB x86 PID 25916 se adjuntó tras la primera actividad y antes del mapa;
se esperó CAPTURE_READY antes de liberar el cambio de mapa.
Los filtros continuaron con `gn`, nunca trataron la excepción como manejada.

Hubo un Assert Dialog de WebUI: UpdateTextFilterDictionary ya registrado.
Se pulsó **Omitir** en el diálogo del servidor propio durante el mapa, lo que
desactiva posteriores diálogos de assert de ese proceso. Se conserva hora e
intervención en external_instrumentation; no cambió los filtros de excepciones.
Esto distingue el ensayo instrumentado de los 18 controles. El primer directorio
de símbolos local no existía al iniciar CDB; la captura continuó sin símbolos.
El análisis offline creó/usó el directorio y el helper ahora lo prepara.

Después de gameplay activo y kick:

1. Primera oportunidad c0000005, operación **execute (8)**, dirección **0**,
   EIP 0. Retorno inmediato a **server.dll+0x1e1226** (base 0x68650000).
2. Otra primera oportunidad c0000005 durante el cierre: **read (0)** de
   **0x15a55e48**, EIP **0x6b951316 = engine.dll+0x161316**,
   base engine 0x6b7f0000. ECX 0x15a55d78;
   instrucción `mov eax,dword ptr [ecx+0D0h]`.
3. Segunda oportunidad final: la misma lectura inválida en engine+0x161316.
   El proceso real terminó con c0000005, handle señalado y códigos concordantes.

Se guardaron dump de la primera excepción y dump de la segunda oportunidad final.
`analysis/first_chance.json`, `final_second_chance.json` y `capture-summary.json`
incluyen registros, pilas saneadas y hashes/rutas de los dumps privados.
La pila final pasa por llamadas de descarga del loader; no se atribuye la causa
a la última DLL ni se convierten exports cercanos con desplazamientos enormes
en nombres de funciones internas. Sin símbolos privados de Valve, el unwind
tiene límites. No se observó c0000409 en esta serie ni se asigna un subcódigo
a los casos históricos c0000409 o a partir de un fixture.

## Pilotos excluidos y correcciones del recolector

Se conservan cinco pilotos fuera de los 18, en `excluded-pilots/`:
preflight_C0 (heartbeat en hibernación), A1_1 (scrollback duplicaba userid),
A1_r1 y B0_r1 (antes de endurecer el gate active), C1_r2 (respuesta inicial
de consulta aún vacía; observador realmente estaba en 2 al volver a consultar).
Se corrigió el parseo a la última respuesta status, se exigió active y se esperó
la respuesta de la ConVar hasta 10 s; C1_r2b es su repetición válida.
Los pilotos con intervención quit o errores no se contabilizan como controles PASS.
Sus fuentes/revisiones e incidencias quedan en sus JSON y evidencia privada.

## Restauración y entrega

Servidor y CDB propios detenidos. El cliente del usuario quedó abierto en el menú.
Antes de los cambios se respaldaron y verificaron 1.207 archivos cfg/addons en
un ZIP privado de 73.087.778 bytes. Al finalizar coincidieron exactamente el
conjunto de archivos regulares y cada SHA-256 original. Los archivos generados
se archivaron privadamente antes de retirarlos. La DLL diagnóstica no está instalada;
no hay autoload suyo. La fuente conserva el predeterminado solicitado 2.
SteamClientDll HKCU volvió al valor y tipo originales y se volvió a comprobar.
La certificación no abarca metadatos ni directorios vacíos.

`restoration/restoration-result.json` y `final-audit.json` conservan comprobaciones,
hashes críticos y espacio. Los manifiestos protegidos pasaron: entrada 4 archivos,
investigacion-cierre 31 y validacion-orden-carga 67. Las instalaciones del juego
y del dedicado siguen presentes; no se afirma rehash de todos sus assets.

Se conserva evidencia privada en
`C:\Users\israe\Documents\Codex\2026-11-13\tene\work\steam-debug-private`:
estados y consolas, respaldo original, residuos archivados, capturas CDB y dumps.
Punto de resume: `trials`, `cdb`, `original-inventory.json`, `restoration-result.json`;
no ejecutar de nuevo una restauración sobre evidencia ya archivada.
La instantánea previa al empaquetado ocupa aproximadamente 1,29 GB lógicos en
esa carpeta; SDK/dependencias 0,294 GB y evidencia histórica shutdown-private
2,96 GB, conservada. Espacio libre al auditar: C: ~1.011 GB, D: ~541 GB decimales.
Los JSON registran bytes exactos y limitan esa medición al momento de la captura.

La entrega incluye DLL/PDB separados, build, JSON/trazas saneadas, análisis,
fuentes exactas nuevas, bundle incremental y patches sobre la base especificada.
La reconstrucción independiente y el árbol final se certifican en
`reconstruction-verification.json`; la revisión final está fuera del historial
en `REVISION_FINAL.json` para evitar una autorreferencia de commit.
Para reconstruir los bytes exactos del overlay, usa `core.autocrlf=false` en
el repositorio nuevo antes del checkout o extrae `codigo-fuente.zip`.
La primera comprobación detectó conversión CRLF de C++ con el valor global
true de Git para Windows; el árbol Git ya coincidía, pero esa conversión impedía
comparar bytes con el ZIP. La verificación final desactiva la conversión solo
en sus repositorios privados; no cambia la configuración global del usuario.
El manifiesto SHA-256 incluye este informe, DLL, PDB, fuentes y evidencias.
No se exportaron dumps, consolas crudas, identidades de jugador ni runtime Valve.
No se añadió publicación o despliegue de producción.
