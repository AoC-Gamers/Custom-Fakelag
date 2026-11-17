# Política de fakelag en LAN

`sv_lan 1` bloquea los perfiles nuevos de latencia o pérdida por defecto.
`sm_custom_fakelag_allow_lan` vale 0; asignar 1 permite pruebas explícitas en LAN.
El permiso no cambia la comprobación de identidad/capacidad del motor.

| sv_lan | allow_lan | Resultado |
|---|---|---|
| 0 | 0 o 1 | Permite perfiles nuevos explícitos |
| 1 | 0 | Bloquea y limpia el estado anterior |
| 1 | 1 | Permite pruebas explícitas |

Al entrar en el bloqueo se borran perfiles, paquetes retenidos y estados de
pérdida. La limpieza no se puede vetar desde el forward de latencia. Se intenta
retirar el detour incluso en always-on; si falla la protección/restauración,
se informa el fallo, se conserva la infraestructura y la política delega los
paquetes al motor sin simulación. Reset permite reintentar la retirada.
No se libera un hook cuya retirada no esté confirmada.

Salir del bloqueo, tanto mediante LAN 0 como mediante allow_lan 1, no reproduce
perfiles ni colas guardados. Es necesaria una solicitud nueva. La extensión
observa los cambios globales de ConVars sin sustituir el callback de sv_lan.
Los cambios reentrantes de política se concilian en el frame siguiente;
la admisión de perfiles y el procesamiento de paquetes consultan la política
efectiva, no solo el estado de la última notificación.

## API y plugin

`CFakeLag_IsLanBlocked()` informa la restricción efectiva. Una asignación no
nula bloqueada lanza un error nativo específico; consultas, clear y reset siguen
disponibles. `CFakeLag_IsClientSupported()` conserva su significado de tipo y
elegibilidad del cliente. Una limpieza de política emite razón
`CFakeLagChange_LanPolicy` (valor nuevo 3; los anteriores conservan sus valores).

`CFakeLag_OnLanPolicyChanged(bool blocked)` avisa después de limpiar perfiles.
Todos los consumidores que mantengan persistencia deben descartarla al recibir
blocked=true. El plugin incluido borra sus tres StringMaps, snapshots de cambio
de modo, marcadores de desconexión y voto pendiente, incluidos datos de clientes
ya desconectados. Los callbacks pendientes quedan sin perfiles que restaurar;
se descartan también notificaciones antiguas que ya no coincidan con el perfil
activo. Volver a LAN 0 no solicita restauraciones.

Se deben actualizar extensión, include y plugin juntos. Los plugins compilados
contra la nueva consulta requieren esta versión de la extensión.

## Validación

La suite C++ comprueba limpieza con cola activa, pérdida y latencia bloqueadas,
excepción de pruebas y su retirada, prioridad sobre always-on, bypass de
paquetes nuevos/retenidos, fallo/reintento de retirada, veto de forward,
reentrada y cambios LAN durante el forward, y ausencia de restauración al
volver a LAN 0. La compilación Linux32 con ASan/UBSan, extensión ELF32, plugin
normal y consumidores SourcePawn se comprueban separadamente del runtime.

No se presenta esta política como un arreglo del fallo de Steam ni se atribuyen
los ensayos Windows anteriores a estos cambios nuevos. La aceptación en SRCDS
debe verificar las transiciones en caliente, colas/GE, retirada y vuelta de la
excepción, reset, persistencia de un cliente desconectado y callbacks/votos
pendientes. En LAN 1 los ensayos anteriores con perfiles necesitan activar
allow_lan expresamente; no se debe interpretar su rechazo por política como
fallo del adaptador.
