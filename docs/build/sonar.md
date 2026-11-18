# Sonar C/C++ local

Esta integración usa Cppcheck y SonarQube Community con el plugin sonar-cxx.
No usa SonarCFamily ni Build Wrapper. Requiere GCC/gcov multilib, el SDK ya
preparado, Cppcheck, SonarScanner y un Java compatible. No instala plugins ni
crea proyectos, credenciales o análisis remotos automáticamente.

## Preparación explícita

`make deps-sonar` descarga y extrae Cppcheck y libtinyxml2 del catálogo APT del
host Ubuntu amd64 a .deps/sonar-tools, sin instalar paquetes del sistema.
Seleccionar el wrapper resultante con SONAR_CPPCHECK=.deps/sonar-tools/bin/cppcheck.
También puede usarse una instalación existente. Scanner/JDK se preparan aparte.
`make deps-test-coverage` prepara coverage.py 7.13.5 en su venv aislado.
Ningún target de análisis, compilación o pruebas descarga herramientas.

## Contexto real del compilador

`make sonar-build` realiza un build Linux x86 aislado y construye el diagnóstico
independiente. Captura las órdenes reales de compilación en
.build/sonar-native/compile_commands.json, sin migrar la API de AMBuild del producto.
SONAR_BUILD_DIR cambia el directorio del build principal de análisis.
La captura conserva el compilador, cwd y flags efectivos; se rechazan unidades
faltantes y configuraciones sin -m32. Repetir tras cambiar fuentes o dependencias.
No acredita ejecución en SRCDS.

`make sonar-cppcheck` ejecuta solo el análisis local. Para el contexto CXX se
consultan macros e includes del compilador con arquitectura, SSE, PIC, estándar,
optimización y orden de -D/-U reales, sin generar objetos. Los errores de ejecución,
XML, preprocesado o parser bloquean la importación del informe. El servidor usa
sonar.cxx.errorRecoveryEnabled=false; no se rebaja el quality gate.

Se incluyen la extensión principal, el diagnóstico independiente y los scripts
Python. SourcePawn no se presenta como C++. Se excluyen tests, SDK descargados,
asm y libudis86 vendorizados; los adaptadores y detours mantenidos se conservan.
Los includes externos siguen disponibles como contexto de compilación.

## Cobertura medida

Ejecutar `make test-coverage TEST_OUTPUT=.build/coverage/native-001` tras el build.
La salida debe ser nueva. Ejecuta las regresiones nativas originales con GCC x86,
ASan/UBSan y contadores gcov. Compila además todas las unidades del producto con
instrumentación para incorporar líneas ejecutables sin hits, incluido el diagnóstico
que esa suite no ejecuta. No usa contadores de mutantes ni assertions como cobertura.
La métrica es de líneas, no de ramas ni aceptación del motor.

`make test-python-coverage TEST_OUTPUT=.build/coverage/python-001` usa coverage.py
para las pruebas portables y los subprocesos, incluyendo fuentes Python sin hits.
Las copias temporales no se remapean a las fuentes canónicas.
Ambos informes genéricos conservan un receipt.json con hashes de fuentes, pruebas
e informe. Fuentes o informes alterados/fallidos bloquean el uso del recibo.

## Configuración y análisis remoto explícito

.env contiene SONAR_HOST_URL, SONAR_PROJECT_KEY, SONAR_PROJECT_NAME y las rutas
SONAR_COVERAGE_RECEIPT/SONAR_PYTHON_COVERAGE_RECEIPT a los recibos anteriores.
.env.example contiene valores genéricos. SONAR_TOKEN va únicamente en .env.secret
(modo 600) o el entorno. Las variables exportadas prevalecen y no se evalúa shell.
El token se transmite por entorno al scanner, sin argumentos ni informes públicos.
El token del entorno tiene prioridad sobre `.env.secret`. Si aún usas el
nombre anterior `env.secret`, renómbralo manualmente y conserva sus permisos
restrictivos. Cppcheck local funciona sin credenciales.
HTTPS es obligatorio salvo ensayos por loopback. No reutilizar tokens de otro
proyecto ni crear credenciales como efecto de configurar esta integración.

Después de configurar y autorizar el destino, `make sonar` vuelve a ejecutar
Cppcheck, valida los recibos antes/después y envía el análisis al servidor.
Espera el quality gate por defecto; una subida exitosa no acredita su aprobación.
Si se configura SONAR_QUALITY_GATE_WAIT=false, el resultado no acredita el gate.
Los umbrales y baseline del servidor se conservan.

## Pruebas locales y CI

`make sonar-tooling-test` comprueba orquestación, tokens, contexto, XML y fallos
con ejecutables controlados. `make coverage-tooling-test` comprueba gcov real,
líneas sin hits, contadores positivos y rechazo de informes alterados.
Sonar y sus pruebas de tooling/cobertura son exclusivamente locales. No están en
el workflow, en make test-python ni en la compilación normal. Las regresiones del
producto siguen en CI. Logs, herramientas, tokens e informes no son instalables.
Se realizó el primer análisis desde el entorno local y se verificaron la tarea
completada y el quality gate aprobado. Esto no acredita ausencia de hallazgos ni
aceptación runtime. El parser CXX se comprueba también en los logs: cualquier
ERROR invalida la ejecución aunque el scanner devuelva código cero.
Las rutas de include inexistentes que GCC ignora se omiten únicamente en la copia
de la base para CXX; la base original y la usada por Cppcheck conservan sus flags.
