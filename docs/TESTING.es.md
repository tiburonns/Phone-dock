# Plan de aceptación física de Phone Dock

**[English](TESTING.md) · Español**

CI es necesario pero no suficiente: Phone Dock depende de dispositivos físicos, permisos, red local, hardware de audio/pantalla y firma de AltStore.

## iPhone/iPad + Mac

- Instala la misma revisión de `main` en móvil y Mac.
- Valida discovery Bonjour y fallback manual host/puerto.
- Empareja con código de seis dígitos y confirma reconexión aunque cambie IP/nombre de servicio, manteniendo la misma identidad de host.
- Prueba PIN incorrecto/lockout, replay, rotación de claves, olvidar/revocar y errores de versión de protocolo.
- Prueba acciones de apps, Shortcuts, web, texto y clipboard.
- Valida volumen, mute, brillo donde esté soportado, ventanas, copy/paste, gestos Quick Dock, landscape, personalización e idioma EN/ES/Sistema.
- Revoca Accessibility y confirma que sólo fallen las acciones que dependen de ese permiso.

## Windows 11 x64

- Ejecuta el paquete self-contained como usuario estándar.
- Valida discovery/IP manual, pairing e identidad persistente.
- Prueba activación/lanzamiento de apps, restauración de ventanas, volumen/mute y brillo.
- Valida WMI en pantalla integrada y DDC/CI en monitor externo compatible por separado.
- Confirma que rutas de brillo no soportadas se deshabiliten sin fingir éxito.
- Prueba UI WPF, paletas, personalización, EN/ES/Sistema y persistencia tras reinicio.

## AltStore Classic

- Instala la IPA de release mediante la fuente del repositorio en un dispositivo físico.
- Confirma que AltStore la vuelve a firmar con la cuenta del usuario y que abre normalmente.
- Valida permiso de red local, pairing y el comportamiento de renovación correspondiente a la cuenta usada.

## Evidencia

Registra dispositivo, OS, revisión/build y resultado por ruta dependiente de hardware. No marques una release como validada físicamente usando sólo simulador o CI.
