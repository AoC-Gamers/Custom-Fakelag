# Distribución de pérdida en la extensión

Entrada común: `p = packetLossPercent / 100`, entre 0 y 1. El porcentaje lo
asigna un consumidor; el plugin incluido usa [esta heurística](PLAYER_FAKELAG_PACKET_LOSS_MODEL.md).
La extensión determina qué paquetes se descartan, no la política de balance.

| `sm_custom_fakelag_loss_mode` | Modelo | Distribución |
|---|---|---|
| 0, inicial de la extensión | Bernoulli | Descarte independiente con probabilidad p |
| 1, predeterminado del plugin | Gilbert-Elliott | Estados bueno/malo, pérdidas correlacionadas |

## Bernoulli

Para N paquetes, la pérdida esperada es `N*p`, con varianza `N*p*(1-p)`.
Los eventos son independientes; pueden aparecer rachas por azar. La probabilidad
de dos pérdidas consecutivas es `p²` y la racha media, para `0<p<1`, `1/(1-p)`.

## Gilbert-Elliott implementado

El estado bueno G entrega y el malo B descarta. Se empieza en G por sesión;
para cada paquete se transiciona **antes** de decidir el descarte:

```text
a = P(G → B) = p/2
b = P(B → G) = (1-p)/2
P = [[1-a, a], [b, 1-b]]
```

Para `0<p<1`, la proporción estacionaria de pérdidas es `a/(a+b)=p`, la racha
mala media es `1/b=2/(1-p)` y la autocorrelación es `0.5^k`. Las rachas crecen
al aumentar el porcentaje; no se mantiene una duración fija de dos paquetes.
Con 2 % la racha media es aproximadamente 2,04 paquetes. Una ventana corta puede
diferir de la tasa estacionaria por correlación y estado inicial.

Los extremos son explícitos: 0 % entrega y deja estado bueno; 100 % descarta
siempre. El algoritmo no divide por `1-p`. Usa un generador propio y uniformes
en `[0,1)`, sin modificar el PRNG global del motor. Implementación:
[LossModel.h](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/extension/network/LossModel.h).

## Ciclo de vida

Cambiar `sm_custom_fakelag_loss_mode` o llamar `CFakeLag_SetPacketLossMode`
resetea perfiles, colas y estado del modelo antes de adoptar el nuevo modo.
`player_fakelag` puede reconstruir perfiles tras ese cambio de modo, salvo
cuando los haya descartado la [política LAN](LAN_POLICY.md).
Editar/eliminar un perfil, desconectar, resetear o bloquear LAN limpia su estado.

Las regresiones usan semillas fijas y 2.000.000 de paquetes por porcentaje,
incluidos 0, 1, 10, 20, 50, 80, 99 y 100. Evidencia histórica:
[seguridad](FAKELAG_SAFETY_VALIDATION.md); estado actual:
[matriz de validación](VALIDATION.md). Los modelos no habilitan identidades
nuevas del motor ni eluden la restricción LAN.
