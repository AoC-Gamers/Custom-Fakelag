# Desarrollo local

## Objetivo

Este repositorio usa un flujo reproducible basado en:

- `AMBuild`
- `Makefile`
- scripts en `scripts/`
- dependencias locales en `.deps/`
- artefactos de compilacion en `.build/`

La idea es que nadie tenga que editar rutas a mano ni depender de proyectos
legacy de Visual Studio.

## Comandos principales

```bash
make help
make deps-linux
make build-linux
```

En Windows:

```powershell
make deps-windows
make build-windows
```

## Estructura relevante

- `AMBuildScript`: configuracion general del build
- `extension/AMBuilder`: lista de fuentes de la extension
- `extension/`: codigo nativo C++, headers y librerias auxiliares
- `extension/latency/`: estado de fake lag por jugador, validacion y bridge de API
- `extension/network/`: colas, politica de despacho y estructuras de paquetes
- `PackageScript`: define que entra al paquete final
- `scripts/`: bootstrap y builds por plataforma
- `gamedata/`: archivos `.games.txt`
- `scripting/`: include y plugin de ejemplo

## Convenciones

- `.deps/` no se versiona
- `.build/` no se versiona
- `gamedata/` es fuente canonica; no mantener copias manuales de distribucion
- la via oficial de build es `Makefile` + scripts, no soluciones viejas de IDE

## Verificacion recomendada

Antes de tocar logica de la extension:

1. confirmar que `make build-linux` sigue compilando
2. si estas en Windows, confirmar que MSVC x86/x64 esta instalado
3. revisar que el paquete final contenga extension, include, gamedata y plugin de ejemplo
