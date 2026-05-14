# Referencias SDK y runtime

## Objetivo

Este documento resume que partes de `Custom-Fakelag` pueden tomarse con
confianza desde `hl2sdk-l4d2` y que partes dependen de validacion contra los
binarios reales del juego o del servidor dedicado.

Tambien deja constancia de una pasada concreta de verificacion hecha sobre:

- SDK local: `C:\GitHub\Custom-Fakelag\.deps\hl2sdk-l4d2`
- Servidor Linux: `linux`
- Servidor Windows: `windows`

## Mapa rapido

### Seguro con SDK

- `extension/extension.h`
- `extension/extension.cpp`
- `extension/latency/PlayerLatencyService.h`
- `extension/latency/PlayerLatencyService.cpp`
- `extension/latency/PlayerLatencyApiBridge.h`
- `extension/latency/PlayerLatencyApiBridge.cpp`

Estas piezas trabajan mayormente con interfaces publicas de SourceMod o del
engine, sin depender de layouts binarios fragiles.

### Mixto

- `extension/latency/PlayerLagManager.h`
- `extension/latency/PlayerLagManager.cpp`
- `extension/network/LagPacketPolicy.h`
- `extension/network/LagPacketPolicy.cpp`

Estas piezas usan interfaces publicas y logica propia, pero terminan
interactuando con datos o flujos que dependen del runtime real.

### Fragil o dependiente de runtime

- `extension/network/net_structures.h`
- `extension/network/LagSystem.h`
- `extension/network/LagSystem.cpp`
- `extension/NET_LagPacket_Detour.h`
- `extension/NET_LagPacket_Detour.cpp`
- `gamedata/custom_fakelag.games.txt`

Estas piezas dependen de:

- layout de `netpacket_t`
- layout de `bf_read`
- firma y calling convention de `NET_LagPacket`
- resolucion de `net_time`
- compatibilidad binaria real entre el codigo y el engine

## Revision de `net_structures.h` contra `hl2sdk-l4d2`

### `dumb_netadr_t`

`extension/network/net_structures.h` define:

- `netadrtype_t type`
- `unsigned char ip[4]`
- `unsigned short port`

Eso coincide con `netadr_t` en:

- `.deps/hl2sdk-l4d2/public/tier1/netadr.h`

La coincidencia es de campos y orden. La limitacion es que aqui no se reutiliza
directamente `netadr_t`, sino una copia minima de layout.

### `_netpacket_t`

`extension/network/net_structures.h` define:

- `from`
- `source`
- `received`
- `data`
- `message`
- `size`
- `wiresize`
- `stream`
- `pNext`

Eso coincide en orden y sentido con `netpacket_t` declarado en:

- `.deps/hl2sdk-l4d2/public/inetchannel.h`

Conclusion:

- la forma general del `netpacket_t` usado por la extension coincide con el SDK
- sigue siendo una zona fragil porque la extension hace copia material de la
  estructura y la trata como layout binario, no solo como interfaz

### `fake_bf_read`

`extension/network/net_structures.h` modela un subconjunto de `bf_read` con:

- `m_pData`
- `m_nDataBytes`
- `m_nDataBits`
- `m_iCurBit`
- `m_bOverflow`
- `m_bAssertOnOverflow`
- `m_pDebugName`
- tres ints extra: `m_BitRead0`, `m_BitRead1`, `m_BitRead2`

En `hl2sdk-l4d2/public/tier1/bitbuf.h`:

- en Linux, `bf_read` queda envuelto sobre `old_bf_read`
- en Windows, `bf_read` queda envuelto sobre `CBitRead`

Implicancia importante:

- `fake_bf_read` no representa una clase publica estable del SDK
- representa el layout concreto que la extension espera encontrar en runtime
- ese layout puede ser compatible con la build objetivo actual y aun asi no ser
  una garantia general del SDK

Conclusion:

- `net_structures.h` esta razonablemente alineado con el SDK para `netadr_t` y
  la forma de `netpacket_t`
- la parte mas riesgosa sigue siendo `fake_bf_read`, porque ahi la extension
  depende de layout binario real, no solo de headers publicos

## Revision de `NET_LagPacket` y `gamedata` contra binarios reales

### Windows

Binario revisado:

- `windows/bin/engine.dll`

Resultado de verificacion de firmas actuales:

- `NET_LagPacket` firma Windows encontrada en offset `0x1C8F70`
- `net_time` firma Windows encontrada en offset `0x1C913A`

Eso valida que las firmas declaradas hoy en:

- `gamedata/custom_fakelag.games.txt`

siguen apareciendo en el binario Windows revisado.

### Linux

Binario revisado:

- `linux/bin/engine_srv.so`

Resultado de verificacion textual:

- simbolo `_Z13NET_LagPacketbP11netpacket_s` encontrado en offset aproximado `0x379e51`
- cadena `net_time` encontrada en offset aproximado `0x37eb53`

Esto no equivale por si solo a una prueba completa de detour o resolucion de
direccion, pero si respalda que:

- el simbolo Linux esperado por `gamedata` existe en el binario revisado
- la referencia nominal a `net_time` tambien esta presente

### Limites de esta validacion

Esta pasada confirma:

- coincidencia razonable de `netpacket_t` con el SDK
- coincidencia razonable de `dumb_netadr_t` con `netadr_t`
- presencia de la firma Windows usada para `NET_LagPacket`
- presencia de la firma Windows usada para `net_time`
- presencia del simbolo Linux esperado para `NET_LagPacket`

Esta pasada no confirma por si sola:

- que `fake_bf_read` siga alineando exactamente con todos los builds objetivo
- que el offset de `net_time` resuelto por la firma sea semanticamente correcto
  en todas las versiones
- que no haya cambios de calling convention o prologo fuera de las firmas
- que el detour se comporte bien bajo carga real o con trafico de clientes real

## Recomendacion practica

Usar `hl2sdk-l4d2` como referencia principal para:

- nombres de interfaces
- firmas de metodos
- enums
- structs publicos

Y tratar siempre como validacion de runtime obligatoria:

- `net_structures.h`
- `LagSystem`
- `NET_LagPacket_Detour`
- `custom_fakelag.games.txt`

Cuando se toquen esas piezas, la validacion minima razonable deberia ser:

1. compilar Windows y Linux
2. verificar las firmas en los binarios actuales
3. cargar la extension en servidor real
4. probar fake lag con clientes reales o bots de trafico
