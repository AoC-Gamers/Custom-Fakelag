# Custom-Fakelag: cambios y validación

> Informe histórico de la primera entrega (`9ab5632`). El estado actual,
> incluido el adaptador Linux y las pruebas posteriores en SRCDS, está en
> [integración del motor](ENGINE_INTEGRATION_VALIDATION.md). Las referencias a
> bloqueo total y ausencia de build Windows describen aquella entrega.

Fecha: 2026-11-13 (America/Santiago). Rama local: `codex/fakelag-safety`.
Estado: correcciones independientes implementadas y probadas; **integración ABI
pendiente y activación bloqueada**. No se desplegó ni publicó esta rama.

## Revisiones y entrega

- Checkout inicial observado: `develop`, `b871f52dc5903308c73cc08bc8348c793844729d`, limpio.
- Se ejecutó `git fetch origin`; main vigente/base del trabajo:
  `430872d40dcafa3dc41c21a707a7523b8db64524`. Incluye el develop observado.
- Correcciones funcionales iniciales: `e3c3767`.
- Separación de propiedad, sesiones y robustez, SHA final de código:
  `9499dc84df232a0b931ab67896704f6450312f5d`.
- Un tercer commit contiene validación, scripts, CI y documentación. Su SHA final
  de entrega se obtiene con `git rev-parse HEAD` después del commit y se informa
  en la respuesta de entrega; no se incrusta el hash del documento en sí mismo.

La API pública de `scripting/include/custom_fakelag.inc`, sus natives/forwards y
los fuentes SourcePawn no cambiaron. La extensión conserva red/cleanup; el plugin
conserva perfiles funcionales de usuario y persistencia.

## Defectos confirmados y evidencia

| Hallazgo | Comprobación propia | Resultado |
|---|---|---|
| Doble liberación al asignar dos buffers | Código original con ASan x86/x64 | `attempting double-free`, salida 1 |
| División por cero GE al 100 % | Expresión extraída de la política original, UBSan x86; aritmética aislada x64 | `division by zero`, salida 1 |
| Reset de perfiles sin vaciar cola | `PlayerLagManager::ClearAll()` original con cola no vacía, ASan/UBSan x86 | `profiles=0 queue=1`, salida 0 del reproducer |
| Copia de punteros internos del lector; capacidad inferida de longitud | Revisión del original y contraste SDK | Confirmado estáticamente; ABI concreto pendiente |
| Resolución sin propagación, notificación posterior al fallo | Revisión de setters originales; regresiones actuales con fallo inyectado | Corregido en lógica aislada |
| NaN/infinito y reentrada tras forwards | Revisión de validaciones originales; casos actuales con inyección | Rechazados sin aplicación ni notificación |
| Segunda copia al insertar lvalue | Original crea copia y llama `add(newPacket)`; owner actual no copiable | Eliminada por construcción movible y comprobación de tipos |

Ninguno de los tres fallos críticos resultó corregido en el main vigente.
El reproducer del reset demuestra la ruta lógica perfil/cola, no descarga un
plugin dentro de un servidor. La prueba de la división usa la expresión original,
no el callback completo cargado en SourceMod.

## Decisiones de implementación

- `EnginePacketView` es prestada; `QueuedPacket` posee exclusivamente un
  `unique_ptr<unsigned char[]>`. Copia/asignación por copia están prohibidas;
  movimiento y autoasignación por movimiento se prueban con sanitizers. No se
  almacena ningún puntero del lector ni el puntero prestado al encolar.
- Una copia de payload motor→owner; heap, extracción y limpieza mueven owners.
  No se añadieron pools ni se afirma mejora de rendimiento medida.
- `SessionId` representa una generación de perfil de una conexión. Cambiar un
  perfil invalida su generación anterior; desconexión/reutilización de slot usa
  identidad cacheada, incluso si la resolución de dirección ya falla. Reset no
  reinicia el contador de generaciones. Un address no puede pertenecer a dos
  clientes perfilados simultáneamente.
- Modificar/eliminar un perfil descarta sus pendientes; no se reprograman ni se
  envían de inmediato. El reset total limpia todos los perfiles, colas, payloads,
  almacenamiento de metadatos y estados GE, aunque el cliente ya no sea consultable.
  Los contadores históricos sobreviven al reset. Reset repetido es idempotente.
- `LevelShutdown`, desconexión, reutilización de slot, descarga y desactivación
  lazy conectan con la misma limpieza. Cambios de modo por native se efectúan
  mediante la misma ConVar y su callback que los cambios directos de consola.
  Cambiar modo de pérdida o modo de detour hace reset. Si always-on falla se
  rechaza/revierte su activación. La ejecución de estos hooks en SRCDS está pendiente.
