# Validación

La compilación SourcePawn, las regresiones C++ y las herramientas Python se
comprueban por Make. Las pruebas Windows requieren Windows y MSVC x86.
Los fixtures de identidad del motor conservan sus bytes originales.

Las pruebas aisladas usan transporte simulado: no acreditan efectos de red reales,
cliente humano, disponibilidad de BuiltinVotes ni compatibilidad con otro engine.
Históricamente se comprobaron en Windows carga y recarga con Left4DHooks activo.
La investigación de cierre reprodujo el fallo también en vanilla con sv_lan 1;
los antiguos errores 0xc0000409 siguen sin atribución completa.
No se han repetido ensayos SRCDS por reorganizar el repositorio.

Los resultados nuevos van a .build o a los artefactos de CI; los informes completos
se conservan fuera del repositorio público.

El ensayo aislado histórico de informes completó 177 comprobaciones por idioma,
44 regresiones y cinco ejecuciones de muestreo. Utilizó SourceMod real con clientes
y transporte simulados; no acredita partidas humanas ni BuiltinVotes real.
