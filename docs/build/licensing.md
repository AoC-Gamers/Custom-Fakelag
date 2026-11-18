# Procedencia y licencia

El texto en `LICENSE` coincide con el de ProdigySim en `5f1ea1b`. Los cambios
propios mantienen el texto de licencia del repositorio. El historial Git
conserva la atribución de esas contribuciones. Eso no sustituye la identificación
individual cuando una fuente contiene material incorporado de terceros.

| Rutas o entradas | Evidencia disponible |
|---|---|
| `extension/cdetour/{detours.cpp,detours.h,detourhelpers.h}` | Cabeceras AlliedModders, GPLv3 y excepciones originales |
| `extension/asm/*` | Incorporado desde SourceMod en `3f0085b`; los archivos carecen de cabecera. Confirmar alcance de la licencia de esa revisión |
| `extension/libudis86/*` | Atribución a Vivek Thampi y términos de redistribución en las cabeceras. `itab.c` y `itab.h` son tablas generadas por udis86; las condiciones se conservan en las cabeceras originales |
| SourceMod `public/smsdk_ext.cpp` | Compilado desde el SDK. El aviso general está en `licenses/LICENSE.txt` del SDK de SourceMod; verificar contra la revisión efectiva del build |
| `scripts/deps/includes/builtinvotes*.inc`, `left4dhooks_stocks.inc` | Cabeceras GPLv3 y atribuciones en sus cabeceras originales |
| `scripts/deps/includes/colors.inc` | La copia identifica autores y versión 1.3.2. Sus términos de licencia no figuran en la cabecera; falta verificar su origen y la incorporación al SMX |
| HL2SDK | El build usa cabeceras y bibliotecas de ambos SDK de plataforma. Falta determinar qué código de archivos estáticos entra al binario y los avisos aplicables |
| `tests/fixtures/*` y archivos sin cabecera | Mantener los fixtures y sus hashes. Resolver la atribución por rutas a partir de la procedencia antes de declarar cobertura completa del inventario |

Las fuentes copiadas y los fixtures se conservan con sus bytes originales.
Cualquier identificación adicional debe distinguir la licencia del texto de
`LICENSE` de la evidencia específica de cada archivo o grupo de archivos.
El instalador incluye el `LICENSE` del proyecto. Sigue pendiente verificar
la reproducción de los avisos de terceros para los binarios distribuidos.
La validación de estructura y contenido no resuelve ese punto.
