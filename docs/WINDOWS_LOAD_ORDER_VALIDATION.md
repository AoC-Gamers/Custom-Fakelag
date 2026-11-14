# Aceptación Windows: carga y recarga con Left4DHooks activo

> Informe histórico de las revisiones indicadas. Estado vigente y pendientes:
> [matriz de validación](VALIDATION.md). La política LAN actual y el debug
> apagado por defecto no se atribuyen retroactivamente a estos ensayos.

Prueba ejecutada el 13-11-2026 con un cliente Steam real. **La aceptación funcional
pasó en ambos órdenes de carga. El cierre completo del proceso no queda aprobado.**
No se modificó el comparador de producción ni se amplió la excepción de código.

## Revisión y procedencia

El checkout comenzó limpio en `feat/windows-engine-validation`,
`c5a75790c5d177b8ae751c1d73bdaf3e7571575d`. Se creó
`test/windows-load-order` y se avanzó por fast-forward al develop descargado,
`9c7debcf334ef534d715449b828e0c6d5fa67853`. Ese es el código de producción de las
DLL probadas. No había correcciones locales que descartar. El fetch usó HTTPS
con puerto 443 para evitar la regla global que convierte HTTPS en SSH; no se
cambió la configuración Git del usuario.

Las herramientas usadas para las pruebas runtime se fijaron en
`3cb8c41b6edeedd8a5358ae07e60ea07a55ce03b`. El commit final de documentación y la
rama exacta entregada se registran en `REVISION_FINAL.json` junto al bundle;
así no se intenta incluir el hash de un commit dentro de su propio contenido.
La base de integración del bundle/patches es exactamente `9c7debc`.

Resultados estructurados: [windows-load-order-2026-11-13.json](runtime/windows-load-order-2026-11-13.json).
Las secuencias completas saneadas están en `evidence/*.jsonl` de la entrega:
comando, PID, hora, consola, módulos realmente cargados, hashes, bytes y regiones.

| Componente | Versión o identidad comprobada |
|---|---|
| Windows | 11, 10.0.26300 |
| MSVC x86 | 19.44.35230.0; directorio de herramientas 14.44.35207 |
| Build Tools / SDK | VS 2022 17.14.45 / SDK 10.0.26100.0 |
| SourceMod / DHooks | 1.12.0.7260 / 1.12.0.7260 |
| Metamod | 1.12.0-dev+1229 |
| Left4DHooks | 1.175; fuente `7672bdefc4e03a693ae7fdc06e470df41b4cc069` |
| Motor | L4D2 2.2.4.3, exe 10097, Steam server build 23990100, PE32 I386 |

SHA-256 del motor antes/después:
`8a6d468059394bf4cfce32f11dcba12ef45de88da1373084d5a2916d0bf7ba86`.
La sesión final cargó realmente
`D:\SteamLibrary\steamapps\common\Left 4 Dead 2 Dedicated Server\bin\engine.dll`.
Se usó la instalación descargada por el usuario desde Steam, manteniendo addons,
configuración y archivos escribibles en la instancia privada anterior.

| Artefacto | SHA-256 |
|---|---|
| DLL normal | `3e062b7047baad8551c5bd384fa18f9727735418ad917f60a04d155589165a73` |
| DLL observadora opt-in | `a4c24e0343333fa7f9a4d798735d407823219206677a217df796ecca8d554f04` |
| Left4DHooks SMX | `a5097583f718a58b249bec7aa2f7d019b03a9d70bb148dc4dbdc4646b43a1105` |
| DHooks DLL | `f2e44969b84f6b0c090187074f9eb9dcf46b8491a282838760f64add34bfdcb3` |

Los hashes de extensión provienen también de la ruta del módulo cargado. La DLL
normal contiene cero comandos `cf_probe_*`; la observadora contiene cinco. El
plugin de aceptación se recompiló explícitamente, está identificado en el JSON y
queda fuera del paquete normal. Las primeras pruebas usaron el SMX conservado de
la entrega anterior; la reconexión y el orden inverso repitieron los 17 casos con
el SMX recompilado desde `tests/windows_public_api.sp`.

## Pruebas aisladas y negativas

