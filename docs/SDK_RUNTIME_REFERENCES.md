# Referencias SDK y runtime

Estado al 2026-11-13: **ABI no validado; activación del detour bloqueada**.
Esta rama permite compilar y probar la lógica, pero no está lista para desplegar
fake lag. `EnginePacketAdapter` rechaza captura/restauración, devuelve capacidad
cero y `IsRuntimeValidated() == false`. `LagDetour_Enable()` devuelve error antes
de modificar código del motor. La native propaga el error sin crear el perfil
ni emitir un forward de aplicación exitosa. En lazy la extensión puede cargar
si resuelve gamedata; always-on falla de forma controlada.

## Fuentes nuevas y alcance

Se contrastó el código con AlliedModders HL2SDK rama `l4d2`, revisión
`2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6`:

- [Paquete](https://github.com/alliedmodders/hl2sdk/blob/2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6/public/inetchannel.h).
- [Lector](https://github.com/alliedmodders/hl2sdk/blob/2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6/public/tier1/bitbuf.h).
- [Dirección](https://github.com/alliedmodders/hl2sdk/blob/2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6/public/tier1/netadr.h).

En esta revisión `bf_read` deriva de `CBitRead`; no existe una selección Linux
`old_bf_read` / Windows `CBitRead` como afirmaba la documentación anterior.
`CBitRead` contiene punteros internos de lectura que no pueden sustituirse
cambiando solamente un supuesto `m_pData`. El código nuevo no copia lectores,
usa `netpacket_t` del SDK como declaración candidata y mantiene el almacenamiento
propietario fuera de cualquier estructura ABI.

Un probe GCC 13.3 x86, sin packing añadido, produjo estos **valores del SDK**:

| Tipo | Tamaño | Alineación |
|---|---:|---:|
| puntero | 4 | — |
| `netadr_t` | 12 | 4 |
| `bf_read` | 36 | 4 |
| `netpacket_t` | 80 | 4 |

Offsets diagnósticos GCC: `from=0`, `source=12`, `received=16`, `data=24`,
`message=28`, `size=64`, `wiresize=68`, `stream=72`, `pNext=76`.
`netpacket_t` no es standard-layout según este compilador: el probe emitió
advertencias por usar `offsetof` en ese tipo. Los offsets son una observación
del compilador, no static_asserts portables ni prueba del motor.
No se añaden asserts ABI sin evidencia binaria.

Se consultó [L4D2node NET_LagPacket, ELF catalogado](https://binaries.l4d2node.org/b/engine_srv.so/f/0x001c3670).
El catálogo identifica `_Z13NET_LagPacketbP11netpacket_s`, dirección de catálogo
`0x001c3670`, `__cdecl`, y decompilación con accesos a `source +0xc`,
`received +0x10`, `data +0x18`, `size +0x40`, `pNext +0x4c`.
La restauración catalogada escribe `net_time` en `received` y copia payload;
no demuestra por sí sola la preparación del lector en los callers ni la
capacidad física del destino. Los tipos inferidos por Ghidra no son autoridad
sobre las declaraciones originales. No se traslada ese comportamiento a nuestro
`received` sin verificar el binario objetivo y sus callers.

No se obtuvo build del juego, SHA-256 ni build ID de un motor objetivo. No se
verificó una dirección efectiva de `net_time`, la unicidad de patrones Windows,
ni una resolución ELF efectiva. Por ello gamedata permanece **sin cambios**.
Los offsets textuales citados anteriormente para `windows/bin/engine.dll` y
`linux/bin/engine_srv.so` carecían de identidad verificable; se retiran como
certificación. Las netprops describen SendTables, no este layout de paquetes.

## Contrato obligatorio para habilitar una plataforma

Implementar un adaptador por ABI, respaldado por un manifiesto del módulo:
versión/build del juego, arquitectura, módulo, SHA-256/build ID, toolchain y
revisión SDK. La implementación deberá comprobar esa identidad antes de aceptar
`IsRuntimeValidated()`; no basta con cambiar su retorno a `true`.

1. Verificar firma y convención de `NET_LagPacket` y dirección/tipo de `net_time`.
2. Verificar tamaños, alineación y accesos a campos en el binario objetivo.
3. Seguir callers con `newdata=true/false`: campos válidos, procedencia y capacidad
   física de `data`, momento de inicialización del lector, longitud y cursor.
4. `Capture` entrega solo payload prestado y metadatos escalares válidos.
   `DestinationCapacity` obtiene capacidad de una fuente comprobada; ni `size`
   ni la longitud del lector son evidencia de capacidad.
5. `Restore` valida antes de escribir y reconstruye todos los punteros del lector
   mediante el contrato verificado. Si falla, no modifica destino ni payload.
6. Verificar Linux con símbolos resueltos, Windows con patrones únicos y dirección
   resultante; ejecutar pruebas reales de carga, tráfico, descarga, cambio de
   mapa, desconexión/reconexión y cambios de modo por native y ConVar.

No hay bypass mediante ConVar para activar el adaptador no verificado.

## Matriz de evidencia

| Componente | Linux x86 | Windows x86 |
|---|---|---|
| Lógica aislada | ASan + UBSan aprobados en Ubuntu 24.04 | No ejecutada aquí; CI configurado |
| Extensión | Compilación GCC 13.3 aprobada | Pendiente MSVC |
| ABI del motor / gamedata | Pendiente binario identificado y resolución efectiva | Pendiente `engine.dll` identificado y firmas |
| SRCDS real | No ejecutado | No ejecutado |
| Certificación producción | No | No |

También pasó la lógica aislada x64 en el host. Eso no agrega soporte engine x64.
Detalles y comandos: [informe de validación](FAKELAG_SAFETY_VALIDATION.md).
