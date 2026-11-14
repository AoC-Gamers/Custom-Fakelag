# Build y empaquetado

Las instrucciones de compilación están en [DEVELOPMENT.md](DEVELOPMENT.md).
Este documento describe cómo se forman las salidas.

## Fuentes y manifiesto

| Archivo | Función |
|---|---|
| `configure.py`, `AMBuildScript` | SDK, compilador y selección de build |
| `extension/AMBuilder` | Fuentes de Custom-Fakelag |
| `plugin-package-map.json` | Binarios construidos y contenido distribuido |
| `PackageScript` | Copia de runtime al paquete nativo |
| `scripts/build-plugins.py` | Compilación SourcePawn |
| `scripts/stage-artifact.py`, `scripts/package-release.py` | Fusión y ZIP |

En el manifiesto, `build.plugins` y `build.extensions` enumeran binarios por
bucket (`root` o subcarpeta). `artifact.addons.sourcemod` selecciona plugins,
extensiones, scripting, gamedata y traducciones mediante `files`, `dirs` o
`all`. La distribución normal incluye solo los dos includes propios.

## Salidas

| Etapa | Salida |
|---|---|
| `build-smx` | `.build/plugins/` |
| `build-exts-linux` / `build-exts-windows` | `.build/<plataforma>-l4d2/package/` |
| `package-smx` | `.build/package-smx/` |
| `package-exts-*` | `.build/package-exts-<plataforma>/` |
| `release-*` | `dist/sourcemod/artifact/` y ZIP en `dist/release/` |

`stage-artifact.py` combina los paquetes nativo y SMX, README, manifiesto y docs.
Los binarios instalables se normalizan como `custom_fakelag.ext.so` o `.ext.dll`.
No se incluyen librerías de Valve, DLL de prueba, ejemplos ni harnesses.

## CI

[build.yml](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/.github/workflows/build.yml) separa cachés y dependencias SMX,
Linux y Windows. Compila el plugin, ejecuta regresiones C++ y Python, compila
consumidores opt-in y el arnés SDK Windows, y construye paquetes por plataforma.
El arnés SDK en CI solo se compila: sus pruebas contra engine.dll requieren el
módulo privado identificado. Los jobs no ejecutan un SRCDS con cliente humano.

La extensión diagnóstica independiente también se compila y prueba en Linux y
Windows. Sus artefactos se suben por separado y no entran al ZIP normal.
Los canales son `channel/develop` para develop y `channel/latest` para la rama
principal. Un push puede actualizar la release de canal; no despliega servidores.

Resultados y límites: [VALIDATION.md](VALIDATION.md).
