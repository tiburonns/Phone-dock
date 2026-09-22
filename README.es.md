# Phone Dock

**[English](README.md) · Español**

Phone Dock es una superficie de control gratuita y open source para iPhone/iPad que controla macOS y, en vista previa, Windows 11 x64. No requiere cuentas, analítica, suscripciones, relay en la nube ni funciones de pago.

## Estado actual

La rama `main` está en **0.3.5 (build 7)** y utiliza protocolo autenticado **v3**, IDs estables del cliente guardados en Keychain y una identidad persistente/autenticada del host tanto en macOS como Windows. Al probar `main`, actualiza el móvil y el companion de escritorio desde la misma revisión. Las descargas publicadas 0.3.3 no cambian.

Windows es todavía una preview: la interoperabilidad del protocolo está cubierta por pruebas, pero UI y controles dependientes de hardware requieren validación física.

## Idioma

iPhone/iPad, Mac y Windows admiten **Seguir sistema**, **English** y **Español**. La preferencia se guarda por dispositivo y no reinicia Dock, navegación, apariencia ni credenciales de pairing.

## Funciones actuales

- Quick Dock horizontal de tres páginas con acciones, emojis y controles.
- Pulsación larga sobre una app para solicitar una instancia nueva.
- Sliders con protección frente al refresh periódico y envío debounced.
- Bonjour en red local más conexión manual por hostname/IP y puerto.
- Código de pairing rotatorio de seis dígitos.
- Intercambio ECDH/ChaChaPoly y autenticación con credenciales persistentes.
- Identidad estable del host en macOS y Windows, independiente del endpoint/IP.
- Revocación/borrado bidireccional de dispositivos.
- Hasta ocho páginas de acciones personalizables.
- Apps de Mac, Apple Shortcuts, webs, emoji/texto y clipboard.
- Control remoto de volumen, mute, brillo compatible, ventanas, copy/paste y otras acciones.
- Recientes persistentes, favoritos, múltiples conexiones y menu bar en Mac.
- Paletas Aurora/Ocean/Sunset/Forest/Graphite, sistema/claro/oscuro, estilos de esquina, colores por acción y haptics.
- Companion Windows WPF self-contained y app universal de Mac (Apple Silicon + Intel).

## Instalación

### AltStore Classic

Fuente:

```text
https://raw.githubusercontent.com/tiburonns/Phone-dock/main/altstore/source.json
```

La IPA se distribuye sin certificados/perfiles personales y AltStore Classic la vuelve a firmar con la cuenta del usuario. No es una fuente para AltStore PAL.

### macOS

Descarga el DMG universal de Releases. La build pública de prueba utiliza firma ad hoc, no Developer ID/notarización. Verifica procedencia y SHA-256 y, si confías en la copia, autoriza esa app individual desde Privacidad y seguridad. No desactives Gatekeeper.

### Xcode

```sh
git clone https://github.com/tiburonns/Phone-dock.git
cd Phone-dock
open PhoneDock.xcodeproj
```

Los esquemas `PhoneDockMac` y `PhoneDockMobile` ya están incluidos. Para un iPhone físico selecciona tu propio equipo en Signing & Capabilities.

## Seguridad

El pairing inicial usa P-256 efímero y ChaChaPoly. El protocolo v3 cifra/autentica payloads con ChaCha20-Poly1305 y claves derivadas para autenticación, usa IDs estables almacenados en Keychain, identidad persistente del host, protección contra replay y lockout temporal ante PINs incorrectos repetidos.

Accessibility sólo se necesita para acciones que simulan teclado/ventanas. El control de brillo depende de las capacidades reales de la plataforma/monitor.

## Validación

CI cubre build, pruebas deterministas de protocolo e integración. La aceptación física restante está documentada en [docs/TESTING.es.md](docs/TESTING.es.md): instalación iPhone/iPad, controles Mac, comportamiento WPF/hardware de Windows, reconexión/revocación y AltStore.

## Marca

Phone Dock usa identidad propia. Los assets Aurora están en `Resources/Brand/PhoneDock/`; consulta [BRAND.es.md](Resources/Brand/PhoneDock/BRAND.es.md).
