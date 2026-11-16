# Informes efectivos de balance · 16-11-2026

Base: `77f1200512f81380e6e9b829c17f14efaf00f3b2`, coincidente con `develop`
al iniciar. Corrección: `baab61b`; arnés: `aafa0f5`. Trabajo local en
`codex/fakelag-effective-tables`. Ese fue el estado de la entrega local.
Tras autorización, se integró `3006a70` en `develop` y pasó el
[CI de Linux, Windows y SourcePawn](https://github.com/AoC-Gamers/Custom-Fakelag/actions/runs/43915079651),
incluida la publicación automática del canal. No se desplegó en servidores.

## Reproducción y corrección

La reproducción usó el producto anterior **antes de editarlo**, dentro de un
SRCDS Linux aislado con clientes/natives simulados:

| Caso | Informe anterior | Perfil consultado | Informe corregido |
|---|---|---|---|
| Global, latencia modificada | 40 ms / 2 % | 40 ms / 3 % | 40 ms / 3 % |
| Pareja, latencia modificada | Propuesta de 100 ms | 40 ms / 3 % | Resultado individual de 40 ms / 3 % |
| Pareja vetada | Ajuste de 100 ms | 0 ms / 0 % | Sin cambio confirmado, 0 ms / 0 % |
| Sin pareja, clear vetado | Limpieza / 0 % | 25 ms / 15 % | Sin cambio confirmado, 25 ms / 15 % |

[Reproducción y fallo esperado sobre la base](runtime/plugin-table-baseline-2026-11-16.json).
La suite nueva se compiló también contra los fuentes archivados de `77f1200`:
rechazó las filas antiguas. No es una comparación estática del texto fuente.

La implementación utiliza una selección por operación y un perfil propuesto por
sesión. Mantiene emparejamiento, cálculo y orden de aplicación originales: primero
el miembro con mayor ping de cada pareja. Comandos, API silenciosa y voto usan
la misma aplicación; el informe no vuelve a ejecutarla.

La vista previa muestra propuestas sin setters, clears ni forwards. La aplicación
muestra una fila por participante, incluyendo ambos miembros y los jugadores sin
pareja. Latencia y pérdida son celdas tipadas del perfil observado, sin recalcular
la heurística al presentar. Un clear convertido en perfil activo cuenta como
ajuste. Un perfil idéntico se etiqueta «sin cambio confirmado», sin inventar veto.

Los nombres y userid se capturan al seleccionar. Los perfiles se observan al
volver de las natives y se validan al terminar la aplicación. Identidad, generación,
LAN o perfil modificados por un forward posterior invalidan la observación.
La operación se detiene si una native devuelve un resultado no disponible; las
filas desconocidas usan `-`, no ceros. Si cambia la generación/política, se omite
el panel anterior. Las notificaciones de cambios se emiten después de validar el
conjunto, evitando anunciar un resultado que ya invalidó otro forward.

El resumen cuenta únicamente observaciones válidas. Las operaciones parciales se
identifican como incompletas. La API conserva sus firmas y devuelve false cuando
no puede confirmar la operación completa; un veto observable como estado idéntico
sigue siendo normal. Las excepciones nativas se propagan antes de presentar filas.
El informe describe ese instante, no garantiza que otro plugin no cambie el estado
posteriormente. La tabla reutiliza la biblioteca existente y pagina tras 32 filas.

## Validación ejecutada

[Resultado por SHA y filas renderizadas](runtime/plugin-table-results-2026-11-16.json).

- **177 aserciones en inglés y 177 en español**, casos FL02-R01–R16: consultas,
  celdas reales, formato de filas, notificaciones, resumen y contadores; incluye
  vetos Handled/Stop, pérdida retenida, pérdida sola, clear modificado, estado
  idéntico, previews sin efectos, slots reutilizados, LAN/clear-all reentrantes,
  errores inyectados y rutas desde comando, native registrada y callback de voto.
- **44 regresiones anteriores y cinco ejecuciones del muestreador**, con dos
  cambios de mapa y dos recargas. Sin excepciones inesperadas; las inyectadas
  se registran por separado. BuiltinVotes está simulado, no validado en vivo.
- `make deps-smx` y `make build-smx`; compilación explícita del arnés y de
  `balance_report_consumer`, `windows_public_api`, `windows_shutdown_consumer`
  y `windows_shutdown_fill_consumer`: SourcePawn **1.12.0.7260**, sin warnings.
- `SANITIZE=1 make test-exts-linux` y la misma suite con `TEST_ARCH=32` en el
  contenedor Ubuntu 24.04/GCC 13.3: ASan/UBSan aprobados, transporte sintético.
- Seis tests Python de exportadores/verificador aprobados en el venv existente.

Host del arnés: L4D2 **2.2.4.3/10097**, SourceMod **1.12.0.7260**, Metamod
**1.12.0-dev+1228**, sin red, contenido Valve en solo lectura y gamedir privado.
`sb_all_bot_game 1` mantiene la simulación; ningún bot acredita aceptación humana.
Se mantiene el aviso histórico de fallback de `gEntList` del core; este arnés no
certifica gamedata, ABI ni tráfico. No cambiaron extensión, firmas, gamedata,
algoritmo de pérdida, límites, timers, persistencia ni política LAN.

## Repetir y completar la aceptación

La [receta del arnés](PLUGIN_PENDING_VALIDATION.md#repetir-el-arnés-linux) sigue
vigente. Su runner ahora ejecuta `cf_plugin_tables` en inglés y español antes de
los mapas/recargas y guarda `table_checks`, filas y excepciones en el JSON indicado
por `--output`. Los arneses y el consumidor manual no se empaquetan con el producto.

Pendiente: cliente Steam, extensión real y BuiltinVotes real **por separado en
Linux y Windows**. También siguen pendientes las matrices LAN/Steam anteriores.
Procedimiento mínimo, en un servidor privado con al menos tres humanos (dos de
un equipo y uno del contrario), registrando SHA, versiones y hashes:

1. Compilar `tests/balance_report_consumer.sp` con los mismos includes que el
   arnés, instalarlo solo en pruebas y cargarlo con
   `sm plugins load balance_report_consumer`. Identificar los userid con `status`.
2. Ejecutar `sm_fakelag_preview global` y `sm_fakelag_preview pairs`; comparar
   `cf_balance_snapshot` antes/después. No deben cambiar perfiles ni persistencia.
3. Ejecutar ambos balances con `cf_balance_control <userid> allow`, después con
   `handled` y con `stop`. Consultar `cf_balance_snapshot`; comparar cada fila,
   notificación y resumen, incluyendo el participante sin pareja.
4. Usar `cf_balance_control <userid> modify 40`, volver a aplicar y contrastar la
   fila con la consulta. Para probar pérdida sin recalcular, partir de una
   propuesta con pérdida positiva y modificar a una latencia menor que
   `sm_fakelag_loss_added_floor_ms` (por ejemplo 1 ms). La pérdida efectiva debe
   seguir coincidiendo con la consulta, aunque otra heurística sobre 1 ms daría 0.
5. Con control `allow`, preparar `cf_balance_profile <userid> 0 15`; vetar su
   clear y luego permitirlo. Repetir un clear con `modify 25.5`: debe figurar como
   ajuste, con el perfil completo real. Probar desconexión durante forward,
   cambio de mapa y resultado de voto con la extensión BuiltinVotes real.
6. Desde el cliente administrador ejecutar `sm_fakelag_clear_all`; descargar
   el consumidor de pruebas. Sanitizar identidades/IP antes de compartir logs.

El consumidor controla un userid y se desarma al desconectar o cambiar mapa. No
omite la validación del motor ni el bloqueo LAN. Sus comandos son de consola de
servidor. No fue ejecutado aquí con humanos: solo se verificó su compilación.

Al cerrar la fase local, el CI nuevo no se había ejecutado porque el encargo
excluía publicar releases. La autorización posterior de push permitió ejecutar el
workflow `43915079651` de `3006a70`, aprobado en todos sus jobs. El CI compila los
consumidores y ejecuta las suites nativas; no ejecuta el SRCDS privado del arnés.
La implementación de FL-02 queda cubierta por compilación y filas comprobadas;
la aceptación operativa con clientes reales sigue pendiente.
