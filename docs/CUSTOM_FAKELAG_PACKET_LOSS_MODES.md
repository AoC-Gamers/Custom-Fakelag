# Custom Fakelag Packet Loss Modes

## Objetivo

Describir de forma tecnica los dos modelos de simulacion de packet loss que
soporta actualmente la extension `custom_fakelag`:

- `Bernoulli uniforme`
- `Gilbert-Elliott`

Este documento se enfoca en:

- la definicion matematica de cada modelo
- sus propiedades estadisticas relevantes
- como se relacionan con el `%` de packet loss decidido por el plugin
- como estan aterrizados hoy en la implementacion

## Separacion de responsabilidades

### Plugin `player_fakelag`

El plugin decide la severidad objetivo:

- `packetLossPercent`

Ese valor es una tasa objetivo de perdida a nivel de jugador.

### Extension `custom_fakelag`

La extension decide la distribucion temporal de esa perdida:

- si las perdidas son independientes
- o si aparecen en rafagas cortas

Eso se controla con:

- `sm_custom_fakelag_loss_mode`

y con la API publica:

- `CFakeLagPacketLossMode`
- `CFakeLag_SetPacketLossMode(CFakeLagPacketLossMode mode)`
- `CFakeLag_GetPacketLossMode()`

## Variable comun de entrada

Ambos modelos parten de una misma entrada:

- `p = packetLossPercent / 100`

donde:

- `p in [0, 1]`

Ese `p` viene resuelto por `player_fakelag`.

## Modo 0: Bernoulli uniforme

### Definicion matematica

Sea `X_n` una variable aleatoria por paquete:

- `X_n = 1` si el paquete se pierde
- `X_n = 0` si el paquete se conserva

En Bernoulli uniforme:

- `P(X_n = 1) = p`
- `P(X_n = 0) = 1 - p`

y los eventos entre paquetes son independientes:

- `X_n ⟂ X_m` para `n != m`

### Esperanza y varianza

Para cada paquete:

- `E[X_n] = p`
- `Var(X_n) = p(1 - p)`

Para una secuencia de `N` paquetes:

- el numero esperado de perdidas es `N * p`

### Propiedad principal

No existe memoria entre paquetes.

Eso implica:

- la probabilidad de perder el siguiente paquete no cambia aunque el anterior
  haya sido perdido
- la longitud esperada de una rafaga de perdida es muy baja
- la autocorrelacion temporal del proceso es esencialmente `0`

### Consecuencia practica

Este modo reproduce una perdida promedio correcta, pero suele sentirse demasiado
"limpio" porque no forma rafagas.

## Modo 1: Gilbert-Elliott

### Definicion matematica

Gilbert-Elliott es un modelo de Markov de dos estados:

- `G` = Good
- `B` = Bad

En cada paquete, el sistema se encuentra en uno de esos estados y puede
transicionar al siguiente.

Matriz conceptual:

```text
        G        B
G   1-a        a
B    b       1-b
```

donde:

- `a = P(G -> B)`
- `b = P(B -> G)`

La perdida depende del estado:

- en `G`, la perdida es baja o nula
- en `B`, la perdida es alta

### Variante usada en la implementacion actual

La implementacion actual usa una forma simplificada:

- en `G`, la perdida efectiva es `0%`
- en `B`, la perdida efectiva es `100%`

Entonces:

- si el proceso entra a `B`, los paquetes de esa ventana se pierden
- cuando sale de `B`, vuelve a conservar paquetes normalmente

### Relacion entre porcentaje objetivo y transiciones

La implementacion fija:

- una probabilidad de salida de `B` llamada `b`
- una probabilidad de entrada a `B` llamada `a`

Actualmente:

- `b = 0.5`

Lo que implica una longitud media de rafaga en `B` de:

- `E[L_B] = 1 / b = 2 paquetes`

Luego ajusta `a` para aproximar la tasa promedio objetivo `p`.

En una cadena de dos estados, la probabilidad estacionaria de estar en `B` es:

- `pi_B = a / (a + b)`

Como en esta variante:

- `loss(G) = 0`
- `loss(B) = 1`

entonces la tasa media de perdida es:

- `p = pi_B = a / (a + b)`

Despejando:

- `a = p * b / (1 - p)`