Suite portable MSVC: exit 0. Arnés SDK `-BuildOnly`: exit 0, solo compilación.
Arnés SDK ejecutado con ASan: **39 PASS, exit 0**. No hubo warnings en esas
compilaciones SDK. El build normal y el observador terminaron con exit 0; se
conservan sus logs, incluidos avisos de dependencias y opciones del compilador.
ASan acredita el ejecutable/adapter instrumentados, no SRCDS ni todas sus DLL.

El PE se mapeó con `DONT_RESOLVE_DLL_REFERENCES`, sin ejecutar DllMain/código del
motor. Ningún caso negativo parcheó el servidor vivo ni archivos de Valve. Se
restauraron bytes, protecciones, tabla, reloj y asignaciones antes de salir.

| Caso | Cobertura ejecutada | Resultado |
|---|---|---|
| Imagen exacta | SDK real + portable | Aprobado |
| E9 externo ejecutable, aceptación repetida sin reescribirlo | SDK real + portable | Aprobado |
| Destino no ejecutable, no legible, inaccesible o inválido | SDK real + portable | Rechazado como se esperaba |
| Opcode arbitrario | SDK real + portable | Rechazado como se esperaba |
| E9 permitido más cambio de NET_LagPacket | SDK real + portable; byte alterado conservado durante el rechazo | Rechazado como se esperaba |
| Sexto byte, anterior, recepción, lector y operando net_time | SDK real; portable añade todos los callers del contrato | Rechazado como se esperaba |
| Salto nulo, bucle o destino interno | SDK real + portable | Rechazado como se esperaba |
| Original inesperado, rango inválido o excepción parcial | Comparador portable usado por producción | Rechazado como se esperaba |
| Arquitectura/cabecera cargada incompatible | SDK real | Rechazado como se esperaba |
| Dirección no soportada, módulo/clock ajenos o NaN | SDK real | Rechazado como se esperaba |
| Archivo de identidad desconocida | Copia ordinaria alterada, proceso SDK nuevo | Rechazado por SHA-256, exit 4 esperado |
| rel32 con wrap i386 | Portable x86 | Aprobado |

La última prueba de identidad necesita el entorno MSVC/ASan y las DLL SDK en PATH.
Una primera invocación sin ese PATH falló al iniciar; se repitió correctamente y
el resultado conservado distingue ese problema del rechazo de identidad.

## Left4DHooks primero: PID 10216

Left4DHooks era el plugin 14, DHooks la extensión 8 y SourceMod permaneció activo.
Antes de cargar Custom-Fakelag se observó FillServerInfo con E9 real hacia una
región externa comprometida y ejecutable/legible (`MEM_COMMIT`, protección `0x40`).
Custom-Fakelag emitió ambos diagnósticos requeridos: `Packet adapter accepted` y
`compatible FillServerInfo entry detour accepted`.

| Build | Recargas consecutivas con perfil humano activo | Cola antes de retirar dependientes |
|---|---:|---|
| Normal | 3 | Perfil 5000 ms activo; el build normal no expone contadores |
| Observador | 3 | 73, 73 y 71 paquetes observados respectivamente |

La primera descarga usó el ID efectivo 10; después, al quedar BuiltinVotes antes,
Custom-Fakelag pasó al 11. Se consultaron las listas por ciclo. Solo se retiraron
`player_fakelag` y el plugin de aceptación antes de descargar Custom-Fakelag.
No hubo descarga, pausa, reemplazo ni reinicio de Left4DHooks/DHooks/SourceMod.
Se aplicaron, consultaron y limpiaron perfiles y se repitieron API y tráfico.

En todo el intervalo parcheado del PID, FillServerInfo conservó exactamente
`e9 55 c3 16 fe` y su sexto byte `57`. NET_LagPacket fue `55 8b ec 51 57` sin
perfil, E9 al activar el hook y otra vez original al retirarlo. En cada descarga
el módulo Custom-Fakelag desapareció realmente de la lista de módulos. La nueva
extensión comenzó sin perfiles/colas de la generación anterior.

## Orden inverso, mapa y API: PID 21292

