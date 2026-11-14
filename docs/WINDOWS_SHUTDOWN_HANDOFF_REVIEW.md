# Revisión de la entrega de investigación del cierre Windows

Entrega revisada el 13-11-2026 (America/Santiago), base `65031fb`, cuatro commits
hasta `3f63ba8c858b97ee78a2b838a0d6dfccb957dd39`, integrados por fast-forward.

## Integridad y alcance

- Los SHA-256 de los 31 archivos del manifiesto coinciden. Bundle SHA-256:
  `b3810a466e33c7297a9ea8d5897eae28652799e8b24c35ca9071faee60b80f86`.
- `git bundle verify` aprobó el historial y su base. Los documentos y registros
  importados coinciden con la entrega externa, normalizando finales de línea.
- Se revisaron los recolectores, configuración de filas, observación de módulos,
  captura de excepciones, exportación y fixtures. No se importaron dumps ni
  binarios de Valve. El código de extensión y plugin de producción no cambia.
- Se contrastaron los 45 registros: 35 controles básicos con salida 0 y proceso
  señalado; 10 ensayos extendidos, con resultados desconocidos/suplementarios
  conservados explícitamente. Los tres pilotos excluidos no cuentan como ensayos.

## Conclusión que permite la evidencia

El [informe técnico](WINDOWS_SHUTDOWN_INVESTIGATION.md) demuestra una reproducción
actual del fallo de interfaces Steam después de cambiar de mapa con `sv_lan 1`,
también en vanilla. Los watches observan invalidación de los objetos durante
`SteamGameServer_Shutdown`; `server.dll` utiliza después una interfaz almacenada
que ya no es válida. Se distinguen esa primera excepción y las detecciones
posteriores durante teardown.

En A14, LAN 0 conservó interfaces válidas y permitió cerrar con salida 0. A15
restauró LAN 1 y reprodujo `0xc0000005`. F12/F13 cerraron con salida 0 bajo LAN 0,
incluyendo ambos proveedores, recargas, mapa y reconexión; F13 aplicó perfiles
reales. Son secuencias escalonadas, no una estimación estadística por factor.

Esta reproducción no necesita Custom-Fakelag ni Left4DHooks. No demuestra la
ausencia de otro fallo ni atribuye los antiguos `0xc0000409`: sus dumps y
subcódigos no están disponibles. Tampoco identifica con símbolos privados la
instrucción exacta que debería renovar el contexto en los binarios de Valve.
No se despliega LAN 0 ni se implementa una corrección del motor.

## Validación de integración

En Linux pasaron las regresiones C++ x64 con ASan/UBSan, la prueba de privacidad
del exportador y la comprobación de sintaxis Python. Se compiló el plugin normal
y los dos consumidores opt-in con SourcePawn 1.12.0.7260 sin warnings nuevos.
No se ejecutó aquí SRCDS Windows; los ensayos con cliente son evidencia externa.

El workflow incorpora el exportador y compilación de consumidores en Linux,
y seis regresiones de recolección real en Windows, incluida la ventana de
DLL detach en la que existe un exit status pero el proceso aún no terminó.
Estas pruebas no requieren Steam ni binarios de Valve y no son aceptación SRCDS.
El resultado del CI se consulta en el run del commit integrado, separado del
resultado de servidor consignado en los JSON.
