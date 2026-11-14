# Estado y evidencia de validación

Actualizado: 14-11-2026. Este índice consolida las revisiones de entregas;
los informes y JSON originales conservan su carácter histórico. Sus resultados
no se atribuyen automáticamente a commits posteriores.

## Estado actual

| Área | Evidencia disponible | Límite |
|---|---|---|
| Linux x86 | Build, ASan/UBSan y 17 checks SRCDS con UDP real | Perfil sintético; gameplay Steam pendiente |
| Windows x86 | Build, fixture nativo, UDP, API y sesiones con cliente real | Solo motor y versiones identificados |
| Left4DHooks activo | Ambos órdenes, recargas, reconexión y mapa en Windows | Excepción de código acotada; no soporte genérico de hooks |
| Diagnóstico Steam | Compilación/fixture en ambas plataformas; 18 ensayos Windows | DLL histórica probada con predeterminado 2; actual 0 |
| Política LAN | Regresiones de bloqueo, limpieza, excepción y no restauración; CI | Aceptación de esta política en SRCDS pendiente |
| Cierre completo | Reproducción vanilla/SM/observador dependiente de LAN | No hay fix del motor; antiguos c0000409 sin atribución completa |

La [política LAN](LAN_POLICY.md), commit `2c9312d`, tiene
[CI Linux/Windows/SourcePawn aprobado](https://github.com/AoC-Gamers/Custom-Fakelag/actions/runs/43560988242).
El diagnóstico actual carga apagado (`sm_steam_lifecycle_debug=0`, cambio
`de0add0`); su [CI](https://github.com/AoC-Gamers/Custom-Fakelag/actions/runs/43559336843)
compila y ejecuta fixtures, no prueba ese nuevo predeterminado dentro de SRCDS.
Los artefactos del diagnóstico están separados del paquete normal.

## Informes y datos

| Tema | Informe | Datos |
|---|---|---|
| Seguridad inicial: propiedad, colas y pérdida | [Seguridad](FAKELAG_SAFETY_VALIDATION.md) | Reproducer y suite en tests/ |
| ABI, capacidad y lector | [SDK/runtime](SDK_RUNTIME_REFERENCES.md) | [Linux](runtime/linux-engine-2.2.4.3.json), [Windows](runtime/windows-engine-2.2.4.3.json) |
| 17 checks Linux | [Integración Linux](ENGINE_INTEGRATION_VALIDATION.md) | [Probe](runtime/linux-probe-2026-11-13.json) |
| 32 checks UDP y 17 API Windows iniciales | [Adaptador Windows](WINDOWS_ENGINE_VALIDATION.md) | [Runtime](runtime/windows-runtime-2026-11-13.json) |
| Left4DHooks: 17 ejecuciones API, 289 comprobaciones | [Carga/recarga](WINDOWS_LOAD_ORDER_VALIDATION.md) | [Registro](runtime/windows-load-order-2026-11-13.json) |
| Investigación de cierre: 35 controles y 10 extendidos | [Causa y límites](WINDOWS_SHUTDOWN_INVESTIGATION.md) | [Ensayos](runtime/windows-shutdown-investigation-2026-11-13.json), [contextos](runtime/windows-shutdown-evidence-2026-11-13.json), [logs](runtime/windows-shutdown-logs-2026-11-13.jsonl) |
| Observador: matriz de 18 procesos Windows | [Debug Steam](WINDOWS_STEAM_DEBUG_VALIDATION.md) | [Matriz](runtime/windows-steam-debug-matrix-2026-11-14.json) |

El catálogo ELF externo es una referencia, no prueba del ABI de un binario
Windows. Las netprops describen SendTables, no paquetes ni contextos Steam.
Un build correcto o un fixture SDK no certifican funcionamiento con jugadores.

## Qué se sabe del cierre

Con el motor probado, LAN 1 falló 9/9 después de mapa y desconexión y LAN 0
reconectó/cerró con salida 0 en 9/9; mismo resultado en vanilla, SM mínimo y SM
con observador. En los tres ensayos diagnósticos LAN 1, las cadenas dejaron de
pertenecer a steamclient después del mapa. La investigación previa observó
invalidación durante SteamGameServer_Shutdown y uso posterior por server.dll.

Se distinguen primera excepción (ejecución inválida con retorno a
server+0x1e1226) y detección posterior durante teardown (engine+0x161316).
Las muestras no atómicas y los nombres aproximados de pila no identifican por
sí solos el origen. El caso no necesita Custom-Fakelag ni Left4DHooks. Bloquear
fakelag en LAN es una política operativa, no una corrección del ciclo Steam.
Los antiguos c0000409 no tienen dumps/subcódigo suficientes para atribuirlos.

## Procedencia de las integraciones

Los bundles se verificaron y se integraron por fast-forward. Se conservaron
commits y autoría; no se importaron dumps, DLL/PDB ni runtime Valve al historial.

| Entrega Windows | Base → tip recibido | Archivos SHA-256 verificados |
|---|---|---:|
| Adaptador y API | 7c72156 → c5a7579 | 70 |
| Orden de carga | 9c7debc → 65031fb | 67 |
| Investigación de cierre | 65031fb → 3f63ba8 | 31 |
| Steam Lifecycle Debug | 070a71b → bf0882e | 75 |

SHA-256 de bundles de las revisiones consolidadas:

- Adaptador: `0efce19e82309e987ca0e517b444b9560e9c80b42ba3c06ec7c11d1765411262`.
- Cierre: `b3810a466e33c7297a9ea8d5897eae28652799e8b24c35ca9071faee60b80f86`.
- Diagnóstico: `a5d082dce4c2874e3328e5adb3427e7c6138431b51d34ec21443e46f2a2dbd4e`.

La DLL diagnóstica Windows probada era
`04c54a453f115dc59e7df3198cea51150c9aca5459d583d9bca97735c06997ca`.
Su PDB coincidió por GUID `1f8aa4a4-b60c-40bf-800a-1fcdbe3f19e3`, age 1.
Las diez fuentes locales iniciales coincidían con la entrega Windows.
Las verificaciones locales repitieron fixtures y builds en Linux; los ensayos
humanos Windows son evidencia recibida, no ejecuciones efectuadas desde Linux.

## Qué falta repetir

- Política LAN actual en SRCDS: transiciones, excepción, colas/GE, reset,
  persistencia de desconectados y callbacks/votos pendientes.
- Predeterminado 0 del diagnóstico en carga/recarga real; las pruebas históricas
  con predeterminado 2 siguen siendo históricas.
- Gameplay y reconexión Steam en Linux, y aceptación de cualquier nueva identidad
  del motor antes de habilitar su adaptador.