- Hora original `received` y `releaseAt` son independientes. Se programa desde
  `net_time` actual y no se cambia la hora original visible al restaurar.
  Empates tienen secuencia estable; en un socket los paquetes de una sesión no
  adelantan a sus anteriores si disminuye la latencia. Otras sesiones con plazo
  anterior no quedan bloqueadas. No se certifica orden entre sockets distintos.
- `EnginePacketAdapter` exige capacidad explícita independiente de longitud de
  payload/lector. Si una restauración falla, se descarta una vez, se cuenta y se
  intenta el siguiente listo; no hay retry infinito ni escritura parcial permitida.
- Wrappers `SessionId`, `Milliseconds`, `EngineTime` y `LossPercentage` evitan
  mezclar dominios en la cola/modelo. Los valores de la API se validan antes de
  forwards y después de ellos: finitos, latencia 0–10000 ms, pérdida 0–100 %.
  Diez segundos es un límite operativo generoso para simulación, no una propiedad
  demostrada del engine. Limita retención junto con los presupuestos siguientes.
- Límites por sesión: 256 paquetes / 2 MiB de payload. Globales: 4096 / 32 MiB.
  Máximo por paquete: 65536 bytes como límite interno, no como inferencia de la
  asignación del motor. Saturación descarta el nuevo paquete. `PacketCounters`
  separa pérdida solicitada, saturación, restauración fallida, ciclo de vida e
  invalidación de captura. Metadatos del vector también tienen crecimiento
  acotado por el número máximo de entradas; se liberan al reset total.
- Aplicación atómica de latencia+pérdida con comprobación de resolución y detour
  antes de commit/notificación. Guardas y revisión de estado rechazan mutación
  anidada, resultados inválidos y reset/desconexión durante pre-forwards.
- Protección de páginas para activar el detour devuelve fallo y cubre spans que
  cruzan páginas. Se validan longitud del trampolín y asignación. Pruebas usan
  páginas sintéticas; no parchean código del motor.

## Modelo de pérdida y resultados nuevos

Para `p=porcentaje/100`, GE usa `a=p/2`, `b=(1-p)/2`.
Primero transiciona y después emite: entrar en malo descarta, salir entrega.
`pi_B=a/(a+b)=p`; la ráfaga mala es geométrica de media `1/b=2/(1-p)`;
`rho(k)=(1-a-b)^k=0.5^k`. No se intenta mantener simultáneamente ráfagas de
longitud dos para porcentajes altos. 0 % y 100 % tienen ramas exactas.

PRNG: `std::mt19937`; uniformes `generate_canonical<double,53>`. El modelo no
modifica `std::rand` global del motor. Prueba con semilla `0xCF123 + porcentaje`,
2 000 000 de paquetes por caso, inicio bueno. Resultados obtenidos en esta tarea:

| Objetivo % | Efectivo % | Media de ráfaga observada | Ráfagas |
|---:|---:|---:|---:|
| 0 | 0 | 0 | 0 |
| 1 | 0.9938 | 2.02053 | 9837 |
| 10 | 10.0466 | 2.22454 | 90325 |
| 20 | 19.9922 | 2.49888 | 160010 |
| 50 | 50.0303 | 4.002 | 250026 |
| 80 | 80.014 | 10.0166 | 159762 |
| 99 | 99.0108 | 201.898 | 9808 |
| 100 | 100 | 2000000 (ventana completa) | 1 |

Tolerancia de tasa en fracción: `8*sqrt(3*p*(1-p)/N)+20/N`.
El factor tres es la autocorrelación integrada `(1+rho)/(1-rho)` con rho=0.5;
se incluye margen de arranque. Ráfagas: `8*sqrt(mu*(mu-1)/runs)+mu/runs`,
con `mu=2/(1-p)`, margen para censura de la ventana. Son tolerancias estadísticas
aproximadas conservadoras del arnés, no una garantía para ventanas arbitrarias.
0/100 se comprueban exactamente. También se prueba el orden entrada/salida.

## Comandos reproducibles y entorno

Host: elementary OS 8, Linux x86_64, GCC 13.3.0.
Faltan cabeceras multilib en el host: `make build-exts-linux` falló inicialmente
con `bits/libc-header-start.h: No such file or directory`. No se instalaron
paquetes del sistema; se usó contenedor Ubuntu 24.04 con GCC 13.3.0 multilib.