Esa es exactamente la idea que usa la extension, solo que en base entera para
trabajar con randoms discretos.

### Propiedad principal

Este modelo tiene memoria.

Eso implica:

- si un paquete se acaba de perder, la probabilidad de perder el siguiente
  aumenta
- aparecen rafagas cortas
- existe autocorrelacion temporal positiva

### Consecuencia practica

Aunque el `%` promedio sea el mismo que en Bernoulli, la sensacion puede ser
mas parecida a una conexion real degradada.

## Comparacion tecnica entre modelos

### Misma tasa media, distinta estructura temporal

Supongamos:

- `p = 0.02`

En ambos modos, la perdida media esperada es aproximadamente `2%`.

Pero:

- en Bernoulli, los eventos son independientes
- en Gilbert-Elliott, la misma perdida media puede concentrarse en rafagas

### Longitud de rafagas

En Bernoulli:

- la probabilidad de dos perdidas seguidas es `p^2`

Con `p = 0.02`:

- `P(2 seguidas) = 0.0004`

Es muy baja.

En Gilbert-Elliott:

- si el proceso entra en `B`, la longitud esperada de la rafaga es `1 / b`

Con `b = 0.5`:

- la longitud media es `2 paquetes`

### Correlacion

En Bernoulli:

- correlacion temporal ~ `0`

En Gilbert-Elliott:

- correlacion temporal `> 0`

Eso es precisamente lo que permite modelar burst loss.

## Parametrizacion actual en la extension

### Seleccion del modo

La extension usa:

- `sm_custom_fakelag_loss_mode`

Valores:

- `0` = `Bernoulli uniforme`
- `1` = `Gilbert-Elliott`

El cambio de modo puede hacerse en vivo, pero la implementacion actual lo trata
de forma estricta:

- si el modo cambia, la extension hace `ResetState()`
- eso limpia todos los perfiles activos antes de adoptar el nuevo modelo

La razon es evitar mezclar estado interno y trafico retrasado entre modelos
distintos dentro de la misma sesion.

### Parametros efectivos del modo Gilbert-Elliott

La implementacion actual usa:

- una base discreta de probabilidad `10000`
- `b = 5000 / 10000 = 0.5`

Y calcula `a` a partir del `%` objetivo:

- `a ~= (p * b) / (1 - p)`

en forma entera y discretizada.

### Efecto de esa parametrizacion

Con `b = 0.5`:

- las rafagas malas son cortas
- el modo sigue siendo conservador
- el modelo no busca emular una red rota, sino introducir una leve estructura
  temporal en la perdida

## Limitaciones matematicas de la implementacion actual

La implementacion actual no es un Gilbert-Elliott general completo.

Simplificaciones actuales:

- `loss(G) = 0`
- `loss(B) = 100%`
- `b` es fijo
- solo `a` varia con el `%`

Eso significa:

- el control sobre la forma de las rafagas es limitado
- no se exponen parametros separados para `a` y `b`
- no se modelan estados intermedios de mala calidad con perdida parcial en `B`

## Interpretacion operativa

### Cuando usar Bernoulli

Conviene cuando se busca:

- baseline simple
- comportamiento facil de razonar
- debugging sencillo

### Cuando usar Gilbert-Elliott

Conviene cuando se busca:

- una estructura temporal mas realista
- burst loss corto
- una sensacion menos artificial en jugadores low ping con fakelag alto

## Relacion con el resto del sistema

Este documento no define cuanto `%` de packet loss debe recibir un jugador.

Eso se define en:

- `docs/PLAYER_FAKELAG_PACKET_LOSS_MODEL.md`

Este documento solo define como la extension transforma ese `%` en perdida
observada a nivel de paquetes.

## Resumen

### Bernoulli uniforme

- proceso sin memoria
- `P(loss) = p` por paquete
- tasa media correcta
- sin rafagas naturales

### Gilbert-Elliott

- proceso con memoria
- cadena de Markov de dos estados
- misma tasa media aproximada
- rafagas cortas por construccion

## Nota final

La eleccion entre ambos modos no cambia la severidad objetivo decidida por el
plugin. Cambia solo la geometria temporal de la perdida.

Esa es la razon por la que ambos modelos deben vivir en la extension y no en la
heuristica del plugin.
