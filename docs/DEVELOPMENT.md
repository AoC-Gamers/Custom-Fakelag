# Desarrollo local

Usa Makefile + AMBuild. `.deps/` contiene dependencias locales y `.build/` las
salidas; ninguno se versiona. `gamedata/` es la fuente canónica del gamedata.

## Compilar y empaquetar

Linux: bash, Git, Make, Python/venv y toolchain C++ con multilib i386. Windows:
Git, Make, Python, PowerShell, MSVC x86 y Windows SDK. Los scripts descargan los
SDK de AlliedModders y AMBuild; el compilador SourcePawn se prepara por separado.

```bash
make deps-smx
make deps-exts-linux
make build-smx
make build-exts-linux
make package-smx
make package-exts-linux
make release-linux
```

En Windows sustituye los tres targets `*-exts-linux` por `*-exts-windows` y
`release-linux` por `release-windows`. `make help` enumera los targets vigentes.
Las dependencias quedan en `.deps/smx`, `.deps/exts-linux` y `.deps/exts-windows`.

Los ZIP aparecen en `dist/release/`; el árbol combinado, en
`dist/sourcemod/artifact/`. Las bibliotecas del motor y los includes externos no
se añaden al paquete. Consulta [el manifiesto y CI](build-system.md).

## Comprobar cambios

```bash
SANITIZE=1 make test-exts-linux
# Con toolchain multilib:
TEST_ARCH=32 SANITIZE=1 make test-exts-linux
```

En Windows: `make test-exts-windows`. Cambios SourcePawn requieren `make build-smx`
y compilación explícita de los harnesses afectados. Las pruebas standalone no
certifican ABI ni gameplay: registra runtime y módulo exactos por separado.
Para documentación basta comprobar coherencia, enlaces y diff; no cambia binarios.

`.env.example` describe overrides locales. `VCVARSALL_PATH` permite seleccionar
MSVC. Los scripts de build nativo recrean su directorio de salida; usa un
`BUILD_DIR` independiente para candidatos y no guardes evidencia allí.

## Diagnóstico y compatibilidad

[Steam Lifecycle Debug](https://github.com/AoC-Gamers/Custom-Fakelag/blob/develop/diagnostics/steam_lifecycle_debug/README.md) usa un
build independiente con `--steam-lifecycle-debug`, sin alterar el paquete normal.
No se instala ni despliega automáticamente al compilar.

En GCC 14+ se conserva `-Werror` excepto `template-id-cdtor`, por constructores
antiguos del HL2SDK. La validación histórica incluye Ubuntu 26.04/GCC 15.2 x86;
los ZIP Linux de CI se construyen en Ubuntu 22.04. Son candidatos distintos,
no una declaración de requisitos mínimos ni una prueba con jugadores.
