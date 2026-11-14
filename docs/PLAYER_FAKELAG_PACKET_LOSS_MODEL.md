# Severidad de pérdida calculada por player_fakelag

El plugin calcula un porcentaje heurístico a partir del ping base B, la
latencia agregada A y el objetivo T, en milisegundos. La extensión aplica ese
porcentaje usando [Bernoulli o Gilbert-Elliott](CUSTOM_FAKELAG_PACKET_LOSS_MODES.md).
Es una regla de balance; no reproduce por sí sola todas las condiciones de una
conexión real ni añade jitter.

## Fórmula vigente

Para B y T válidos y A mayor que cero:

```text
baseFactor   = clamp((baseCeiling - B) / baseSpan, 0, 1)
targetFactor = clamp((T - targetFloor) / targetSpan, 0, 1)
addedFactor  = clamp((A - addedFloor) / addedSpan, 0, 1)
lossFloat    = clamp(maxPercent * baseFactor * targetFactor * addedFactor,
                     0, maxPercent)
lossPercent  = lossFloat > 0 ? ceil(lossFloat) : 0
```

Entradas inválidas o latencia agregada no positiva producen 0 %. La fuente
canónica es `FakelagResolvePacketLossPercent` en
[latency.sp](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/scripting/player_fakelag/latency.sp).

| ConVar | Predeterminado |
|---|---:|
| `sm_fakelag_loss_base_ceiling_ms` | 60 |
| `sm_fakelag_loss_base_span_ms` | 40 |
| `sm_fakelag_loss_target_floor_ms` | 35 |
| `sm_fakelag_loss_target_span_ms` | 40 |
| `sm_fakelag_loss_added_floor_ms` | 20 |
| `sm_fakelag_loss_added_span_ms` | 35 |
| `sm_fakelag_loss_max_percent` | 3 |

El último parámetro admite 0–100 %. Los valores 2 %, suelo 40 ms y mínimo
agregado 25 ms de versiones anteriores no son los predeterminados actuales.

## Ejemplos con valores predeterminados

| B | T | A = T-B | Pérdida |
|---:|---:|---:|---:|
| 20 | 30 | 10 | 0 % |
| 20 | 60 | 40 | 2 % |
| 20 | 90 | 70 | 3 % |
| 45 | 80 | 35 | 1 % |
| 80 | 110 | 30 | 0 % |

`CFakeLagNetworkProfile` agrupa `lagMs` y `packetLossPercent`. El porcentaje
solicitado no garantiza una tasa idéntica en una ventana corta. El bloqueo de
[LAN](LAN_POLICY.md) impide aplicar cualquier perfil no nulo salvo excepción
explícita para pruebas.