```bash
make deps-exts-linux
SANITIZE=1 make test-exts-linux
make build-smx

docker build -t custom-fakelag-validation:local - < tests/Dockerfile.linux-validation
# Montar el repositorio en /work, como usuario propietario del checkout:
docker run --rm -v "$PWD:/work" -w /work --user "$(id -u):$(id -g)" \
  custom-fakelag-validation:local \
  python3 tests/reproduce_reference_defects.py --arch 32

docker run --rm -v "$PWD:/work" -w /work --user "$(id -u):$(id -g)" \
  custom-fakelag-validation:local bash -c '
    TEST_ARCH=32 SANITIZE=1 make test-exts-linux &&
    python3 -m venv .deps/exts-linux/.venv-container &&
    .deps/exts-linux/.venv-container/bin/pip install .deps/exts-linux/ambuild &&
    VENV_DIR=/work/.deps/exts-linux/.venv-container make build-exts-linux'
```

Los comandos anteriores se ejecutaron por etapas equivalentes. El reproducer
escribe comandos exactos, logs y `results.json` en `.build/reference-defects/`.
Resultados: copy→salida 1 con ASan double-free; loss→salida 1 con UBSan division
by zero; reset→salida 0 con `profiles=0 queue=1` (defecto esperado).

La suite actual pasó con `-Wall -Wextra -Werror`, ASan y UBSan en x64 y x86.
Las pruebas transportan paquetes sintéticos (`UNIT_TEST`); los servicios y las
colas/política son código real, pero las fronteras de detour, registro de clientes
y adaptador son dobles de prueba. Cubren ownership, límites, destino insuficiente,
restauración fallida sin bloqueo, orden, identidad de reconexión, limpieza,
lazy/always-on, error de resolución/activación y reentrada. El camino sin perfiles
produce Bypass para ambos valores de newdata y el detour delega al original.

Extensión Linux x86: `Build succeeded`, con link `--no-undefined`, sin warnings.
SourcePawn: compilador 1.12.0.7260, `player_fakelag.smx` compilado sin warnings.
Los jobs Linux/Windows de CI ahora ejecutan regresiones antes del build; CI remoto
no se ejecutó porque no se publicó la rama.

Revisiones de dependencias usadas:

- HL2SDK: `2a31cd007b2d7d2f964dc093eedcf7a812cf9dd6`.
- SourceMod: `3f7460671f7adc4a3c6791a47d21ba3e7b5fba91`.
- Metamod: `4e031eb571f5978eea8207b5d915c9cd0e8d6c58`.
- AMBuild: `5b0aa725beef33c9cf6a1b00659a010c3d9120d3`.
- Base Ubuntu por digest: véase `tests/Dockerfile.linux-validation`.

Artefactos locales (no desplegados):

- `.build/linux-l4d2/package/addons/sourcemod/extensions/custom_fakelag.ext.so`:
  SHA-256 `56777610c309599f5e956dc6ada27663f0cb480f5faec52cbc8fc624f0b6a115`.
- `.build/plugins/addons/sourcemod/plugins/player_fakelag.smx`:
  SHA-256 `6165876b11a93e2ce7f1f42bfd344ae8c333757e971aebcf9f85bbbc5d81a12d`.
- Logs complementarios locales: `tmp/validation/` (ignorado por git).

## Compatibilidad y pendientes concretos

| Evidencia | Linux x86 | Windows x86 |
|---|---|---|
| Revisión estática | Realizada | SDK y código portable revisados |
| Prueba aislada | ASan/UBSan aprobados | No ejecutada; falta host MSVC |
| Compilación extensión | Aprobada | Pendiente |
| Binario objetivo identificado | No | No |
| Resolución efectiva / firmas únicas | Pendiente | Pendiente |
| SRCDS carga/descarga/tráfico/mapa/reconexión | No ejecutado | No ejecutado |
| Listo para producción | **No** | **No** |

Para completar aceptación: obtener módulos concretos y su identidad/build,
implementar y verificar el adaptador por plataforma, resolver funciones y tiempo
en runtime, ejecutar MSVC y probar los hooks reales con tráfico, cambio de mapa,
conexiones y ambos canales de cambio de modo. La reconstrucción del lector y la
capacidad física en `newdata=false` siguen pendientes. El adaptador actual no
implementa esa parte y no hay una opción que habilite fake lag sobre supuestos.

[La referencia SDK/runtime](SDK_RUNTIME_REFERENCES.md) registra el contraste con
SDK y el catálogo ELF de L4D2node. No se modificó gamedata sin evidencia nueva del
módulo objetivo. No se certifica Windows a partir de ELF, ni runtime a partir del
build o de las simulaciones.
