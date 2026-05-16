# Custom Fakelag

Extensión de SourceMod para aplicar fake lag por jugador en **Left 4 Dead 2**.

El proyecto permite agregar latencia artificial a jugadores humanos específicos,
principalmente para pruebas, administración competitiva o balance de diferencias
de ping entre jugadores.

A diferencia de un plugin SourcePawn simple, este repositorio contiene una
extensión nativa en C++ que intercepta el manejo interno de paquetes del motor
Source y una capa SourcePawn que expone comandos, natives, forwards y lógica de
balance.

## Origen y créditos

Este repositorio deriva del proyecto original publicado por `ProdigySim`:

- https://github.com/ProdigySim/custom_fakelag

La base original de la extensión, su idea y la implementación inicial
corresponden a ese trabajo.

Este repositorio toma como base histórica la versión `1.0.0` del proyecto
original.

## Estado del proyecto

El código base de la extensión proviene de una implementación antigua, pero el
repositorio fue reorganizado para permitir un flujo de build reproducible antes
de modernizar más profundamente la lógica interna.

El objetivo actual del repositorio es mantener una base compilable, ordenada y
más fácil de extender.

Flujo recomendado en Linux:

```bash
make deps-linux
make build-linux
```

En Linux, el paquete final incluye solo `custom_fakelag.ext.so`. La extension
depende de las bibliotecas del gameserver (`libtier0_srv.so`,
`libvstdlib_srv.so`) normalmente presentes en `left4dead2/bin` o `linux/bin`,
por lo que no se empaquetan dentro de `addons/sourcemod/extensions`.

Flujo recomendado en Windows:

```powershell
make deps-windows
make build-windows
```

## Qué hace técnicamente

Custom Fakelag aplica latencia artificial retrasando paquetes entrantes de un
jugador.

La extensión carga `custom_fakelag.games`, localiza símbolos internos del motor
como `NET_LagPacket` y `net_time`, y crea un detour sobre `NET_LagPacket`.

Cuando llega un paquete de red:

1. La extensión revisa si el origen del paquete pertenece a un jugador con fake
   lag configurado.
2. Si el jugador no tiene fake lag, el paquete se despacha normalmente.
3. Si el jugador tiene fake lag, el paquete se copia a una cola interna.
4. El campo de tiempo de recepción del paquete se desplaza hacia el futuro.
5. El paquete se libera cuando `net_time` alcanza el tiempo simulado.

En términos simples: no cambia solamente un valor visual de ping. Retrasa el
procesamiento real de paquetes para ese jugador.

Además, la extensión ahora puede simular packet loss artificial por jugador.
Ese packet loss puede distribuirse con dos modelos:

- `Bernoulli uniforme`
- `Gilbert-Elliott`

## Arquitectura

El repositorio está dividido en dos capas principales.

### Extensión nativa C++

La extensión nativa vive en:

```text
extension/
```

Componentes relevantes:

```text
extension/
├── extension.cpp
├── NET_LagPacket_Detour.cpp
├── latency/
│   ├── PlayerLatencyApiBridge.cpp
│   ├── PlayerLatencyService.cpp
│   └── PlayerLagManager.cpp
└── network/
    ├── LagPacketPolicy.cpp
    └── LagSystem.cpp
```

Responsabilidades principales:

- cargar gamedata;
- resolver direcciones de red de clientes;
- registrar natives de SourcePawn;
- crear forwards para hooks de plugins;
- interceptar `NET_LagPacket`;
- retrasar paquetes mediante colas internas;
- simular packet loss artificial por jugador;
- limpiar estado al desconectar jugadores o descargar la extensión.

La extensión no decide persistencia ni restauración de perfiles entre
desconexiones. Su rol es ejecutar y limpiar estado activo del motor.

### Plugin SourcePawn

El plugin SourcePawn vive en:

```text
scripting/player_fakelag.sp
scripting/player_fakelag/
```

Este plugin entrega la capa administrativa y de uso práctico:

- comandos para aplicar y limpiar fake lag;
- comandos de estado y comparación de ping;
- balance global de latencia;
- balance por pares Survivor/Infected;
- resolución heurística de packet loss para balances;
- votaciones para aplicar balance;
- persistencia temporal por Steam Account ID;
- muestreo estable de ping para evitar decisiones basadas en picos aislados.

