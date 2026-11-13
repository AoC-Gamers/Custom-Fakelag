# Revisión e integración de la entrega Windows

Fecha: 2026-11-13. Base local y remota comprobada: `7c72156`.
Entrega recibida: siete commits, hasta
`c5a75790c5d177b8ae751c1d73bdaf3e7571575d`.
Se integraron por fast-forward, conservando los commits y su autoría.

## Integridad y revisión

- Se comprobaron los SHA-256 de los 70 archivos del manifiesto de entrega:
  cero discrepancias. Bundle SHA-256:
  `0efce19e82309e987ca0e517b444b9560e9c80b42ba3c06ec7c11d1765411262`.
- `git bundle verify` aprobó el historial; la base coincide con el develop local.
- Los cuatro JSON de evidencia Windows del bundle coinciden semánticamente con
  los entregados por separado.
- Se revisaron comprobación PE/ASLR, capacidad, región/tabla de paquetes, byte
  stream no preparado, build y cambio de ejecución de listeners SourcePawn.
- No se importaron DLL/SMX ni binarios de Valve al historial. Los builds normales
  y los de prueba de la entrega siguen separados.

La corrección de listeners tiene respaldo en el código de SourceMod usado:
`CForward::Execute` recoge resultados de los callbacks exitosos y no propaga
como retorno el error de un listener. El bridge nuevo ejecuta los listeners por
separado y conserva handles/serials, para abortar el cambio ante una excepción
sin mantener punteros de plugins que hayan sido descargados o recargados.

## Comprobaciones repetidas en Linux después de importar

| Comprobación | Resultado |
|---|---|
| Regresiones C++ x64, ASan/UBSan | Aprobado |
| Regresiones C++ x86, ASan/UBSan | Aprobado, Ubuntu 24.04/GCC 13.3 en contenedor |
| Extensión Linux ELF32 | Compilada sin errores ni warnings nuevos |
| Plugin normal SourcePawn | Compilado con 1.12.0.7260 sin warnings |
| `tests/windows_public_api.sp` | Compilado explícitamente sin warnings |
| Verificador Python | Dos pruebas aprobadas: patrones ambiguos/solapados e identidad desconocida |
| Scripts Python de la entrega | Comprobación de sintaxis aprobada |

Comandos: `SANITIZE=1 make test-exts-linux`; misma suite con `TEST_ARCH=32` en
el contenedor `custom-fakelag-validation:local`; `make build-exts-linux` dentro de
ese toolchain; `make deps-smx`, `make build-smx` y `spcomp` explícito para el arnés.
El verificador se ejecutó con pefile 2024.8.26 y Capstone 5.0.9 en venv local.
Logs de esta revisión: `tmp/validation/windows-handoff-*` y
`tmp/validation/windows-verifier-review.log` (no versionados).

No se repitió aquí SRCDS Windows ni se ejecutaron sus DLL. La evidencia Windows
es la recibida y verificada; tampoco se repitió el runtime Linux en esta revisión.
El JSON `windows-validation-2026-11-13.json` corresponde a la fase aislada previa;
el resultado dedicado/humano posterior está en `windows-runtime-2026-11-13.json`.

## Resultado funcional y límites que permanecen

Según la entrega final: 32 casos UDP y 17 checks API con un cliente Steam real,
plugin normal, reconexión en el mismo slot, mapa y retirada/recarga de la extensión
aprobados para la DLL identificada. Se comprobó restauración de bytes del detour.
Los detalles y hashes están en [validación Windows](WINDOWS_ENGINE_VALIDATION.md).

El cierre completo de SRCDS sigue fallando con `0xc0000409`; se reprodujo el mismo
código de salida en un proceso nuevo sin mods. Eso impide declarar el entorno
completamente sano, aunque los casos funcionales hayan pasado. El runner conserva
exit 1 para ese cierre fallido. La causa exacta no queda atribuida exclusivamente
a Custom-Fakelag ni resuelta por esta integración.

La comprobación estricta de la sección ejecutable exige inicializar Custom-Fakelag
antes de que Left4DHooks parchee el motor. La recarga aceptada retira primero sus
dependientes y Left4DHooks y los carga después. Se conserva esa restricción; no se
relajó la identidad del módulo ni se afirma compatibilidad con otros hashes o
con una carga de producción prolongada.
