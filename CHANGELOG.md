# Changelog

## [Unreleased]

### Política LAN

- `sv_lan 1` bloquea perfiles nuevos y limpia perfiles, colas y pérdida, con
  prioridad sobre always-on. Excepción de pruebas: `sm_custom_fakelag_allow_lan 1`,
  desactivada por defecto. Volver a LAN 0 no restaura perfiles.
- `player_fakelag` descarta persistencia, snapshots y votos pendientes.
  API nueva: `CFakeLag_IsLanBlocked`, `CFakeLag_OnLanPolicyChanged` y razón
  `CFakeLagChange_LanPolicy`. [Contrato](docs/LAN_POLICY.md).

### Integración y seguridad

- Adaptadores para los motores Linux x86 y Windows PE32 identificados de L4D2
  2.2.4.3; otros módulos rechazan activación. El adaptador Windows admite el
  detour conocido de Left4DHooks sin descargarlo ni modificarlo.
- Memoria prestada del motor separada del payload propietario de las colas;
  capacidad verificada por asignación, lector reconstruido por su caller.
- Colas acotadas y limpieza por sesión, desconexión, edición, reset y mapa.
  Validación de latencia finita, pérdida y resultados de forwards.
- Veto normal separado de errores. Los listeners se ejecutan con referencias
  estables para detectar excepciones y rechazar mutaciones reentrantes.
- Retirada del hook comprobada: un fallo conserva infraestructura y se propaga.
  Una descarga irrecuperable aborta antes de dejar callbacks en código liberado.
- Bernoulli y Gilbert-Elliott, con extremos 0/100 % y calibración coherente.

### Herramientas y validación

- Build reproducible de SMX y extensiones x86, paquetes por plataforma y canales
  `channel/develop` / `channel/latest`.
- Diagnóstico independiente Steam Lifecycle Debug, apagado por defecto, con
  ConVar, muestreo de solo lectura y logs acotados; artefactos separados.
- Regresiones Linux ASan/UBSan, Windows nativas, SourcePawn y herramientas Python
  en CI. La [matriz](docs/VALIDATION.md) distingue esos checks del runtime.
- En Windows se validaron API con cliente real, ambos órdenes con Left4DHooks
  activo y recargas. La investigación de cierre reprodujo el fallo también en
  vanilla con LAN 1; los antiguos `0xc0000409` siguen sin atribución completa.

## 2.0.0

API centrada en perfiles `lag + packet loss`, incompatible con los setters
legacy fraccionados. Plugin administrativo con balance global/parejas, votos,
traducciones y persistencia temporal. Includes low-level y high-level separados.

## 1.0.0

Base original de [ProdigySim](https://github.com/ProdigySim/custom_fakelag).