Se inició un proceso nuevo con la DLL normal y sin Left4DHooks: entrada
FillServerInfo `55 8b ec 53 56 57`. Luego se cargó Left4DHooks, plugin 17, y se
observó `e9 55 c3 2e ff 57`. Ese salto quedó idéntico durante todas las operaciones
posteriores del PID. No se compara con el salto del PID anterior.

Con el cliente real se completó una recarga normal antes del mapa. El observador
se instaló únicamente tras comprobar la descarga del módulo normal. Con ambos
activos y el plugin de persistencia retirado se cambió de `c1m1_hotel` a
`c1m2_streets`: se observaron 75 paquetes / 5486 bytes antes, y después cero
perfiles, paquetes, bytes y estados de pérdida; descartes de ciclo de vida 98.
El cliente volvió al mapa sin perfil anterior. Pasó otra recarga del observador
con 72 paquetes pendientes antes de retirar los dependientes. Después se volvió
a la DLL normal y se repitieron carga, aplicación y una recarga posterior al mapa.

Las direcciones observadas siempre fueron base ASLR + `0x1c9ba0` para
NET_LagPacket y base + `0x6b2b48` para net_time. Los registros guardan la base,
direcciones, destino E9 y permisos efectivos, junto al hash del módulo cargado.

En conjunto hay **17 ejecuciones completas de los 17 checks API: 289 comprobaciones,
cero fallos**. Incluyen Handled/Stop en perfiles nuevos/existentes, modificación
permitida, excepción real de callback, entrada y Action inválidas, reentrada,
modos native/ConVar y reset idempotente. Las excepciones deliberadas del arnés
quedan como evidencia, no como fallos inesperados. `player_fakelag` pasó aplicación,
consulta y limpieza repetidas desde el contexto del cliente real.

La pérdida Bernoulli/GE, el tramo 100 % y el reset con pendientes se controlaron
por consola privada. Los contadores separan pérdida solicitada, saturación,
restauración y ciclo de vida. Se observaron pérdidas solicitadas y cero fallos de
restauración/saturación. Los ejemplos con 120 ms retienen aproximadamente 138 ms
según el reloj del motor y el frame; **no son RTT ni medidas de net_graph**.

## Desconexión y reconexión reales

En PID 10216 se retiró primero el plugin normal para impedir su persistencia
intencional. Con perfil de 5000 ms, usuario de sesión 2 y 47 paquetes observados,
se ejecutó `kickid` desde el servidor. Se observaron cero perfiles/colas/bytes y
contador de ciclo de vida 96. El mismo cliente volvió al slot 1 con usuario de
sesión 7, sin perfil. La comprobación se repitió seis segundos después y permaneció
vacía. Esta es una desconexión real iniciada por el servidor; no se presenta como
un `retry` exitoso del cliente. No se conservan SteamID, nombre ni WAN.

## Incidencias de entorno y preservación

El arranque directo que usaba la biblioteca de Steam de escritorio registraba el
servidor como el juego 550 e impedía reabrir el cliente. Forzar AppId 222860 lo
separó visualmente, pero produjo `ticket for the wrong game`: esos intentos
**fallaron y no cuentan como aceptación humana**. El arranque mediante Steam
también reprodujo ese rechazo. La instalación nueva tiene el mismo motor; una
descarga distinta no justificaba cambiar su contrato.

La sesión final mantuvo AppId 550 y cargó el `steamclient.dll` oficial de `bin`
del dedicado. Para seleccionar esa biblioteca, el launcher cambió temporalmente
`HKCU\Software\Valve\Steam\ActiveProcess\SteamClientDll` durante el arranque y
restauró el valor original en `finally` inmediatamente después de observar la
carga. Se verificaron módulo y valor restaurado. Es un cambio temporal por usuario,
no una modificación permanente de Steam. No se debe iniciar/reiniciar otro cliente
durante esa breve selección. El script y recibos hacen explícita esta operación.

No se cerró el cliente del usuario ni se cambiaron firewall, router o credenciales.
Se reutilizaron instancia, dependencias y recursos anteriores. La instalación
completa en D: fue descargada por el usuario; el agente no volvió a copiar el juego.

