# Changelog

Todos los cambios importantes de este proyecto se documentan en este archivo.

## [Unreleased]

### Agregado
- Se agregaron scripts de bootstrap y compilacion para Linux y Windows bajo `scripts/`.
- Se agrego soporte opcional de `.env` para overrides locales como `VCVARSALL_PATH`.
- Se agregaron archivos de soporte para el workspace:
  - `.editorconfig`
  - `.env.example`
  - `docs/DEVELOPMENT.md`

### Cambiado
- Se reorganizo el codigo nativo bajo `extension/`.
- Se normalizaron a minusculas los nombres de directorios del proyecto.
- Se simplifico el `Makefile` con targets explicitos para dependencias y build:
  - `make help`
  - `make deps`
  - `make deps-linux`
  - `make deps-windows`
  - `make build-linux`
  - `make build-windows`
  - `make clean`
  - `make distclean`
- Se actualizo `AMBuildScript` para alinearlo con SourceMod 1.12 y el flujo actual del repo.
- Se actualizo `PackageScript` para empaquetar:
  - `custom_fakelag.ext.so`
  - `custom_fakelag.ext.dll`
  - `custom_fakelag.inc`
  - `custom_fakelag.games.txt`
  - `player_fakelag.sp`
- Se actualizo la documentacion del repositorio para describir:
  - requisitos de compilacion en Windows
  - compilacion en Linux y WSL
  - origen del proyecto base de `ProdigySim`
- Se modernizaron partes del codigo de la extension para mantener compatibilidad con el flujo de build actual.

### Eliminado
- Se elimino `pkg/` y otras copias legacy del contenido empaquetado.
- Se eliminaron proyectos legacy de Visual Studio:
  - `msvc8`
  - `msvc9`
  - `msvc10`
  - `msvc12`
- Se elimino `.gitmodules` y la dependencia del repo en submodules propios.

## [1.0.0]

### Notas
- Version base original del proyecto publicado por `ProdigySim`.
