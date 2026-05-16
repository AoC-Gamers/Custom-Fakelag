# Changelog

Todos los cambios importantes de este proyecto se documentan en este archivo.

## [Unreleased]

### Agregado
- Se agrego una API low-level en `custom_fakelag.inc` para:
  - asignar fake lag por jugador
  - consultar fake lag activo
  - limpiar fake lag individual o global
  - validar clientes soportados
  - contar jugadores con fake lag activo
  - interceptar y observar cambios mediante forwards
- Se agrego el plugin `player_fakelag.sp` como capa high-level sobre la extension.
- Se agregaron comandos administrativos y de consulta:
  - `sm_fakelag`
  - `sm_fakelag_status`
  - `sm_fakelag_clear`
  - `sm_fakelag_clear_all`
  - `sm_fakelag_list`
- Se agrego el balanceador de fake lag por ping con modos explicitos:
  - `sm_fakelag_balance <global|pairs>`
  - `sm_fakelag_preview <global|pairs>`
  - `sm_fakelag_vote <global|pairs>`
- Se agrego una API high-level en `player_fakelag.inc` con natives para aplicar, previsualizar y votar el balanceo.
- Se agregaron forwards high-level en `player_fakelag.inc` para que otros plugins puedan interceptar y observar cambios de fake lag desde `player_fakelag`:
  - `PlayerFakelag_OnSetPlayerLatency`
  - `PlayerFakelag_OnPlayerProfileChanged`
  - `PlayerFakelag_OnPluginEnd`
  - `PlayerFakelag_OnPacketLossModeChanged`
- Se agrego `custom_fakelag_forward.sp` como plugin de ejemplo para los forwards low-level de la extension.
- Se agregaron translations para la UX del plugin `player_fakelag`.
- Se agregaron scripts de bootstrap y compilacion para Linux y Windows bajo `scripts/`.
- Se agrego soporte opcional de `.env` para overrides locales como `VCVARSALL_PATH`.
- Se agregaron archivos de soporte para el workspace:
  - `.editorconfig`
  - `.env.example`
  - `docs/DEVELOPMENT.md`
- Se agregaron capas internas nuevas en la extension para separar responsabilidades:
  - `LagPacketPolicy`
  - `PlayerProfileService`
  - `PlayerProfileApiBridge`
  - `EngineClientNetAdrResolver`

### Cambiado
- Se reorganizo el codigo nativo bajo `extension/`.
- Se agrupo la logica nativa en subdirectorios semanticos:
  - `extension/latency`
  - `extension/network`
- Se normalizaron a minusculas los nombres de directorios del proyecto.
- Se reemplazo el forward posterior `CFakeLag_OnPlayerLatencyChanged` por el forward compuesto `CFakeLag_OnPlayerProfileChanged`.
- Se agrego el forward low-level `CFakeLag_OnPacketLossModeChanged` y su equivalente high-level `PlayerFakelag_OnPacketLossModeChanged` para observar cambios de modelo de packet loss.
- Se reemplazo el forward posterior `PlayerFakelag_OnPlayerLatencyChanged` por `PlayerFakelag_OnPlayerProfileChanged`.
- Se simplifico el `Makefile` con targets explicitos para dependencias y build:
  - `make help`
  - `make deps`
  - `make deps-linux`
  - `make deps-windows`
  - `make build-linux`
  - `make build-windows`
  - `make clean`
  - `make distclean`
- Se actualizo `AMBuildScript` para alinearlo con SourceMod 1.12 y el flujo actual del repo.
- Se actualizo `PackageScript` para empaquetar:
  - `custom_fakelag.ext.so`
  - `custom_fakelag.ext.dll`
  - `custom_fakelag.inc`
  - `custom_fakelag.games.txt`
  - `player_fakelag.inc`
  - `player_fakelag.sp`
- Se actualizo `PackageScript` para incluir `player_fakelag.smx` en el artefacto final cuando este compilado.
- Se actualizo el empaquetado para excluir `custom_fakelag_forward.sp` y su binario del artefacto final.
- Se actualizo el plugin `player_fakelag` a sintaxis moderna (`newdecls`) y se simplifico su salida hacia translations en lugar de logs ruidosos al servidor.
- Se actualizo `player_fakelag` para notificar su descarga mediante `PlayerFakelag_OnPluginEnd` antes de cancelar votos y limpiar de forma destructiva todas las entradas activas de fake lag.
- Se movio la logica de balanceo por ping al plugin SourcePawn en lugar de dejarla en la extension.
- Se integraron `builtinvotes`, `colors` y `left4dhooks_stocks` en el flujo del plugin de administracion.
- Se actualizo la salida del build para dejar unicamente los binarios canonicos `custom_fakelag.ext.so` y `custom_fakelag.ext.dll` en el paquete final.
- Se actualizo la obtencion de dependencias para descargar el paquete oficial de SourceMod y usar `spcomp` real en Linux y Windows.
- Se actualizo el workflow de GitHub Actions para usar versiones actuales de las actions de checkout, cache, Python y artifacts.
- Se actualizo el workflow de GitHub Actions para publicar releases de canal consumibles por otros proyectos:
  - `channel/latest`
  - `channel/develop`
- Se actualizo el naming de artefactos a:
  - `custom-fakelag-linux-latest.zip`
  - `custom-fakelag-linux-develop.zip`
  - `custom-fakelag-windows-latest.zip`
  - `custom-fakelag-windows-develop.zip`
- Se actualizo la documentacion del repositorio para describir:
  - requisitos de compilacion en Windows
  - compilacion en Linux y WSL
  - origen del proyecto base de `ProdigySim`
- Se refactorizo la extension para separar con mas claridad:
  - la politica de lag de paquetes
  - el detour de `NET_LagPacket`
  - el almacenamiento de latencias por `netadr`
  - la validacion de clientes soportados
  - la traduccion de forwards de SourceMod
- Se desacoplo `PlayerLagManager` del acceso directo a `IVEngineServer`, `playerhelpers` y el logging global del SDK.
- Se corrigio y modernizo el flujo interno para que Windows y Linux compilen la misma base de codigo con el nuevo tooling.
- Se modernizaron partes del codigo de la extension para mantener compatibilidad con el flujo de build actual.

### Eliminado
- Se elimino `pkg/` y otras copias legacy del contenido empaquetado.
- Se eliminaron proyectos legacy de Visual Studio:
  - `msvc8`
  - `msvc9`
  - `msvc10`
  - `msvc12`
- Se elimino `.gitmodules` y la dependencia del repo en submodules propios.
- Se elimino el logging directo de cambios de fake lag desde `player_fakelag` a favor de forwards reutilizables para otros plugins.
- Se eliminaron acoplamientos legacy dentro de la extension entre natives, forwards, detours y manejo de estado interno.

## [1.0.0]

### Notas
- Version base original del proyecto publicado por `ProdigySim`.
## 2.0.0

- Se elevo la version mayor de la extension a `2.0.0` por ruptura de compatibilidad con la API original basada en latencia separada.
- La API publica de `custom_fakelag.inc` quedo centrada en perfiles (`lag + packet loss`) y elimino los nativos legacy fraccionados.
- `player_fakelag` y `custom_fakelag_test` quedaron alineados con la API nueva.
