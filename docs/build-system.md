# Sistema de Build

## Objetivo

Este repositorio mantiene un flujo explicito para:

- dependencias
- build
- artifact
- CI

A diferencia de un repo solo SourcePawn, `Custom-Fakelag` construye dos tipos de salida:

- plugins SourceMod (`.smx`)
- extensiones SourceMod (`.ext.so` / `.ext.dll`)

## Archivos principales

- `Makefile`
- `plugin-package-map.json`
- `PackageScript`
- `scripts/fetch-linux-deps.sh`
- `scripts/fetch-windows-deps.ps1`
- `scripts/build-linux-l4d2.sh`
- `scripts/build-windows-l4d2.ps1`
- `scripts/stage-artifact.py`
- `scripts/package-release.py`
- `.github/workflows/build.yml`

## Flujo

Targets principales:

- `make deps-smx`
- `make deps-exts-linux`
- `make deps-exts-windows`
- `make build-smx`
- `make build-exts-linux`
- `make build-exts-windows`
- `make package-smx`
- `make package-exts-linux`
- `make package-exts-windows`
- `make release-linux`
- `make release-windows`

## Manifiesto

El archivo:

- `plugin-package-map.json`

define dos capas:

### `build`

Describe que binarios se construyen.

- `build.plugins`
- `build.extensions`

Cada una se organiza por bucket de salida, por ejemplo:

- `root`

Eso permite soportar subdirectorios futuros bajo:

- `addons/sourcemod/plugins/`
- `addons/sourcemod/extensions/`

sin rediseñar el formato.

### `artifact`

Describe que runtime entra al paquete final.

Actualmente se usa:

- `artifact.addons.sourcemod.plugins`
- `artifact.addons.sourcemod.extensions`
- `artifact.addons.sourcemod.scripting`
- `artifact.addons.sourcemod.translations`
- `artifact.addons.sourcemod.gamedata`

Cada seccion puede usar:

- `files`
- `dirs`
- `all: true`

## Packaging

`PackageScript` usa el manifiesto para copiar runtime desde el arbol fuente al paquete de AMBuild.

La separacion operativa es:

- `deps-smx`: resuelve el `sourcemod-package` correcto para `spcomp`
- `build-smx`: compila los plugins SourcePawn una sola vez
- `package-smx`: prepara el arbol runtime compartido del lado `.smx`
- `deps-exts-*`: prepara el toolchain nativo de la extension
- `build-exts-*`: construyen la extension nativa por plataforma
- `package-exts-*`: preparan el arbol runtime del lado nativo
- `release-linux` / `release-windows`: fusionan paquetes y generan el ZIP final

`deps-exts-*` ya no resuelven el compilador de SourcePawn. Solo preparan el toolchain nativo de la extension.

En CI, las dependencias quedan separadas por path:

- `.deps/smx`
- `.deps/exts-linux`
- `.deps/exts-windows`

Eso evita mezclar caches del compilador SourcePawn con caches del toolchain nativo.

Los binarios compilados quedan en:

- `addons/sourcemod/plugins/...`
- `addons/sourcemod/extensions/...`

y luego `stage-artifact.py` arma:

- `dist/sourcemod/artifact/`

fusionando:

- `.build/package-exts-linux` o `.build/package-exts-windows`
- `.build/package-smx`

con:

- `addons/`
- `README.md`
- `plugin-package-map.json`
- `docs/`

## CI

El workflow:

- separa `deps`, `build` y `package` para `smx`
- separa `deps`, `build` y `package` para `exts` por plataforma
- usa `release-linux` y `release-windows` para fusionar `package-smx` con el paquete nativo correspondiente
- publica artifacts temporales y releases de canal

Eso deja el ZIP de CI alineado con el mismo staging que se usa localmente y con responsabilidades mas claras por capa.
