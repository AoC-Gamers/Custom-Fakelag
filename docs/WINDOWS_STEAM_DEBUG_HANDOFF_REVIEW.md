# Revisión e integración de Steam Lifecycle Debug

14-11-2026, America/Santiago. Base `070a71b`, diez commits Windows hasta
`bf0882ea37495b1252c8cdb763403c2b78d2148d`, conservados por fast-forward.
Los diez archivos locales sin publicar del diagnóstico coincidían byte por byte
con la entrega; se incorporaron sin descartar ni mezclar cambios ajenos.

## Integridad y evidencia

Se verificaron los SHA-256 de los 75 archivos de la entrega. Bundle SHA-256:
`a5d082dce4c2874e3328e5adb3427e7c6138431b51d34ec21443e46f2a2dbd4e`.
Git verificó el bundle incremental y su base. Se revisaron las herramientas y
se contrastaron los 18 trial.json contra el resumen: tres procesos por cada
combinación de vanilla/SM/SM+observador y LAN 1/0, con handles señalados,+códigos concordantes y ninguna terminación forzada.

Se verificó independientemente PE32 I386 y coincidencia GUID/age entre DLL y PDB:
`1f8aa4a4-b60c-40bf-800a-1fcdbe3f19e3`, age 1. DLL SHA-256:
`04c54a453f115dc59e7df3198cea51150c9aca5459d583d9bca97735c06997ca`.
No se importaron DLL, PDB ni dumps al historial Git.

El [informe Windows](WINDOWS_STEAM_DEBUG_VALIDATION.md) conserva el resultado
de servidor y sus límites. La [matriz estructurada](runtime/windows-steam-debug-matrix-2026-11-14.json)
se importó sin cambiar sus datos. LAN 1 falló 9/9 tras mapa y desconexión;
LAN 0 reconectó y cerró con salida 0 en 9/9. El observador detectó cadenas fuera
de Steam después del mapa en los tres C1. Las copias son no atómicas: el log por
sí solo no acredita una liberación ni sustituye el contexto de excepción.

El caso CDB vanilla conserva ejecución inválida en cero con retorno a
server+0x1e1226 y detección posterior durante teardown en engine+0x161316.
No se observó ni se atribuyó el subcódigo histórico de 0xc0000409.
La DLL histórica tenía predeterminado 2; modo 0, modos 1/2 y descarga/recarga
quedaron comprobados externamente. Tras revisar la entrega, el usuario pidió
restaurar predeterminado 0: el código actual carga apagado y el recolector
activa 2 explícitamente durante las pruebas. Se conserva una opción para repetir
la DLL histórica sin confundir revisiones. El nuevo valor requiere su propia
comprobación de carga real; los 18 ensayos corresponden al binario anterior.
No se implementa un fix ni se cambia código de producción de Custom-Fakelag.

## Validación local y CI

En Linux se repitió el fixture C++ x86 con ASan/UBSan y la compilación ELF32
independiente. Pasaron tres regresiones nuevas de exportación y lectura de
trazas, además de la prueba previa de privacidad; se comprobó sintaxis Python.
No se ejecutó SRCDS Windows en Linux: los ensayos humanos son evidencia externa.

El CI ahora compila y prueba este diagnóstico en Linux x86 y Windows x86,
con artefactos separados del paquete normal. Las regresiones de exportación
evitan contar filas antiguas de status y comprueban que no salgan datos privados.
El resultado del workflow del commit integrado es evidencia de compilación y
pruebas aisladas, separada de los 18 ensayos registrados en Windows.
