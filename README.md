# Custom Fakelag

Extension de SourceMod para aplicar fake lag por jugador en Left 4 Dead 2.

Origen y creditos
-----------------

Este repositorio deriva del proyecto original publicado por `ProdigySim`:

- https://github.com/ProdigySim/custom_fakelag

La base original de la extension, su idea y la implementacion inicial
corresponden a ese trabajo.

Este repositorio toma como base historica la version `1.0.0` de ese proyecto.

Estado
------

El código de la extensión es antiguo, pero el flujo de trabajo del repositorio
fue actualizado para que el proyecto pueda mantenerse con un build reproducible
antes de modernizar la lógica interna.

El flujo recomendado ahora es:

```bash
make deps
make build-linux
```

Artefacto local:

- `.build/linux-l4d2/package/addons/sourcemod/extensions/custom_fakelag.ext.so`

Targets útiles:

- `make help`
- `make build-linux`
- `make build-windows`
- `make deps-linux`
- `make deps-windows`

Requisitos
----------

- `bash`
- `git`
- `python3`
- toolchain Linux de 32 bits funcional

Compilacion Local
-----------------

### Windows

Para preparar dependencias y compilar en Windows nativo necesitas:

- `git`
- `make`
- `PowerShell 7+`
- `python` 3.x
- Visual Studio 2026 Build Tools, o una instalacion de Visual Studio 2026 con soporte C++
- componente MSVC x86/x64 disponible en el sistema

El build Windows usa `AMBuild` con `cl.exe`, por lo que no basta con tener solo
Python o Make: debe existir un toolchain MSVC instalable o detectable por el
script.

En el instalador de Visual Studio / Build Tools, lo recomendado para este repo es:

- workload `Desarrollo de escritorio con C++`

Y dentro de componentes individuales, al menos:

- `MSVC x64/x86 build tools`
- `Windows SDK`
- `MSBuild`

No hace falta instalar workloads como:

- `Desarrollo de juegos con C++`
- `Desarrollo con Unity`
- `Linux, Mac y desarrollo integrado con C++`

Comandos:

```powershell
make deps-windows
make build-windows
```

Si `cl.exe` no esta disponible en el entorno actual, el script intenta localizar
`vswhere.exe` y cargar `vcvarsall.bat` automaticamente. Si no existe una
instalacion de Build Tools o Visual Studio con C++, la compilacion Windows no
va a iniciar.

Si tu instalacion de Visual Studio esta en una ruta poco comun, o quieres fijar
paths locales sin tocar los scripts, puedes copiar `.env.example` a `.env` y
definir overrides como:

```dotenv
VCVARSALL_PATH=C:\Program Files\Microsoft Visual Studio\18\Insiders\VC\Auxiliary\Build\vcvarsall.bat
```

### Linux

Para compilar en Linux nativo necesitas:

- `bash`
- `git`
- `make`
- `python3`
- `python3-venv`
- compilador con soporte 32-bit
- librerias multilib instaladas

En Ubuntu/Debian, lo minimo razonable es:

```bash
sudo dpkg --add-architecture i386
sudo apt-get update
sudo apt-get install -y python3 python3-venv make gcc-multilib g++-multilib clang zip
```

Comandos:

```bash
make deps-linux
make build-linux
```

### WSL

`WSL` es una opcion valida y recomendada para el flujo Linux de este repo.

El flujo fue probado en:

- `WSL2`
- `Ubuntu 24.04`

Desde Windows puedes compilar dentro de WSL usando el repositorio montado en
`/mnt/c/...`, por ejemplo:

```bash
cd /mnt/c/GitHub/L4D2_Custom_Fakelag
make deps-linux
make build-linux
```

Artefactos generados:

- Linux: `.build/linux-l4d2/package/addons/sourcemod/extensions/custom_fakelag.ext.so`
- Windows: `.build/windows-l4d2/package/addons/sourcemod/extensions/custom_fakelag.ext.dll`

Dependencias resueltas por script
---------------------------------

`make deps` descarga y prepara:

- `alliedmodders/hl2sdk` rama `l4d2`
- `alliedmodders/sourcemod` rama `1.12-dev`
- `alliedmodders/metamod-source` rama `1.12-dev`
- `alliedmodders/ambuild`

Todo se instala dentro de `.deps/`, incluyendo un entorno virtual de Python
para `AMBuild`.

Overrides locales
-----------------

Los scripts `fetch-*` y `build-*` cargan opcionalmente un archivo `.env` en la
raiz del repo. Eso sirve para parametrizar rutas locales sin editar el repo.

Archivo de referencia:

- `.env.example`

Contenido empaquetado
---------------------

El empaquetado generado por `AMBuild` incluye:

- `addons/sourcemod/extensions/custom_fakelag.ext.(so|dll)`
- `addons/sourcemod/scripting/include/custom_fakelag.inc`
- `addons/sourcemod/gamedata/custom_fakelag.games.txt`
- `addons/sourcemod/scripting/player_fakelag.sp`

Estructura nativa
-----------------

La parte nativa del proyecto sigue ahora el mismo patron general de `SteamWorks`:

- `extension/`: fuentes C++, headers, `AMBuilder` y librerias auxiliares
- `gamedata/`: firmas y offsets
- `scripting/`: include SourcePawn y plugin de ejemplo
- `scripts/`: bootstrap de dependencias y entrypoints de build

Con eso, la raiz del repo queda enfocada en tooling y empaquetado, mientras que
la implementacion nativa vive completa en un unico subarbol.

Documentacion adicional
-----------------------

- `docs/DEVELOPMENT.md`

Comandos del plugin de ejemplo
------------------------------

```text
sm_fakelag <player> <ms>
sm_printlag
```
