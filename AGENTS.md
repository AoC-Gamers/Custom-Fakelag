# Custom-Fakelag

Aplicar aoc-sourcemod-project 2.3.0. Instrucciones propias únicas en esta raíz.
Producto mixto: extensión C++ principal en extension y plugin player_fakelag
con sus APIs y recursos en addons/sourcemod. El diagnóstico independiente en
diagnostics no se distribuye en el instalador normal; debug predeterminado 0.

Make es la interfaz de dependencias, build, pruebas, paquetes y validación.
Leer docs/README.md y docs/build/README.md. El mapa scripts/package/package-map.json
es autoritativo; no crear otro inventario paralelo. No empaquetar proveedores.
Preservar validación exacta del motor, API/ABI, política LAN y lógica de pérdida.
Las pruebas aisladas, compilación y SRCDS son evidencias distintas.
No publicar, desplegar ni actualizar SDK runtime sin autorización explícita.
Conservar evidencia original íntegra fuera del payload público. No incluir rutas,
redes o identificadores operativos privados en documentos ni artefactos.
Revisar documentación manualmente; no crear gates editoriales vacíos.

Sonar C/C++ y cobertura se ejecutan solo mediante targets locales explícitos.
Leer docs/build/sonar.md. No agregar análisis ni suites de tooling/cobertura a CI.
No crear proyectos/tokens ni enviar código sin autorización del usuario.

Conservar las licencias y procedencia documentadas. Resolver entradas pendientes
en docs/build/licensing.md antes de dar por verificada la distribución.
