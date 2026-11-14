# Latencia medida y ping mostrado

`player_fakelag` toma `GetClientAvgLatency(client, NetFlow_Outgoing)` en segundos
y lo convierte a milisegundos. `NetFlow_Both` suma incoming y outgoing: no es
intercambiable con outgoing ni debe sustituirse para ajustar un valor visual.

## Muestreo y estimación

La ventana predeterminada es de cinco muestras cada segundo. Con una/dos se
promedia; con tres se usa la mediana; con cuatro se promedian las dos centrales;
con cinco se descartan mínimo y máximo y se promedian las restantes.
Se resta la latencia artificial aplicada y se limita a cero para estimar el
ping base del balance. Es una estimación, no una medición independiente de RTT.

Para aproximar la lectura de net_graph cuando existe `cl_updaterate` válido:

```text
raw_ms      = GetClientAvgLatency(Outgoing) * 1000
base_ms     = max(0, raw_ms - applied_fakelag_ms)
display_ms  ≈ max(0, measured_ms - 500/cl_updaterate)
```

La corrección de visualización no cambia los paquetes ni el perfil aplicado.
Si no hay updaterate válido, se conserva el valor medido. Ejemplos de la
corrección: 50 ms con updaterate 100 se muestran como unos 45 ms; 50 ms con
updaterate 20, como unos 25 ms. No certifican lo observado en un cliente real.

## Referencias de implementación

- [Código del plugin](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/scripting/player_fakelag/latency.sp): muestreo, resta de
  fakelag y `FakelagEstimateNetGraphPingMs`.
- SourceMod: `plugins/include/clients.inc` y `core/smn_player.cpp`, en las
  dependencias `.deps/exts-linux/sourcemod-1.12/` o equivalentes Windows.
- HL2SDK L4D2: `public/inetchannelinfo.h` y
  `game/client/vgui_netgraphpanel.cpp` en `.deps/exts-linux/hl2sdk-l4d2/`.
  El cliente revisado usa `GetAvgLatency(FLOW_OUTGOING)`, resta
  `0.5/cl_updaterate`, limita a cero y convierte a ms.

La retención observada por la extensión según `net_time` no equivale al ping de
net_graph. Conserva separadas medición del servidor, estimación visual y evidencia
con cliente; véase [validación](VALIDATION.md).