El inventario antiguo presenta dos sprays con igual tamaño y fecha de modificación
distinta. No había hash histórico para certificar su contenido anterior. Las fechas
volvieron a cambiar coincidiendo con arranques del cliente; no se estableció una
atribución mediante captura de escrituras. No se sobrescribieron sus
archivos para intentar restaurar una versión desconocida. Se corrigió la preparación
para separar los sprays escribibles en copias privadas. El inventario actual conserva
57807 hardlinks / 13440077380 bytes lógicos y cero diferencias de tamaño/mtime en
sus fuentes inmutables. Esta comprobación no equivale a un hash de todo el juego.

## Cierre y límites

| Sesión | Resultado del cierre |
|---|---|
| Humana, Left4DHooks primero, PID 10216 | Falló: `3221226505`, `0xc0000409` |
| Humana, orden inverso/runtime dedicado, PID 21292 | Falló: `3221225477`, `0xc0000005` |
| Nueva sesión normal sin cliente, PID 28596 | Exit 0 |
| Nueva vanilla sin Metamod/SM/Custom-Fakelag, PID 30552 | Exit 0 |

La vanilla nueva no reproduce el cierre de las sesiones humanas; la evidencia
vanilla de la entrega anterior sí había registrado `0xc0000409`. No se afirma
que todos los cierres fallen ni que el fallo esté resuelto. Su causa permanece
abierta y no se atribuye a esta excepción por compartir un código de salida.

La [investigación posterior del cierre](WINDOWS_SHUTDOWN_INVESTIGATION.md)
reprodujo un fallo del ciclo de vida de interfaces Steam en vanilla tras cambiar
de mapa con `sv_lan 1`. La intervención `sv_lan 0` evitó esa reproducción y
restaurar LAN 1 la reintrodujo. Esto no recupera el subcódigo ni demuestra la
causa de los antiguos `0xc0000409`; los resultados de esta entrega permanecen
históricos y separados de los nuevos ensayos.

No se repitió un runtime Linux en este encargo, ni se desplegó en servidores de
uso real, ni se creó PR/push. La aprobación funcional se limita al motor exacto
y versiones registrados. Los casos aislados, el build y el cliente real se
mantienen separados en la evidencia.

## Repetición y entrega

Compilar con las dependencias existentes y el venv `.deps/exts-windows/.venv-native`,
usando los scripts PowerShell, sin el `make` BusyBox del PATH:

```powershell
pwsh -NoProfile -File scripts/run-windows-tests.ps1
pwsh -NoProfile -File scripts/test-windows-sdk-contract.ps1 -BuildOnly
$env:CUSTOM_FAKELAG_ASAN = '1'
pwsh -NoProfile -File scripts/test-windows-sdk-contract.ps1 -EnginePath '<dedicado>\bin\engine.dll'
Remove-Item Env:CUSTOM_FAKELAG_ASAN
pwsh -NoProfile -File scripts/build-windows-l4d2.ps1
```

Arrancar con `scripts/start-windows-load-order-session.ps1`, pasando Python,
Srcds, Game privado marcado, Commands vacío y Output explícitos. El script guarda
un recibo de la selección/restauración de runtime. Añadir comandos a Commands;
`@snapshot` solo observa y `@wait N` espera como máximo diez segundos. Consultar
IDs reales antes de cada descarga. Para contadores usar un build separado con
`CUSTOM_FAKELAG_ENGINE_HARNESS=1`; nunca ejecutar `cf_probe_profile` durante la
fase humana, porque sustituye el resolver por uno sintético.

Exportar con `tests/export_windows_load_order.py`. El resumen ayuda a revisar las
secuencias; no convierte automáticamente una carga en aceptación funcional.
La entrega contiene DLL normal, observador/SMX separados, logs saneados,
herramientas, bundle/patches y manifiesto SHA-256; no contiene binarios de Valve
ni dumps. La copia anterior de la DLL está identificada y conservada por separado.

Estado final comprobado: ningún `srcds.exe` activo, DLL normal instalada en la
instancia privada, plugin de aceptación deshabilitado, Metamod restaurado,
Left4DHooks y player_fakelag habilitados en disco y registro Steam restaurado.
