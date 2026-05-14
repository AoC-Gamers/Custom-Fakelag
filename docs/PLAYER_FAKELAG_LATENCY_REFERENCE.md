# Referencia sobre evaluacion de latencia en ms

## Objetivo

Este documento resume la diferencia entre dos formas de evaluar la latencia en
Source:

- el valor crudo reportado por el netchannel
- el valor de ping visible para el jugador en `net_graph`

La idea es dejar una referencia tecnica sobre la diferencia de medicion y
presentacion de los ms, sin depender de una implementacion concreta de plugin.

## Resumen corto

Una forma habitual de medir latencia en SourceMod es consultar la latencia
promedio saliente del netchannel:

- `GetClientAvgLatency(client, NetFlow_Outgoing)`

Ese valor no coincide necesariamente con el `ping` visible en `net_graph`,
porque el cliente aplica una correccion adicional basada en `cl_updaterate`.

En terminos practicos:

- valor crudo del netchannel: mejor para telemetria interna del motor
- valor estimado tipo `net_graph`: mejor para aproximar lo que ve el usuario

## Conceptos base

### Valor crudo

Es el valor obtenido directamente del netchannel, sin correcciones visuales
adicionales.

Un ejemplo comun en SourceMod es:

```sourcepawn
stock float GetAverageOutgoingLatencyMs(int client)
{
	float latency = GetClientAvgLatency(client, NetFlow_Outgoing);
	if (latency < 0.0)
	{
		return -1.0;
	}

	return latency * 1000.0;
}
```

Eso significa:

- latencia promedio
- flujo saliente
- medicion base del canal de red
- conversion de segundos a milisegundos

### Valor visible o estimado

Es el valor que intenta aproximar lo que el jugador percibe en `net_graph`.

Ese valor no es necesariamente igual al valor crudo, porque el cliente aplica
una correccion adicional antes de renderizar el ping.

## Referencias verificadas

### SourceMod

Documentacion publica:

- https://raw.githubusercontent.com/alliedmodders/sourcemod/master/plugins/include/clients.inc

Puntos relevantes:

- `GetClientLatency(int client, NetFlow flow)`:
  - latencia actual
  - mas precisa
  - mas inestable
- `GetClientAvgLatency(int client, NetFlow flow)`:
  - latencia promedio de paquetes
  - mas estable

Ademas, `NetFlow_Both` en SourceMod suma `incoming + outgoing`.

Implementacion publica:

- https://github.com/alliedmodders/sourcemod/raw/refs/heads/master/core/smn_player.cpp

Puntos verificados ahi:

```cpp
if (params[2] == MAX_FLOWS)
{
	value = pInfo->GetAvgLatency(FLOW_INCOMING) +
		pInfo->GetAvgLatency(FLOW_OUTGOING);
}
else
{
	value = pInfo->GetAvgLatency(params[2]);
}
```

Conclusion:

- `NetFlow_Outgoing` no es lo mismo que `NetFlow_Both`
- medir `FLOW_OUTGOING` produce una lectura distinta a sumar ambos flujos

### SDK de Source / L4D2 vendorizado en el repo

Headers e implementaciones relevantes revisadas en:

- `.deps/hl2sdk-l4d2/public/inetchannelinfo.h`
- `.deps/hl2sdk-l4d2/game/client/vgui_netgraphpanel.cpp`
- `.deps/hl2sdk-l4d2/game/server/util.cpp`

Definicion del netchannel:

```cpp
virtual float GetLatency( int flow ) const = 0;
virtual float GetAvgLatency( int flow ) const = 0;
```

## Formula usada por net_graph

En `vgui_netgraphpanel.cpp`, el cliente calcula el ping mostrado a partir de:

```cpp
m_AvgLatency = netchannel->GetAvgLatency( FLOW_OUTGOING );

if ( cl_updaterate->GetFloat() > 0.001f )
{
	flAdjust = -0.5f / cl_updaterate->GetFloat();
	m_AvgLatency += flAdjust;
}

m_AvgLatency = MAX( 0.0, m_AvgLatency );
```

Y luego lo imprime como:

```cpp
Q_snprintf( sz, sizeof( sz ), "fps:%4i   ping: %i ms", (int)(1.0f / m_Framerate), (int)(m_AvgLatency*1000.0f) );
```

Por lo tanto, una aproximacion razonable al ping visible en `net_graph` es:

$$
ping_{netgraph} \approx \max\left(0, GetClientAvgLatency(Outgoing) - \frac{0.5}{cl\_updaterate}\right) \times 1000
$$

En milisegundos, si el valor crudo ya esta convertido:

$$
ping_{netgraph\_ms} \approx \max\left(0, ping_{raw\_ms} - \frac{500}{cl\_updaterate}\right)
$$

## Ejemplos

### Ejemplo 1

- `GetClientAvgLatency(Outgoing) = 0.040`
- valor crudo = `40 ms`
- `cl_updaterate = 40`

Correccion:

$$
\frac{500}{40} = 12.5 ms
$$

Estimado tipo `net_graph`:

$$
40 - 12.5 = 27.5 ms
$$

Eso explica un caso real como:

- medicion cruda: `40 ms`
- `net_graph`: `27 ms`

### Ejemplo 2

- valor crudo = `52 ms`
- `cl_updaterate = 30`

Correccion:

$$
\frac{500}{30} \approx 16.67 ms
$$

Estimado:

$$
52 - 16.67 \approx 35.33 ms
$$

### Ejemplo 3

- valor crudo = `9 ms`
- `cl_updaterate = 60`

Correccion:

$$
\frac{500}{60} \approx 8.33 ms
$$

Estimado:

$$
9 - 8.33 \approx 0.67 ms
$$

Aplicando clamp:

$$
\max(0, 0.67) = 0.67 ms
$$

## Nota sobre el servidor

En `.deps/hl2sdk-l4d2/game/server/util.cpp`, Valve tambien calcula un ping
corregido a partir de `GetAvgLatency(FLOW_OUTGOING)` y aplica ajustes por
`cl_cmdrate` y tick.

Eso refuerza la misma idea:

- el valor crudo del netchannel no siempre es el valor final presentado al usuario
- hay una capa de correccion para acercarlo al ping visible o historico esperado

## Formulas de referencia

### Valor crudo en ms

$$
ping_{raw\_ms} = GetClientAvgLatency(client, NetFlow_Outgoing) \times 1000
$$

### Valor estimado tipo net_graph en ms

$$
ping_{display\_ms} = \max\left(0, ping_{raw\_ms} - \frac{500}{cl\_updaterate}\right)
$$

Donde `cl_updaterate` representa la frecuencia de actualizacion usada por el
cliente para esa evaluacion visual.

## Conclusiones practicas

- el valor crudo y el valor visible no representan exactamente la misma cosa
- `net_graph` no es una lectura directa del netchannel sin procesar
- comparar ambos valores sin contexto puede dar la impresion de que uno de los dos esta mal, cuando en realidad pertenecen a etapas distintas de evaluacion