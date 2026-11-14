# Custom Fakelag

Extensión SourceMod para añadir latencia y pérdida de paquetes a jugadores
humanos de **Left 4 Dead 2**. Incluye `player_fakelag`, con comandos, balance,
votaciones y persistencia temporal. Deriva de
[ProdigySim/custom_fakelag](https://github.com/ProdigySim/custom_fakelag).

## Estado actual

- Motores admitidos: L4D2 2.2.4.3 x86, Linux y Windows, únicamente las
  [identidades verificadas](docs/SDK_RUNTIME_REFERENCES.md). Una firma encontrada
  no basta para habilitar otro binario.
- Carga y recarga con Left4DHooks activo comprobadas en Windows para ese motor.
- Con `sv_lan 1` se bloquea fakelag y se limpian perfiles, colas y pérdida.
  La excepción `sm_custom_fakelag_allow_lan 1` permite pruebas explícitas.
  Volver a LAN 0 no recupera perfiles ni persistencia del plugin.
- La política LAN tiene regresiones y CI aprobados; su aceptación en SRCDS real
  sigue pendiente. El fallo de interfaces Steam también se reproduce en vanilla:
  bloquear fakelag no lo corrige.

La [matriz de validación](docs/VALIDATION.md) separa compilación, pruebas aisladas
y pruebas en servidor, e identifica las revisiones correspondientes.

## Instalación

Usa el ZIP de la plataforma adecuada o compílalo según
[desarrollo local](docs/DEVELOPMENT.md). Copia `addons/` sobre el servidor y
actualiza **extensión, plugin e includes juntos**. El paquete contiene:

- `extensions/custom_fakelag.ext.so` o `.ext.dll`.
- `plugins/player_fakelag.smx`, sus fuentes e includes propios.
- `gamedata/custom_fakelag.games.txt` y traducciones.

Las rutas anteriores son relativas a `addons/sourcemod/`. El diagnóstico Steam
es independiente y se publica como artefacto separado, sin autoload.

Entorno comprobado: SourceMod 1.12 y Metamod 1.12. El plugin usa BuiltinVotes y
Left4DHooks; la extensión puede utilizarse desde otros plugins sin esa capa.
Los includes externos de desarrollo y el runtime de Valve no se distribuyen
dentro del ZIP. En Linux se requieren las bibliotecas i386 del gameserver.

## Configuración

| ConVar de extensión | Predeterminado | Función |
|---|---:|---|
| `sm_custom_fakelag_allow_lan` | 0 | Excepción explícita para pruebas con LAN 1 |
| `sm_custom_fakelag_loss_mode` | 0 | 0: Bernoulli; 1: Gilbert-Elliott |
| `sm_custom_fakelag_detour_mode` | 0 | 0: bajo demanda; 1: siempre activo si LAN lo permite |
| `sm_custom_fakelag_debug` | 0 | Log interno de paquetes |
| `sm_custom_fakelag_debug_hold_interval` | 5.0 | Intervalo mínimo de logs repetidos por socket, en segundos |

El plugin genera `cfg/sourcemod/player_fakelag.cfg`. Sus ajustes de muestreo son
`sm_fakelag_sample_window=5`, `sm_fakelag_sample_interval=1.0` y
`sm_fakelag_debug=0`. Aplica `sm_fakelag_loss_mode_default=1` al ejecutar configs;
por tanto el modo efectivo puede diferir del valor inicial de la extensión.
Los parámetros de pérdida están en [la fórmula del plugin](docs/PLAYER_FAKELAG_PACKET_LOSS_MODEL.md).

Cambiar el modo de pérdida resetea el estado de la extensión. `player_fakelag`
puede reconstruir sus perfiles tras ese cambio; el bloqueo LAN descarta también
esas restauraciones y tiene prioridad sobre `always-on`.

## Comandos

| Comando | Uso |
|---|---|
| `sm_fakelag <jugador> <ms>` | Asignar latencia; requiere permiso de configuración |
| `sm_fakelag_balance <global\|pairs>` | Aplicar balance global o por parejas |
| `sm_fakelag_preview <global\|pairs>` | Previsualizar balance |
| `sm_fakelag_clear_all` / `sm_fakelag_list` | Limpiar todos los perfiles / listar activos |
| `sm_fakelag_clear [jugador]` | Limpiar el propio; otro jugador requiere permisos |
| `sm_fakelag_status [jugador]` | Consultar el propio; otro jugador requiere permisos |
| `sm_fakelag_compare <jugador> [jugador]` | Comparar latencias |
| `sm_fakelag_vote <global\|pairs>` | Solicitar votación de balance |

Los objetivos admiten nombre o `#userid`. El balance global toma el mayor ping
base elegible; el balance por parejas ordena Survivors/Infected por ping y
compensa al de menor latencia de cada pareja. Los que quedan sin pareja se limpian.

Los perfiles se guardan por Account ID en memoria del plugin, sin base de datos,
para reconexión o cambio de equipo. El bloqueo LAN los olvida, incluso si el
cliente ya se desconectó, y cancela restauraciones/votos pendientes. La descarga
del plugin pide reset total de la extensión.

## API y arquitectura

- La extensión posee perfiles activos por sesión, paquetes propios y modelo de
  pérdida. Intercepta `NET_LagPacket`, retiene tráfico entrante y restaura sobre
  el buffer prestado del motor. No copia el lector sin preparar.
- El plugin decide balance y persistencia. Las declaraciones completas están en
  [custom_fakelag.inc](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/scripting/include/custom_fakelag.inc) y
  [player_fakelag.inc](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/scripting/include/player_fakelag.inc).

La API principal permite asignar/consultar/limpiar perfiles, resetear, consultar
clientes y elegir modelo de pérdida. El forward previo de latencia puede vetar
normalmente con Handled/Stop; errores de ejecución o valores inválidos abortan
la operación. Latencia válida: 0–10000 ms; pérdida: 0–100 %.

`CFakeLag_IsLanBlocked()` consulta la política. Al entrar en ella,
`CFakeLag_OnLanPolicyChanged(true)` avisa después de limpiar; los consumidores
con persistencia deben descartarla. Las asignaciones no nulas bloqueadas generan
un error nativo. Más detalles: [política LAN](docs/LAN_POLICY.md).

## Documentación

| Tema | Referencia |
|---|---|
| Compilar, probar y empaquetar | [Desarrollo](docs/DEVELOPMENT.md), [build](docs/build-system.md) |
| Estado, CI y evidencia | [Validación](docs/VALIDATION.md) |
| Política LAN | [Contrato y límites](docs/LAN_POLICY.md) |
| Medición de latencia | [Referencia](docs/PLAYER_FAKELAG_LATENCY_REFERENCE.md) |
| Pérdida: severidad y distribución | [Plugin](docs/PLAYER_FAKELAG_PACKET_LOSS_MODEL.md), [extensión](docs/CUSTOM_FAKELAG_PACKET_LOSS_MODES.md) |
| ABI y buffers | [SDK/runtime](docs/SDK_RUNTIME_REFERENCES.md) |
| Diagnóstico Steam opcional | [Steam Lifecycle Debug](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/diagnostics/steam_lifecycle_debug/README.md) |
