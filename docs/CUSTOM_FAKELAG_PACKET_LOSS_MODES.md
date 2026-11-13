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

Para `0 < p < 1`, la implementación usa:

- `a = p / 2`
- `b = (1 - p) / 2`
- primero transiciona; luego descarta si el nuevo estado es `B`

Por tanto `pi_B = a/(a+b) = p`, `E[L_B] = 1/b = 2/(1-p)` y
`rho(k) = (1-a-b)^k = 0.5^k`. Al entrar en `B` se descarta; al salir se entrega.
0 % siempre entrega y deja estado bueno; 100 % siempre descarta.
No hay división por `1-p` en el algoritmo ni probabilidades saturadas.
Mantener ráfagas de dos paquetes para todo porcentaje sería incompatible con
las transiciones acotadas; a porcentajes altos las ráfagas crecen.

### Propiedad principal

Este modelo tiene memoria.

Eso implica:

- si un paquete se acaba de perder, la probabilidad de perder el siguiente
  aumenta
- aparecen ráfagas correlacionadas
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

Con `p = 0.02`, `b = 0.49`:

- la longitud media es aproximadamente `2.0408 paquetes`

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

Se muestrea con `mt19937` propio y uniformes en `[0,1)`; no se modifica el
PRNG global del motor. Se parte de `G` por generación de conexión y se limpia
su estado al cambiar/eliminar el perfil, desconectar o resetear. No se exponen
parámetros independientes de ráfaga. La tasa es estacionaria; una ventana corta
puede diferir del objetivo por correlación y por el estado inicial.

Las pruebas usan 2 000 000 de paquetes por porcentaje y semillas fijas;
[el informe](FAKELAG_SAFETY_VALIDATION.md) registra resultados y tolerancias.
La ejecución en el motor permanece bloqueada hasta validar el adaptador ABI.

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
- ráfagas de media `2/(1-p)`, crecientes con el porcentaje

## Nota final

La eleccion entre ambos modos no cambia la severidad objetivo decidida por el
plugin. Cambia solo la geometria temporal de la perdida.

Esa es la razon por la que ambos modelos deben vivir en la extension y no en la
heuristica del plugin.
