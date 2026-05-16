# Player Fakelag Packet Loss Model

## Objetivo

Describir el modelo de packet loss artificial que hoy soporta la extension
`custom_fakelag`.

Este documento ya no plantea una idea futura. Resume lo que esta implementado
en el repositorio:

- que forma tiene el modelo de severidad
- que parametros controlan la formula
- que piezas publicas expone la API de la extension

## Motivacion del modelo

Un jugador con ping base muy bajo al que se le agrega solo fakelag suele
sentirse mas limpio que un jugador con ping medio o alto natural.

La razon es que una conexion real no suele traer solo latencia. Tambien puede
venir acompa#ada de otras imperfecciones, entre ellas:

- packet loss
- jitter
- pequenas rafagas de degradacion

El modelo implementado aca busca introducir una peque#a cantidad de packet loss
artificial solo cuando ayuda a que el resultado final se sienta mas parecido a
una conexion real degradada.

## Alcance del documento

Este documento se enfoca en:

- el modelo numerico usado para resolver una severidad de packet loss
- la representacion de ese packet loss en la API de la extension
- la relacion entre severidad objetivo y modo de simulacion

No documenta la logica de comandos o balance externo.

## Variables del modelo

La heuristica actual usa tres variables:

- `B`: ping base real del jugador
- `T`: ping objetivo final
- `A`: fakelag agregado

donde:

- `A = T - B`

## Formula de severidad

La formula implementada en el repositorio es:

- `baseFactor = clamp((60 - B) / 40, 0, 1)`
- `targetFactor = clamp((T - 40) / 40, 0, 1)`
- `addedFactor = clamp((A - 25) / 35, 0, 1)`

- `lossFloat = 2.0 * baseFactor * targetFactor * addedFactor`
- `lossPercent = round(clamp(lossFloat, 0, 2))`

En el codigo, esos valores no estan hardcodeados del todo: los umbrales y spans
se resuelven desde ConVars.

## Interpretacion de la formula

### `baseFactor`

Favorece aplicar packet loss a jugadores con ping base bajo.

- si `B >= 60`, tiende a `0`
- si `B` es muy bajo, tiende a `1`

### `targetFactor`

Favorece aplicar packet loss cuando el ping final objetivo ya entra en una zona
menos limpia.

- si `T <= 40`, tiende a `0`
- si `T >= 80`, tiende a `1`

### `addedFactor`

Evita aplicar packet loss cuando el ajuste agregado fue peque#o.

- si `A <= 25`, tiende a `0`
- si `A >= 60`, tiende a `1`

## Resultado practico esperado

La politica actual tiende a producir:

- `0%` cuando el jugador ya tiene ping base alto
- `0%` cuando el ajuste agregado es peque#o
- `1%` cuando el jugador tenia ping bajo y fue llevado a un ping medio
- `2%` cuando el jugador tenia ping muy bajo y fue llevado a un ping alto

## Ejemplos de referencia

### Caso 1

- `B = 20`
- `T = 30`
- `A = 10`

Resultado esperado:

- `0%`

### Caso 2

- `B = 20`
- `T = 60`
- `A = 40`

Resultado esperado:

- `1%`

### Caso 3

- `B = 20`
- `T = 90`
- `A = 70`

Resultado esperado:

- `2%`

### Caso 4

- `B = 45`
- `T = 80`
- `A = 35`

Resultado esperado:

- `1%`

### Caso 5

- `B = 80`
- `T = 110`
- `A = 30`

Resultado esperado:

- `0%`

## Limites actuales

El modelo esta implementado de forma conservadora:

- minimo: `0%`
- maximo: `2%`

No se usa una politica mas agresiva por defecto porque el objetivo no es romper
la jugabilidad ni recrear una conexion mala extrema, sino quitarle algo de
"limpieza artificial" a ciertos casos de fakelag.

## ConVars que controlan la formula

La heuristica actual se controla con:

- `sm_fakelag_loss_base_ceiling_ms = 60`
- `sm_fakelag_loss_base_span_ms = 40`
- `sm_fakelag_loss_target_floor_ms = 40`
- `sm_fakelag_loss_target_span_ms = 40`
- `sm_fakelag_loss_added_floor_ms = 25`
- `sm_fakelag_loss_added_span_ms = 35`
- `sm_fakelag_loss_max_percent = 2`

Con eso, la forma general del modelo se mantiene estable, pero sus umbrales se
pueden recalibrar sin reescribir la logica principal.

## Perfil compuesto expuesto por el include

El include de la extension expone un perfil compuesto:

- `CFakeLagNetworkProfile`

Helpers disponibles:

- `CFakeLag_BuildNetworkProfile(float lagMs, int lossPercent)`
- `CFakeLag_GetPlayerProfile(int client, CFakeLagNetworkProfile &profile)`
- `CFakeLag_ApplyPlayerProfile(int client, const CFakeLagNetworkProfile profile)`
- `CFakeLag_ClearPlayerProfile(int client)`

Eso permite trabajar con un solo perfil logico por jugador, aunque
internamente la extension siga exponiendo setters separados para latencia y
packet loss.

## Relacion con los modos de simulacion

Este documento describe la severidad objetivo del packet loss.

La distribucion temporal real de ese `%` sobre los paquetes depende de la
extension y de `sm_custom_fakelag_loss_mode`.

Modos disponibles:

- `0`: `Bernoulli uniforme`
- `1`: `Gilbert-Elliott`

Eso esta documentado aparte en:

- `docs/CUSTOM_FAKELAG_PACKET_LOSS_MODES.md`

## Resumen

El modelo implementado hoy es:

1. definir una severidad objetivo de packet loss
2. limitarla a un rango conservador
3. representarla como parte de un perfil de red
4. dejar que la extension materialice ese loss con el modo configurado

## Nota final

Este modelo sigue siendo una heuristica de dise#o, no una ley de red real.

Su funcion actual es:

- representar una severidad de perdida conservadora
- mantener una API explicita para `lag + loss`
- dejar espacio para iteracion empirica sin cambiar la arquitectura base
