# Referencia de diseño de tablas de consola

Esta es una propuesta histórica de extracción de helpers, no una API de producto
ni una tarea pendiente autorizada. El plugin actual consume `console_table.inc`
y mantiene en [balance.sp](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/scripting/player_fakelag/balance.sp) la lógica del
reporte. El include externo no se añade al ZIP por documentar este diseño.

## Contrato propuesto

Un panel reúne cabecera opcional, tabla tipada y pie opcional. El renderizador
resuelve anchos, bordes, alineación y truncado; el consumidor conserva traducción,
permisos, selección de audiencia y reglas de balance.

Las celdas admiten string, int y float. Strings se alinean a la izquierda y
números a la derecha por defecto. Los anchos se mantienen estables por reporte;
la consola usa truncado seguro y una leyenda para nombres que no caben.

| Límite sugerido de la propuesta | Valor |
|---|---:|
| Ancho del panel | 96 |
| Líneas de cabecera/pie | 8 por sección |
| Columnas | 8 |
| Filas | 32 |
| Buffer de texto por celda | 128 |

Una extracción futura debería reutilizar bordes, secciones, truncado ASCII y
leyendas UTF-8 ya presentes, fijar tipos panel/tabla y migrar solo el renderizado.
Estos límites y los nombres de API propuestos originalmente no describen un
contrato implementado ni justifican mover lógica de negocio a la biblioteca.
