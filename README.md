# Phone Dock

Phone Dock is a free, open-source iPhone/iPad control surface for macOS, with its own customizable visual identity. No accounts, analytics, subscriptions, cloud relay, or paid feature gates.

## Windows preview

A native Windows 11 x64 companion is now available under [Windows](Windows/README.md), with the Phone Dock logo, five palettes, a customizable action editor, and the existing iPhone pairing protocol. It builds as a self-contained WPF application. Protocol interoperability is tested with the Swift models; Windows UI and hardware validation remain pending. See the Windows README for supported controls and limitations.

## Language / Idioma

All three apps include **Follow system**, **English**, and **Español**. The choice is saved per device and updates the app interface immediately without resetting the Dock, navigation, appearance, or pairing credentials.

- iPhone/iPad: **Settings → Language** / **Ajustes → Idioma**.
- Mac: **Settings → Appearance → Language** / **Ajustes → Apariencia → Idioma**.
- Windows: **Appearance → Language** / **Apariencia → Idioma**.

User-created action names, application names, and content are not translated. System-owned permission dialogs and operating-system menu items may follow the OS language. Existing error messages keep the language in which they were generated. Unsupported system languages fall back to English.

The GitHub repository contains the source for all three platforms. Windows builds and an iPhone/iPad IPA for AltStore Classic are attached to [Releases](https://github.com/tiburonns/Phone-dock/releases).

## Instalar con AltStore Classic

Requiere iOS/iPadOS 17 o posterior y AltStore Classic configurado con AltServer. En **Browse → Sources → +**, agrega esta fuente:

```text
https://raw.githubusercontent.com/tiburonns/Phone-dock/main/altstore/source.json
```

También puedes descargar `PhoneDock-0.3.1.ipa` de [Releases](https://github.com/tiburonns/Phone-dock/releases/tag/v0.3.1) e importarlo con **My Apps → +**. AltStore vuelve a firmarlo con tu cuenta; el IPA no contiene certificados ni perfiles del desarrollador. Mantén las renovaciones que indique AltStore. Necesitas Phone Dock abierto en un Mac o PC de la misma red para controlar ese equipo.

Esta fuente es para **AltStore Classic, no AltStore PAL**. No está notarizada para PAL ni publicada en App Store. La estructura del IPA y su correspondencia con la fuente están verificadas; la instalación final con AltStore aún debe probarse en un dispositivo. [Documentación oficial de fuentes](https://faq.altstore.io/developers/make-a-source).

## Included now

- The iPhone swipe control pad stays pinned below the scrollable controls, so vertical gestures no longer scroll the page.
- Windows activates an existing application window before launching, restores minimized windows, and suppresses repeated launch taps during startup.
- Bonjour discovery and direct local-network communication.
- Manual hostname/IP and port connection when Bonjour or multicast is unavailable.
- Six-digit rotating pairing code, ECDH/ChaChaPoly secret exchange, and Keychain-backed HMAC authentication.
- Bidirectional device forgetting that revokes the saved Mac credential.
- Up to eight customizable action pages for Mac apps, discovered Apple Shortcuts, websites, emoji/text, and clipboard actions, with live updates to connected devices. Selected apps use their native icon, websites attempt to load their own `/favicon.ico` directly, and Shortcuts can use a custom emoji.
- Remote Mac volume, mute, main-display brightness, window minimize/full-screen/hide, copy, and paste.
- Persistent recent apps with native artwork and pin-to-front favorites, remembered devices, multi-connection listener, gesture controls, menu bar access, and native Settings.
- A consistent, responsive interface across Dock, Controls, Devices, and Settings, with prominent 76 or 100-point icons and adaptive grids.
- Five palettes (Aurora, Ocean, Sunset, Forest, Graphite), system/light/dark appearance, two corner styles, optional action details, individual icon colors, and iPhone haptic preferences. Changes persist locally on each device and have a live preview.
- Click any action in the Mac Dock editor to change its name, detail, emoji, image, or color without changing its command. Action edits synchronize to the paired phone.
- English interface with complete Spanish localization for the main UI, connection states, errors, accessibility labels, and permission descriptions.

## Build

Requirements: macOS with Xcode 26 or newer. XcodeGen is optional, only needed to regenerate the included project.

### Probar en Xcode

En Xcode, elige **Clone Git Repository** (en la pantalla de bienvenida o en **Source Control → Clone**) y pega:

```text
https://github.com/tiburonns/Phone-dock.git
```

O desde Terminal:

```sh
git clone https://github.com/tiburonns/Phone-dock.git
cd Phone-dock
open PhoneDock.xcodeproj
```

Abre `PhoneDock.xcodeproj`. Selecciona `PhoneDockMac` y **My Mac** para ejecutar la app de Mac, o `PhoneDockMobile` y un iPhone/iPad Simulator para probar la app móvil. Usa **⌘R**. Para instalarla en un iPhone físico, selecciona tu equipo en **Signing & Capabilities** del destino móvil.

El proyecto y los dos esquemas ya están incluidos: no necesitas XcodeGen para clonarlo y abrirlo. No se incluye una cuenta de firma. También puedes guardar `PHONE_DOCK_TEAM = TU_TEAM_ID` en `Configuration/Signing.local.xcconfig`, que Git ignora. Si Xcode indica que el identificador no está disponible para tu cuenta, cambia el Bundle Identifier de tu copia por uno único; no hace falta hacerlo para usar el simulador.

Ambos dispositivos deben estar en la misma red local. Acepta el permiso de red local y empareja con el código mostrado en la Mac. Los identificadores internos, Bonjour y claves del Llavero conservan el nombre técnico anterior para mantener las configuraciones y los emparejamientos existentes.

```sh
xcodebuild -project PhoneDock.xcodeproj -scheme PhoneDockMac -destination 'platform=macOS' build
xcodebuild -project PhoneDock.xcodeproj -scheme PhoneDockMobile -destination 'generic/platform=iOS Simulator' build
```

Para generar un IPA Release sin firma para AltStore Classic, ejecuta `./script/build_ipa.sh`. Se guarda en `dist/ios/`; el script no publica nada ni usa certificados. El código JSON de la fuente está en `altstore/source.json` y se puede verificar con `swift script/validate_altstore.swift altstore/source.json dist/ios/PhoneDock-0.3.1.ipa`.

The Codex Run action executes `./script/build_and_run.sh`, which preserves the existing Xcode project (including your signing choices), builds a locally signed Mac app in `/tmp/PhoneDockDerivedData-$UID` (outside File Provider metadata and readable by Bonjour), and launches it. It only generates a project if missing. `--verify`, `--debug`, `--logs`, and `--telemetry` modes are also supported. Manually regenerating with XcodeGen may reset signing choices; select your team again if necessary.

### Personalización

En iPhone, abre **Ajustes**. En Mac, abre **Ajustes → Apariencia** o usa el botón **Apariencia** del editor. La paleta y el diseño se guardan por dispositivo, así que tu Mac y tu iPhone pueden tener estilos distintos. Para usar un color propio por acción, activa **Colores individuales de iconos**. Actualiza ambas apps para recibir también las imágenes de las aplicaciones recientes.

## Tests

```sh
xcodebuild test -project PhoneDock.xcodeproj -scheme PhoneDockMac -destination 'platform=macOS'
./script/test_integration.sh
```

The integration test uses a debug-only pairing code, reads system state, re-applies the current volume and brightness without a perceptible change, validates the encrypted/authenticated round trip, unpairs, and confirms that its temporary Keychain credential was revoked.

## Permissions and compatibility

Accessibility permission is required only for simulated keyboard actions and window manipulation. Volume uses CoreAudio. Main-display brightness first uses the macOS DisplayServices interface because Apple does not provide an equivalent public SwiftUI API, then falls back to software gamma dimming for unsupported external displays. DisplayServices use may affect Mac App Store eligibility; direct distribution or replacing the bridge with a DDC helper is recommended for hardware-level external-display support.

Initial pairing uses an ephemeral P-256 key agreement and ChaChaPoly so the persistent credential is never sent in clear text. Later commands include an HMAC made with that 256-bit secret stored in Keychain. Duplicate signed requests are rejected and repeated bad PINs trigger a temporary lockout. Full-session transport encryption and QR-based out-of-band verification remain recommended hardening before an untrusted-network deployment.

## Name and assets

Phone Dock intentionally uses its own name and system symbols. Choclift and its visual assets remain the property of their respective owners.

The current Aurora brand assets live in `Resources/Brand/PhoneDock/`: `AppIcon-Source.png` and the transparent horizontal `Wordmark.png`. `BRAND.md` records the image-generation prompts. The previous source remains archived at `Resources/Brand/CocoaLift-AppIcon-Source.png`.

Run `swift script/generate_app_icons.swift` to export an opaque iOS icon and rounded macOS icons with transparent exterior margins. The Mac app uses the new identity in its sidebar, overview, About screen, and quick menu-bar panel, while preserving native sidebar selection, keyboard access, and shared appearance preferences.