El plugin es el dueño de la gobernanza del sistema:

- decide cuándo aplicar un perfil;
- decide cuándo olvidarlo;
- decide si debe restaurarse tras reconexión;
- y al descargarse ordena a la extensión eliminar todo el estado residual.

## Gamedata

La extensión depende de firmas y direcciones declaradas en:

```text
gamedata/custom_fakelag.games.txt
```

Actualmente se usan firmas para:

- `NET_LagPacket`
- `net_time`

Si una actualización del binario del servidor cambia esas firmas, la extensión
podría dejar de cargar o fallar al inicializar el detour.

## API SourcePawn

El include principal está en:

```text
scripting/include/custom_fakelag.inc
```

Natives disponibles:

```sourcepawn
enum CFakeLagPacketLossMode
{
    CFakeLagPacketLoss_BernoulliUniform = 0,
    CFakeLagPacketLoss_GilbertElliott
};

enum struct CFakeLagNetworkProfile
{
    float lagMs;
    int packetLossPercent;
};

native void CFakeLag_SetPlayerLatency(int client, float lagTime);
native float CFakeLag_GetPlayerLatency(int client);
native bool CFakeLag_HasPlayerLatency(int client);
native void CFakeLag_ClearPlayerLatency(int client);

native void CFakeLag_SetPlayerPacketLoss(int client, int packetLossPercent);
native int CFakeLag_GetPlayerPacketLoss(int client);
native bool CFakeLag_HasPlayerPacketLoss(int client);
native void CFakeLag_ClearPlayerPacketLoss(int client);

native void CFakeLag_SetPacketLossMode(CFakeLagPacketLossMode mode);
native CFakeLagPacketLossMode CFakeLag_GetPacketLossMode();

native void CFakeLag_ClearAllPlayerProfiles();
native void CFakeLag_ResetState();
native int CFakeLag_GetProfiledClientCount();

native void CFakeLag_ClearAllPlayerLatencies();
native bool CFakeLag_IsClientSupported(int client);
native int CFakeLag_GetLaggedClientCount();
```

Helpers stock relevantes:

```sourcepawn
stock CFakeLagNetworkProfile CFakeLag_BuildNetworkProfile(float lagMs, int packetLossPercent);
stock void CFakeLag_GetPlayerProfile(int client, CFakeLagNetworkProfile profile);
stock void CFakeLag_ApplyPlayerProfile(int client, const CFakeLagNetworkProfile profile);
stock void CFakeLag_ClearPlayerProfile(int client);
```

Notas:

- `CFakeLag_ClearAllPlayerProfiles()` es la API preferida actual.
- `CFakeLag_ResetState()` deja la extensión como si nunca hubiera aplicado fakelag.
- `CFakeLag_ClearAllPlayerLatencies()` se mantiene como alias legacy.
- `CFakeLag_GetProfiledClientCount()` es la API preferida actual.
- `CFakeLag_GetLaggedClientCount()` se mantiene como alias legacy.

Forwards disponibles:

```sourcepawn
forward Action CFakeLag_OnSetPlayerLatency(
    int client,
    float oldLag,
    float &newLag,
    CFakeLagChangeReason reason
);

forward void CFakeLag_OnPlayerProfileChanged(
    int client,
    float oldLag,
    int oldPacketLossPercent,
    float newLag,
    int newPacketLossPercent,
    CFakeLagChangeReason reason
);
```

`CFakeLag_OnSetPlayerLatency` permite modificar o bloquear un cambio antes de
que se aplique.

`CFakeLag_OnPlayerProfileChanged` notifica después de que el perfil fue aplicado,
incluyendo `lag` y `packet loss`.

## Packet Loss Modes

La extensión expone la ConVar:

```text
sm_custom_fakelag_loss_mode
```

Valores:

- `0`: `Bernoulli uniforme`
- `1`: `Gilbert-Elliott`

El plugin decide cuánto `%` de packet loss aplicar. La extensión decide cómo
materializar ese `%` en el flujo real de paquetes.

## Plugin `player_fakelag`

Además de la extensión, el repositorio incluye un plugin SourcePawn de uso
administrativo llamado:

```text
player_fakelag.sp
```

Este plugin usa la extensión `custom_fakelag` y agrega comandos de administración
y balance.

