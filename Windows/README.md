# Phone Dock para Windows

Primera versión nativa para **Windows 11 x64**, con la misma identidad visual de las aplicaciones de iPhone y Mac. El PC actúa como compañero del iPhone, no como cliente de la app de Mac.

## Abrir y conectar

1. Descomprime **toda** la carpeta `PhoneDock-Windows-x64.zip` en una ubicación permanente de tu PC.
2. Abre `PhoneDock.exe`. No necesita instalar .NET ni ejecutarse como administrador.
3. Si el Firewall de Windows pide permiso, permite la comunicación únicamente en tu red privada de confianza. No abras puertos del router.
4. Conecta el iPhone y el PC a la misma red. En Phone Dock para iPhone, abre Dispositivos y elige `Phone Dock · nombre-del-PC`.
5. Si no aparece, usa la dirección IPv4 que muestra Inicio y el puerto **49832**. Introduce el código de seis dígitos que muestra Windows.

La app de iPhone actual conserva algunas etiquetas «Mac», pero utiliza el mismo protocolo para conectarse a este PC. El código cambia cada cinco minutos y después de enlazar. Mantén Phone Dock abierto; puedes minimizarlo. Cerrar la ventana detiene la conexión. Solo debe abrirse una instancia a la vez.

El ejecutable de prueba **no está firmado con un certificado de distribución**. Windows puede mostrar una advertencia de reputación. Comprueba su procedencia antes de abrirlo; no desactives SmartScreen, el antivirus ni el firewall. Si una política de tu organización lo bloquea, consulta a su administrador.

## Incluye

- Selector de idioma en **Apariencia → Idioma**: Español, English o idioma del sistema. Se aplica al instante y se guarda en este PC, sin modificar los nombres de tus acciones ni los dispositivos enlazados. Los diálogos propios de Windows siguen el idioma del sistema.
- Dock con hasta 24 acciones, distribuibles en ocho páginas: aplicaciones `.exe`, accesos directos `.lnk`, enlaces HTTP/HTTPS y texto.
- Editor con imágenes propias, iconos de aplicaciones, emojis, color por acción, reordenación y cambio de página.
- Paletas Aurora, Océano, Atardecer, Bosque y Grafito; modo oscuro, iconos extragrandes y esquinas ajustables. La apariencia del PC y la del iPhone se configuran por separado.
- Volumen, silencio, copiar/pegar, inserción de texto, minimizar y maximizar la ventana activa.
- Brillo en pantallas que lo permiten mediante WMI, normalmente las integradas en portátiles. Si no está disponible, no se anuncia ese control.
- Enlace local, descubrimiento Bonjour/mDNS y revocación de dispositivos desde la aplicación.

## Límites de esta primera versión

- No incluye Recientes, Atajos de Apple, bandeja del sistema ni inicio automático.
- «Ocultar» minimiza; «pantalla completa» maximiza la ventana. Algunas aplicaciones pueden ignorar los controles.
- La entrada de teclado no controla ventanas elevadas, pantallas de seguridad ni todas las aplicaciones o juegos.
- Los iconos importados se reducen a 128 × 128; imágenes demasiado complejas se rechazan para respetar el límite de mensajes del iPhone.
- Sin compatibilidad nativa ARM64 ni Windows 10 en este paquete.
- Compilada desde macOS y comprobada con pruebas del protocolo y de interoperabilidad Swift/.NET. **La interfaz WPF, los permisos del firewall y los controles de hardware aún requieren una prueba real en Windows.**

## Datos y seguridad

La configuración se guarda en `%LOCALAPPDATA%\PhoneDock`. Las credenciales se protegen con DPAPI, ligadas al usuario de Windows. Al olvidar un dispositivo se elimina su credencial y se desconectan sus sesiones. Los archivos dañados no se sustituyen automáticamente.

El enlace usa P-256, HKDF-SHA256 y ChaCha20-Poly1305 para transferir la credencial. Las órdenes posteriores se autentican con HMAC-SHA256 y se comprueban identificadores repetidos. **El tráfico posterior no está cifrado**: usa únicamente redes privadas de confianza. No expongas el puerto TCP 49832 a Internet. La detección usa mDNS UDP 5353. No hay cuentas, nube ni telemetría propia.

## Desarrollo

Requiere .NET SDK 10. La aplicación se puede compilar desde macOS con `EnableWindowsTargeting`, pero solo se ejecuta en Windows.

```sh
dotnet build Windows/PhoneDock
dotnet run --project Windows/PhoneDock.Core.Tests
dotnet publish Windows/PhoneDock -c Release -r win-x64 --self-contained true -o Windows/dist/PhoneDock-Windows-x64
```

El proyecto `PhoneDock.Core` contiene framing, firma, enlace y servidor TCP. `PhoneDock` contiene la interfaz WPF y las integraciones Windows. `PhoneDock.Core.Tests` no requiere frameworks de pruebas externos. `scripts/Interop.swift` usa los modelos reales de la app Apple para verificar firmas y descifrar credenciales producidas por Windows.

### Comprobación manual en un PC

- Abrir sin privilegios de administrador; comprobar las cinco pestañas, tema claro/oscuro, navegación por teclado y escala de pantalla 100/150/200 %.
- Enlazar desde el iPhone por descubrimiento y por IP; probar PIN incorrecto y reconexión al reiniciar.
- Agregar, editar, mover y borrar una acción de cada tipo; reiniciar y verificar persistencia y actualización en el iPhone.
- Probar volumen, silencio, texto Unicode, copiar/pegar, minimizar/maximizar y brillo compatible.
- Revocar el iPhone y comprobar que deja de controlar el PC.
- Comprobar el comportamiento con red desconectada, sin dispositivo de audio y con una segunda instancia abierta.

Consulta también `THIRD-PARTY-NOTICES.md`.
