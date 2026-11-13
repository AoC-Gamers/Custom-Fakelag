# Carga de Custom-Fakelag con Left4DHooks activo

La validación Windows admite ahora el detour de entrada observado de Left4DHooks
1.175 en `CBaseServer::FillServerInfo`, para el mismo `engine.dll` PE32 identificado
por SHA-256 `8a6d468059394bf4cfce32f11dcba12ef45de88da1373084d5a2916d0bf7ba86`.
No requiere descargar Left4DHooks para inicializar o reinicializar el adaptador.

## Qué se admite y qué sigue comprobándose

La entrega Windows registró una única diferencia de cinco bytes en RVA `0x133cb0`:
original `55 8b ec 53 56`, parche observado `e9 55 c3 ac ff`. La firma del proveedor
identifica ese sitio como `CBaseServer::FillServerInfo`, fuera del contrato de
paquetes. El desplazamiento del salto cambia con ASLR y la asignación de DHooks;
no se compara contra la dirección particular de aquella sesión.

`WindowsCodeCompatibility.h` acepta exclusivamente, en ese sitio y con el
original esperado, un salto i386 `E9 rel32` de cinco bytes. Su destino debe ser
externo a la imagen del motor y estar en memoria comprometida, legible y
ejecutable, comprobada por `VirtualQuery`. Se rechazan saltos nulos, bucles y
saltos al interior del motor. El validador solo lee el parche: no lo retira,
no lo reescribe y no descarga ni pausa al proveedor.

El resto de cada sección ejecutable sigue coincidiendo byte a byte con la imagen
identificada y reubicada. Eso incluye el sexto byte de FillServerInfo y todos los
bytes del hook, callers de recepción, preparación del lector y operando net_time.
No hay una exclusión de páginas, una máscara genérica de saltos ni una ConVar para
omitir checks. El SHA-256 del archivo, arquitectura, cabeceras/ASLR, propiedad y
RVA de las direcciones, reloj, tabla y capacidad del buffer siguen comprobándose.
Los motores desconocidos y otras modificaciones siguen rechazándose.

Esto reconoce un sitio y una forma de parche compatibles; no acredita la autoría
de código inyectado ni protege contra plugins hostiles que modifiquen el proceso.
La validación conserva su finalidad de compatibilidad del motor, no anticheat.

## Evidencia y pruebas

El sitio, original y salto proceden de `runtime-code-differences.json` de la entrega
Windows; la firma del proveedor está en `left4dhooks.l4d2.txt`,
`CBaseServer::FillServerInfo`. El motor identificado y su contrato siguen siendo
los del [manifiesto Windows](runtime/windows-engine-2.2.4.3.json).

Las regresiones portables ejecutan el mismo comparador que usa el validador PE:
original exacto, parche compatible al inicializar/repetir, destino ejecutable,
rel32 con wrap i386, original inesperado, opcode inválido, límites de sección,
bytes adyacentes y alteraciones en todas las funciones/operandos de paquetes.
Se ejecutaron con ASan/UBSan x86 y x64. El build Linux permanece sin cambios de
contrato. El CI ejecuta las mismas regresiones con MSVC y compila el arnés SDK
Windows real sin requerir distribuir el binario de Valve.

`tests/windows_sdk_contract.cpp` amplía la prueba de PE mapeado sin ejecución:
instala un E9 equivalente hacia una asignación ejecutable privada, exige que
Initialize lo acepte repetidamente sin tocarlo, y comprueba que siguen fallando
un destino no ejecutable, un opcode arbitrario y un cambio simultáneo del hook.
Restaura y libera el estado de ese proceso aislado al terminar.

Compilar sin DLL, sin ejecutar estos tests PE:

```powershell
pwsh -NoProfile -File scripts/test-windows-sdk-contract.ps1 -BuildOnly
```

Ejecutar en Windows con el archivo identificado (opcional ASan instalado):

```powershell
$env:CUSTOM_FAKELAG_ASAN = '1'
pwsh -NoProfile -File scripts/test-windows-sdk-contract.ps1 -EnginePath '<ruta>\bin\engine.dll'
Remove-Item Env:CUSTOM_FAKELAG_ASAN
```

## Repetición de aceptación en SRCDS Windows

La evidencia anterior de 32 checks UDP y 17 API sigue correspondiendo a la revisión
previa, que imponía el orden de carga. Este cambio no se presenta como una nueva
prueba con Left4DHooks activo: falta repetirla en la PC Windows.

En la instancia privada ya preparada, usando el build normal actualizado:

1. Cargar Left4DHooks y comprobar que su detour FillServerInfo está activo.
2. Cargar Custom-Fakelag y exigir `Packet adapter accepted`; aplicar/consultar/
   limpiar perfiles mediante la API/plugin normal con el cliente real.
3. Retirar solo los dependientes que SourceMod necesite para descargar
   Custom-Fakelag. Mantener Left4DHooks activo y recargar la extensión.
4. Comprobar nuevamente aceptación, latencia/pérdida, reset, sesión y tráfico.
   Verificar que el E9 de FillServerInfo conserva exactamente sus bytes antes y
   después de cada carga/recarga y que NET_LagPacket se restaura al retirar su hook.
5. Repetir el orden inverso y cambios de mapa. Registrar hashes, versiones,
   direcciones, logs y resultados sin presentar compilación como prueba de SRCDS.

El fallo de salida completa de SRCDS `0xc0000409`, reproducido también sin mods,
permanece separado de este cambio.
