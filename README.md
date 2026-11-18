# Custom Fakelag

Extensión SourceMod para añadir latencia y pérdida de paquetes a jugadores
humanos de **Left 4 Dead 2**. Incluye `player_fakelag`, con comandos, balance,
votaciones y persistencia temporal. Deriva de
[ProdigySim/custom_fakelag](https://github.com/ProdigySim/custom_fakelag).

## Estado actual

- Motores admitidos: L4D2 2.2.4.3 x86, Linux y Windows, únicamente las
  [identidades verificadas](docs/engine/sdk-runtime-references.md). Una firma encontrada
  no basta para habilitar otro binario.
- Carga y recarga con Left4DHooks activo comprobadas en Windows para ese motor.
- Con `sv_lan 1` se bloquea fakelag y se limpian perfiles, colas y pérdida.
  La excepción `sm_custom_fakelag_allow_lan 1` permite pruebas explícitas.
  Volver a LAN 0 no recupera perfiles ni persistencia del plugin.
- La política LAN tiene regresiones y CI aprobados; su aceptación en SRCDS real
  sigue pendiente. El fallo de interfaces Steam también se reproduce en vanilla:
  bloquear fakelag no lo corrige.

La [matriz de validación](docs/testing/validation.md) separa compilación, pruebas aisladas
y pruebas en servidor, e identifica las revisiones correspondientes.

## Instalación

Usa el ZIP de la plataforma adecuada o compílalo según
[desarrollo local](docs/build/development.md). Copia `addons/` sobre el servidor y
actualiza **extensión, plugin e includes juntos**. El paquete contiene:

- `extensions/custom_fakelag.ext.2.l4d2.so` o `.ext.2.l4d2.dll`.
- `plugins/player_fakelag.smx`, sus includes públicos propios.
- `gamedata/custom_fakelag.games.txt` y traducciones.

Las rutas anteriores son relativas a `addons/sourcemod/`. El diagnóstico Steam
es independiente y se publica como artefacto separado, sin autoload.

Entorno comprobado: SourceMod 1.12 y Metamod 1.12. El plugin usa BuiltinVotes y
Left4DHooks; la extensión puede utilizarse desde otros plugins sin esa capa.
Los includes externos de desarrollo y el runtime de Valve no se distribuyen
dentro del ZIP. En Linux se requieren las bibliotecas i386 del gameserver.

Al actualizar desde los paquetes antiguos, descargar la extensión y retirar
`custom_fakelag.ext.so` o `custom_fakelag.ext.dll` antes de instalar el binario
canónico de la misma plataforma. Conservar una sola copia evita cargas duplicadas.
El nombre lógico de carga y los includes públicos permanecen iguales.

Comprueba en la consola del servidor que `sm exts list` muestre la extensión y
`sm plugins list` muestre `player_fakelag`. Si la instalación falla, restaura
el conjunto anterior de archivos desde tu respaldo. La copia de `addons/` puede
sobrescribir recursos propios modificados. El motor debe corresponder a las
[identidades verificadas de L4D2 2.2.4.3 x86](docs/engine/sdk-runtime-references.md).
Las versiones actuales conservan el sufijo de juego en los binarios y bloquean
fakelag con `sv_lan 1` salvo que se habilite la excepción de pruebas.

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
Los parámetros de pérdida están en [la fórmula del plugin](docs/packet-loss/player-fakelag-packet-loss-model.md).

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
cliente ya se desconectó, y cancela restauraciones/votos pendientes. La limpieza global descarta también perfiles de desconectados, snapshots y
restauraciones/votos pendientes. La descarga del plugin pide reset total de la
extensión. Los avisos y contadores reflejan cambios efectivos; un veto no confirma
éxito. Los perfiles de solo pérdida también se restauran al recuperar elegibilidad.

## API y arquitectura

- La extensión posee perfiles activos por sesión, paquetes propios y modelo de
  pérdida. Intercepta `NET_LagPacket`, retiene tráfico entrante y restaura sobre
  el buffer prestado del motor. No copia el lector sin preparar.
- El plugin decide balance y persistencia. Las declaraciones completas están en
  [custom_fakelag.inc](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/addons/sourcemod/scripting/include/custom_fakelag.inc) y
  [player_fakelag.inc](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/addons/sourcemod/scripting/include/player_fakelag.inc).

La API principal permite asignar/consultar/limpiar perfiles, resetear, consultar
clientes y elegir modelo de pérdida. El forward previo de latencia puede vetar
normalmente con Handled/Stop; errores de ejecución o valores inválidos abortan
la operación. Latencia válida: 0–10000 ms; pérdida: 0–100 %.

`CFakeLag_IsLanBlocked()` consulta la política. Al entrar en ella,
`CFakeLag_OnLanPolicyChanged(true)` avisa después de limpiar; los consumidores
con persistencia deben descartarla. Las asignaciones no nulas bloqueadas generan
un error nativo. Más detalles: [política LAN](docs/lan-policy/lan-policy.md).

## Documentación

| Tema | Referencia |
|---|---|
| Compilar, probar y empaquetar | [Desarrollo](docs/build/development.md), [build](docs/build/build-system.md) |
| Estado, CI y evidencia | [Validación](docs/testing/validation.md) |
| Política LAN | [Contrato y límites](docs/lan-policy/lan-policy.md) |
| Medición de latencia | [Referencia](docs/latency/player-fakelag-latency-reference.md) |
| Pérdida: severidad y distribución | [Plugin](docs/packet-loss/player-fakelag-packet-loss-model.md), [extensión](docs/packet-loss/custom-fakelag-packet-loss-modes.md) |
| ABI y buffers | [SDK/runtime](docs/engine/sdk-runtime-references.md) |
| Diagnóstico Steam opcional | [Steam Lifecycle Debug](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/diagnostics/steam_lifecycle_debug/README.md) |

Documentación organizada: [índice](docs/README.md). Fuentes disponibles en este repositorio.

Los ZIP de canal usan `custom-fakelag-develop-linux.zip`,
`custom-fakelag-develop-windows.zip`, `custom-fakelag-latest-linux.zip` y
`custom-fakelag-latest-windows.zip`. Los enlaces antiguos con plataforma antes
del canal deberán actualizarse cuando se publique la migración.
