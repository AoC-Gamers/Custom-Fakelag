# Referencias SDK y runtime

Actualizado: 2026-11-13. Existe un adaptador real para **un módulo Linux x86
identificado**. Otros motores, Windows incluido, conservan el rechazo controlado
de activación. No hay una ConVar que salte esta comprobación.

## Identidad del motor soportado

- Juego: L4D2 `2.2.4.3`, Steam build `23990100`; exe build `10097`,
  `Jun 30 2026 18:39:58`.
- Módulo: ELF32 i386 `engine_srv.so`.
- SHA-256: `8f8093a18bba14cb73fc11589687bfb8156b00328b7413d697f1a76ed4b7621a`.
- GNU build ID: `b152439170af081a0d31fc357364a4cd4caa56ac`.
- Procedencia: `serverfiles/bin/engine_srv.so` del volumen local de Vanilla,
  montado en modo lectura durante las pruebas.
- [Manifiesto con símbolos, offsets y capacidad](runtime/linux-engine-2.2.4.3.json).

El adaptador verifica en runtime ELF32/EM_386, build ID, dirección efectiva de
`NET_LagPacket`, dirección efectiva de `net_time` y representación del SDK.
Después restringe captura/restauración a entradas de la tabla nativa
`net_packets`, sockets 0–2 y buffers alineados. Un destino ajeno a esa tabla tiene
capacidad cero y se delega al motor original. El manifiesto registra SHA-256 para
la auditoría offline; la comprobación dentro del proceso utiliza el build ID y
las direcciones verificadas, no una certificación criptográfica contra módulos
hostiles que falsifiquen su identidad.

## Contrato observado en el binario

Desensamblado directamente del módulo identificado, no inferido de netprops:

| Función/símbolo | RVA |
|---|---:|
| `NET_LagPacket(bool, netpacket_s*)` | `0x1b36b0` |
| `NET_GetPacket(int, unsigned char*)` | `0x1b7350` |
| `NET_ProcessSocket(int, IConnectionlessPacketHandler*)` | `0x1b7470` |
| `NET_ReceiveDatagram(int, netpacket_s*)` | `0x1b6870` |
| `NET_GetLoopPacket(netpacket_s*)` | `0x1b3a40` |
| `CBitRead::StartReading(void const*, int, int, int)` | `0x2476e0` |
| `net_time` (`double`) | `0x39c140` |
| `_ZL11net_packets` (puntero a tabla) | `0x39c4d0` |

Convención de llamada: función libre cdecl i386, argumentos bool/puntero en pila.
El stride nativo de paquete es 80 bytes, alineación 4. Campos observados:
`from=0`, `source=12`, `received=16`, `data=24`, `message=28`, `size=64`,
`wiresize=68`, `stream=72`, `pNext=76`. `netadr_t` ocupa 12 bytes y el lector 36.
Los checks de tamaño/alineación son static_asserts Linux x86; se comprueban los
campos usando direcciones de un objeto SDK real, sin packing ni `offsetof` sobre
un tipo no standard-layout.

`NET_ProcessSocket` asigna `0x37ab8` bytes: cabecera de freelist de 8 y buffer
`0x37ab0`. Pasa `bloque+8` a `NET_GetPacket`, que lo coloca en `packet.data`.
Es el caller directo observado de `NET_GetPacket`. `NET_ReceiveDatagram` utiliza
esa misma capacidad en recepción. La capacidad no se deduce de `size` ni de la
longitud del lector. Los límites internos de la cola siguen siendo independientes.

En `NET_GetPacket`, tanto las rutas de datos nuevos como la ruta
`NET_LagPacket(false, packet)` convergen en `0x1b7400`. En `0x1b7424` el caller
invoca `CBitRead::StartReading(data, size, 0, -1)` antes de devolver un paquete
válido. El lector en el punto del hook puede ser viejo o no estar preparado;
por ello **no se captura ni se restaura su memoria**. Se conserva payload y
metadatos escalares; el caller reconstruye todos los punteros del lector a partir
del buffer vivo. Esto también vale cuando `newdata=false`, con `size` inicialmente
cero pero una asignación completa disponible.

La restauración nativa de `NET_LagPacket` escribe `net_time` actual en `received`.
El adaptador reproduce esa semántica ahora verificada. La hora original queda
en el paquete propietario y `releaseAt` sigue siendo independiente.

## SDK y límites de plataforma

SDK usado: AlliedModders HL2SDK rama `l4d2`, revisión
`2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6`:

- [Paquete](https://github.com/alliedmodders/hl2sdk/blob/2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6/public/inetchannel.h).
- [Lector](https://github.com/alliedmodders/hl2sdk/blob/2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6/public/tier1/bitbuf.h).
- [Dirección](https://github.com/alliedmodders/hl2sdk/blob/2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6/public/tier1/netadr.h).

En esta revisión `bf_read` deriva de `CBitRead`. La documentación antigua que
separaba `old_bf_read` en Linux y `CBitRead` en Windows no corresponde a este SDK.
Los punteros internos se reconstruyen mediante el caller comprobado, no copiando
un lector ni cambiando un único supuesto `m_pData`.

El [catálogo ELF de L4D2node](https://binaries.l4d2node.org/) fue una referencia
inicial, pero tiene direcciones distintas y no sustituye al binario local
identificado. Sus tipos de Ghidra no son autoridad automática. Las netprops son
SendTables y no describen el layout de paquetes.

No existe `engine.dll` objetivo disponible. Steam negó la descarga anónima del
depot Windows y el usuario confirmó que no está descargado y hay restricciones
de espacio. No se descargó el servidor completo. Windows se compila y prueba en
CI, pero **no se habilita el adaptador** ni se certifican sus patrones o ABI.
Gamedata no necesitó cambios: la resolución efectiva Linux existente fue
comprobada al cargar y activar el detour en SRCDS. Patrones Windows siguen
pendientes de identidad, unicidad y resolución efectiva.

Para admitir otro módulo se debe registrar su identidad, verificar callers,
capacidad y lector, extender explícitamente el adaptador y repetir pruebas.
Cambiar únicamente `IsRuntimeValidated()` a true sigue siendo incorrecto.

Matriz y evidencia: [informe de integración](ENGINE_INTEGRATION_VALIDATION.md).
