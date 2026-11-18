# Compilación y distribución

GNU Make es la interfaz local y de CI. Linux requiere Bash, Python, AMBuild y
C++ multilib; Windows requiere GNU Make/Bash, PowerShell, Python, MSVC x86 y SDK.

Ejecutar por orden: `make deps-smx deps-exts-linux`, `make build-smx`,
`make test-python test-consumers test-exts-linux`, `make build-exts-linux`,
`make package-smx package-exts-linux`, `make release-linux validate-artifact-linux`.
Las descargas son explícitas. Para Windows usar las familias correspondientes.
`make test-sdk-windows` compila el contrato sin afirmar validación contra engine.
`make test-diagnostic-linux` o `make test-diagnostic-windows` construye y prueba
el diagnóstico independiente, fuera del instalador normal.

El mapa scripts/package/package-map.json es la única autoridad de build/contenido.
Los stages de familia se combinan una vez por plataforma en dist/linux/artifact
o dist/windows/artifact. Cada ZIP contiene binario nativo de su plataforma,
plugin, APIs propias, gamedata, traducciones y documentación declarada.
Se comprueban árbol y ZIP, archivos requeridos, extras y arquitectura.
Las fuentes están disponibles en el repositorio y archivos de fuente de GitHub.
Extraer el ZIP en la raíz del juego puede sobrescribir recursos propios.

Los canales usan custom-fakelag-develop-linux/windows.zip y
custom-fakelag-latest-linux/windows.zip; los tags v* conservan su versión.
Cambian los nombres antiguos con plataforma antes del canal: actualizar enlaces.
Release local genera ZIP sin publicar. El workflow publica únicamente ramas
principales/develop o tags versionados, tras validar ambas plataformas.

El binario nativo conserva el nombre generado por AMBuild: custom_fakelag.ext.2.l4d2.so
o custom_fakelag.ext.2.l4d2.dll. No se renombra al empaquetar. Antes de actualizar,
descargar y retirar la antigua copia sin sufijo de juego para evitar duplicados.

Análisis C/C++ explícito y cobertura: [Sonar local](sonar.md), fuera de CI.

El ZIP incluye el README de instalación generado desde el README raíz,
`LICENSE` y `CHANGELOG.md`. Para archivos de fuente sin Git, `SOURCE_REVISION` admite
el SHA completo de la fuente cuando se conoce. Revisa la [procedencia](licensing.md)
antes de publicar.