### Comandos administrativos

```text
sm_fakelag <#userid|name> <milliseconds|0>
```

Aplica fake lag a un jugador. Usar `0` limpia el fake lag existente.

```text
sm_fakelag_balance <global|pairs>
```

Aplica balance automático de latencia.

Modos:

- `global`: iguala a todos los jugadores humanos elegibles al ping base más alto.
- `pairs`: empareja Survivors e Infected por ping y compensa al jugador con menor
  ping dentro de cada par.

```text
sm_fakelag_preview <global|pairs>
```

Muestra una vista previa del balance sin aplicarlo.

```text
sm_fakelag_clear_all
```

Limpia todas las entradas activas de fake lag.

```text
sm_fakelag_list
```

Lista jugadores con fake lag activo.

### Comandos de jugador

```text
sm_fakelag_clear
```

Permite limpiar el fake lag propio. Con permisos administrativos también puede
limpiar el de otro jugador.

```text
sm_fakelag_status
```

Muestra el estado de fake lag propio. Con permisos administrativos también puede
consultar a otro jugador.

```text
sm_fakelag_compare <#userid|name> [#userid|name]
```

Compara la latencia medida entre jugadores.

```text
sm_fakelag_vote <global|pairs>
```

Inicia una votación para aplicar balance de fake lag.

## Balance de latencia

El plugin mide ping usando muestras periódicas de latencia saliente mediante
SourceMod.

Para evitar decisiones inestables:

- mantiene una ventana de muestras;
- descarta extremos cuando hay suficientes muestras;
- descuenta el fake lag ya aplicado para estimar el ping base real;
- puede estimar una lectura similar a net graph usando `cl_updaterate`.

ConVars relevantes:

```text
sm_fakelag_debug "0"
sm_fakelag_sample_window "5"
sm_fakelag_sample_interval "1.0"
```

### Balance global

El modo global busca el jugador humano elegible con mayor ping base y aplica
fake lag a los demás hasta igualarlos a ese valor.

Ejemplo conceptual:

```text
Jugador A: 80 ms
Jugador B: 45 ms
Jugador C: 60 ms
```

Resultado:

```text
Jugador A: 0 ms fake lag
Jugador B: 35 ms fake lag
Jugador C: 20 ms fake lag
```

### Balance por pares

El modo por pares separa jugadores por equipo:

- Survivors
- Infected

Luego ordena ambos grupos por ping descendente y empareja jugadores por posición.
Dentro de cada par, aplica fake lag al jugador con menor ping para igualarlo al
otro.

Los jugadores que quedan sin pareja tienen su fake lag limpiado.

## Persistencia temporal

El plugin mantiene perfiles de fakelag por Steam Account ID usando `StringMap`.

Ese perfil incluye:

- `lagMs`
- `packetLossPercent`

Esto permite restaurar el fake lag cuando un jugador vuelve a ser elegible, por
ejemplo después de reconectar o cambiar de equipo.

Esta persistencia:

- es temporal;
- vive solo en memoria mientras `player_fakelag` está cargado;
- no usa base de datos;
- no pertenece a la extensión.

Cuando `player_fakelag` se descarga, el plugin llama `CFakeLag_ResetState()`.
La regla operativa es simple:

- si el plugin no está cargado, no debe quedar fakelag activo ni estado interno
  residual en la extensión.

## Gobernanza

La separación de responsabilidades es intencional:

- la extensión aplica `lag` y `packet loss` a clientes activos;
- la extensión no decide si un jugador debe recuperar su perfil;
- la extensión no conserva intención de restauración por su cuenta;
- el plugin decide persistencia, restauración y olvido por `Steam Account ID`;
- el plugin ordena el reset total al final de su ciclo de vida.

Esto evita mover lógica competitiva o administrativa a la capa nativa y mantiene
la extensión como un motor reutilizable.

## Requisitos

### Generales

- `bash`
- `git`
- `make`
- `python3`
- SourceMod compatible
- MetaMod:Source compatible
- HL2SDK para L4D2
- AMBuild

Las dependencias de SourceMod, MetaMod:Source, HL2SDK y AMBuild son descargadas
por los scripts del repositorio dentro de `.deps/`.

## Compilación local

### Linux

Para compilar en Linux nativo necesitas:

