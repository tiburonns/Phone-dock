# Phone Dock 0.3.5 — Preflight de TestFlight

El target de iPhone/iPad debe entrar a Internal TestFlight sólo cuando la rama protegida pase los jobs Apple, Windows e interoperability.

## Gate automatizado

Apple valida el contrato de versión, regenera el proyecto de forma reproducible, ejecuta tests del core de macOS y compila Release para Simulator, iPhoneOS y macOS tratando warnings como errores.

Windows e interoperability también deben permanecer verdes porque móvil y companions comparten el protocolo autenticado v3.

## Aceptación física

Usa `docs/TESTING.es.md`: prueba Bonjour y conexión manual, pairing de seis dígitos, PIN incorrecto/lockout, protección replay, rotación de claves, identidad persistente, olvidar/revocar, controles reales de Mac y Windows, Quick Dock vertical/horizontal, idiomas y permisos revocados.

## Export compliance

Phone Dock usa CryptoKit directamente para P-256, HKDF/SHA-256 y ChaChaPoly; el protocolo v3 cifra y autentica payloads de aplicación. No establezcas automáticamente `ITSAppUsesNonExemptEncryption = NO`.

Antes de la primera subida completa el cuestionario vigente de export compliance de Apple y determina si aplica una exención. Conserva la respuesta o documentación con la release. Agrega la clave al plist sólo después de esa decisión.

## Archive / TestFlight

1. Merge sólo con `apple`, `windows` e `interoperability` verdes.
2. Abre `PhoneDock.xcodeproj` y selecciona el Team de pago en `PhoneDockMobile`.
3. Conserva el bundle ID móvil existente salvo que quieras crear deliberadamente un App ID nuevo.
4. Product > Archive para Generic iOS Device.
5. Organizer > Validate App.
6. Sube a App Store Connect e inicia Internal Testing.
7. Prueba con companions Mac/Windows de la misma revisión.

Developer ID/notarización del DMG de Mac es un gate separado y no bloquea TestFlight iOS.
