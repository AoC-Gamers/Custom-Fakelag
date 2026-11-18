# Changelog

## [Unreleased]

**Antes de actualizar.** Sustituye la extensión, el plugin y los includes juntos.
Retira el binario antiguo si todavía usa el nombre sin sufijo de juego.
Consulta la [guía de instalación](README.md#instalación).

### Añadido

- **API:** `CFakeLag_IsLanBlocked` permite consultar el bloqueo LAN.
  `CFakeLag_OnLanPolicyChanged` y `CFakeLagChange_LanPolicy` permiten detectar
  el cambio de política y su efecto en los perfiles.
- **Diagnóstico:** Steam Lifecycle Debug puede instalarse por separado. Carga
  desactivado por defecto.

### Cambiado

- **Política LAN:** `sv_lan 1` bloquea perfiles nuevos y limpia perfiles, colas,
  persistencia y votos pendientes. Volver a `sv_lan 0` no restaura perfiles.
  `sm_custom_fakelag_allow_lan 1` habilita una excepción explícita para pruebas.
- **Compatibilidad:** la extensión admite las identidades verificadas del motor
  L4D2 2.2.4.3 x86 en Linux y Windows. En Windows admite carga y recarga con
  Left4DHooks activo para el motor comprobado.
- **Distribución:** los binarios usan `custom_fakelag.ext.2.l4d2.so` y
  `custom_fakelag.ext.2.l4d2.dll`. Los ZIP de canal usan el nombre
  `custom-fakelag-<canal>-<plataforma>.zip`. Actualiza los enlaces de descarga y
  los instaladores que todavía busquen el orden anterior.
- **Instalador:** la documentación del ZIP incluye la guía de instalación,
  `LICENSE` y `CHANGELOG.md`.

### Corregido

- **Balance:** los informes muestran los perfiles efectivos después de que un
  forward modifique o vete el cambio. Un veto cancela la operación sin notificar
  éxito ni provocar un error nativo.
- **Pérdida de paquetes:** Gilbert-Elliott respeta la pérdida configurada y trata
  explícitamente los extremos de 0 % y 100 %.
- **Extensión:** la cola conserva sus propias copias de los paquetes para evitar
  liberar memoria del motor. La sesión, el cambio de mapa y el reset limpian
  los datos pendientes.
- **Descarga:** si no se puede retirar el hook, se propaga el fallo y se conserva
  la infraestructura necesaria para evitar callbacks a código liberado.

### Desarrollo

- **Compilación:** Make ofrece las mismas fases de compilación, pruebas y
  empaquetado en local y en CI.
- **Sonar:** análisis C/C++ y cobertura mediante Make, fuera de CI. Si guardas el
  token en un archivo local, usa `.env.secret`.

## 2.0.0

API centrada en perfiles `lag + packet loss`, incompatible con los setters
legacy fraccionados. Plugin administrativo con balance global/parejas, votos,
traducciones y persistencia temporal. Includes low-level y high-level separados.

## 1.0.0

Base original de [ProdigySim](https://github.com/ProdigySim/custom_fakelag).