- `bash`
- `git`
- `make`
- `python3`
- `python3-venv`
- compilador con soporte 32-bit
- librerías multilib instaladas

En Ubuntu/Debian:

```bash
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y python3 python3-venv make gcc-multilib g++-multilib clang zip
```

Luego:

```bash
make deps-linux
make build-linux
```

Artefactos generados:

```text
.build/linux-l4d2/package/addons/sourcemod/extensions/custom_fakelag.ext.so
.build/linux-l4d2/package/addons/sourcemod/plugins/player_fakelag.smx
```

### Windows

Para compilar en Windows nativo necesitas:

- `git`
- `make`
- `PowerShell 7+`
- `python` 3.x
- Visual Studio Build Tools o Visual Studio con soporte C++
- toolchain MSVC x86/x64 disponible

El build Windows usa `AMBuild` con `cl.exe`, por lo que no basta con tener solo
Python o Make.

Comandos:

```powershell
make deps-windows
make build-windows
```

Artefactos generados:

```text
.build/windows-l4d2/package/addons/sourcemod/extensions/custom_fakelag.ext.dll
.build/windows-l4d2/package/addons/sourcemod/plugins/player_fakelag.smx
```

Si `cl.exe` no está disponible en el entorno actual, el script intenta localizar
`vswhere.exe` y cargar `vcvarsall.bat` automáticamente.

Si tu instalación de Visual Studio está en una ruta poco común, puedes copiar
`.env.example` a `.env` y definir overrides locales.

Ejemplo:

```dotenv
VCVARSALL_PATH=C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat
```

### WSL

WSL2 con Ubuntu es una opción recomendada para compilar el artefacto Linux desde
Windows.

Ejemplo:

```bash
cd /mnt/c/GitHub/Custom-Fakelag
make deps-linux
make build-linux
```

## Targets disponibles

```text
make help
make deps-linux
make deps-windows
make build-linux
make build-windows
make clean-linux
make clean-windows
```

## Dependencias resueltas por script

Los scripts de dependencias preparan:

- `alliedmodders/hl2sdk`, rama `l4d2`
- `alliedmodders/sourcemod`, rama `1.12-dev`
- `alliedmodders/metamod-source`, rama `1.12-dev`
- `alliedmodders/ambuild`

Todo se instala localmente dentro de:

```text
.deps/
```

También se crea un entorno virtual de Python para AMBuild.

## Contenido empaquetado

El paquete final incluye:

```text
addons/sourcemod/extensions/custom_fakelag.ext.so
addons/sourcemod/extensions/custom_fakelag.ext.dll
addons/sourcemod/plugins/player_fakelag.smx
addons/sourcemod/scripting/player_fakelag.sp
addons/sourcemod/scripting/player_fakelag/
addons/sourcemod/scripting/include/custom_fakelag.inc
addons/sourcemod/scripting/include/player_fakelag.inc
addons/sourcemod/gamedata/custom_fakelag.games.txt
addons/sourcemod/translations/player_fakelag.phrases.txt
```

El binario exacto depende de la plataforma compilada.

## Instalación en servidor

Copiar el contenido de:

```text
.build/linux-l4d2/package/
```

o:

```text
.build/windows-l4d2/package/
```

sobre el directorio del servidor donde vive `addons/sourcemod`.

En Linux, el archivo principal de la extensión queda en:

```text
addons/sourcemod/extensions/custom_fakelag.ext.so
```

El plugin administrativo queda en:

```text
addons/sourcemod/plugins/player_fakelag.smx
```

El gamedata debe quedar en:

```text
addons/sourcemod/gamedata/custom_fakelag.games.txt
```

## Consideraciones importantes

Esta extensión depende de internals del motor Source. Si cambian las firmas de
`NET_LagPacket` o `net_time`, puede fallar al cargar.

El fake lag se aplica a jugadores humanos soportados. Los fake clients/bots no
son targets válidos.

El sistema trabaja retrasando paquetes por dirección de red. Si no se puede
resolver la dirección de red de un cliente, no se aplica fake lag para ese
cliente.

El plugin `player_fakelag` está pensado para L4D2 y usa lógica de equipos
Survivor/Infected mediante Left 4 DHooks.

## Documentación adicional

Ver:

```text
docs/DEVELOPMENT.md
```
