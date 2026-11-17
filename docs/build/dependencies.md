# Dependencias

| Dependencia | Selección | Función | Distribución |
|---|---|---|---|
| HL2SDK AlliedModders | rama l4d2 | compilación/ABI | externa |
| SourceMod AlliedModders | rama 1.12-dev | compilación | externa |
| Metamod Source AlliedModders | rama 1.12-dev | compilación | externa |
| AMBuild AlliedModders | rama master | herramienta | externa |
| SourceMod package | latest 1.12 por plataforma | spcomp/includes | externa |
| BuiltinVotes, colors, Left4DHooks stocks | snapshot de includes conservado | compilación; proveedores runtime según uso | no empaquetar |
| udis86/cdetour/asm | fuentes vendorizadas | extensión | conservar avisos de licencia |

Las ramas y latest son móviles; la caché no fija sus revisiones. No se afirma
reproducibilidad binaria. Una actualización se realiza mediante deps-* y exige
recompilar consumidores; no actualiza bibliotecas del servidor.
Las identidades exactas de engine soportadas permanecen en los fixtures y código.

Revisiones observadas y hashes de snapshots: scripts/deps/resolved-baseline.json.
Son procedencia de esta migración; no fijan futuras descargas de ramas móviles.
