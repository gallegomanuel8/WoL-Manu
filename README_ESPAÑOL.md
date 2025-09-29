# Wake-on-LAN para macOS

Una aplicación nativa de macOS desarrollada en Swift y SwiftUI para encender remotamente dispositivos usando el protocolo Wake-on-LAN.

## Características

- **Interfaz gráfica sencilla** desarrollada en SwiftUI
- **Envío de Magic Packets** para encender dispositivos remotos
- **Monitor de estado** con ping periódico cada 5 segundos
- **Indicador luminoso** (verde/rojo) que muestra el estado del dispositivo
- **Configuración persistente** guardada en archivo JSON
- **Validación de datos** para IP y direcciones MAC

## Funcionalidades

### Ventana Principal
- Botón **"Encender"** para enviar el paquete Wake-on-LAN
- Botón **"Configuración"** para abrir la ventana de configuración
- **Indicador de estado** con círculo de color y descripción
- **Información del dispositivo** (nombre e IP)

### Ventana de Configuración
- Campo **"Nombre del Equipo"** para identificar el dispositivo
- Campo **"Dirección IP"** con validación de formato
- Campo **"Dirección MAC"** con validación y formato automático
- Botón **"Guardar"** para persistir la configuración

## Tecnologías Utilizadas

- **Swift** como lenguaje de programación
- **SwiftUI** para la interfaz gráfica
- **Network Framework** para envío de paquetes UDP
- **Foundation** para manejo de archivos JSON
- **Process** para ejecutar comandos ping

## Estructura del Proyecto

```
WoL Manu/
├── WoL_ManuApp.swift          # Punto de entrada de la aplicación
├── ContentView.swift          # Ventana principal
├── ConfigurationView.swift    # Ventana de configuración
├── ConfigurationModel.swift   # Modelo de datos y persistencia
├── WakeOnLANService.swift     # Servicio Wake-on-LAN
├── PingService.swift          # Servicio de ping periódico
└── config.json               # Archivo de configuración (generado automáticamente)
```

## Configuración

La configuración se guarda automáticamente en:
```
~/Projects/WoL Manu/config.json
```

Formato del archivo JSON:
```json
{
  "deviceName": "PC Gaming",
  "ipAddress": "192.168.1.100",
  "macAddress": "AA:BB:CC:DD:EE:FF"
}
```

## Funcionamiento Técnico

### Magic Packet
- Construye el paquete mágico: 6 bytes `0xFF` + 16 repeticiones de la dirección MAC
- Envía el paquete vía UDP al puerto 9 como broadcast (255.255.255.255)

### Monitor de Estado
- Ejecuta `ping -c 1 -W 3000 <IP>` cada 5 segundos
- Actualiza el indicador visual según la respuesta del ping

### Validaciones
- **IP Address**: Valida formato IPv4 (0.0.0.0 - 255.255.255.255)
- **MAC Address**: Acepta formatos con `:`, `-` o sin separadores
- **Campos requeridos**: Todos los campos deben estar completos

## Uso

1. **Primera vez**: Hacer clic en "Configuración" e introducir los datos del dispositivo
2. **Configurar**: Introducir nombre, IP y MAC address del PC a encender
3. **Guardar**: La configuración se guarda automáticamente
4. **Monitor**: El indicador muestra el estado actual del dispositivo
5. **Encender**: Usar el botón "Encender" para enviar el paquete Wake-on-LAN

## Requisitos del Dispositivo Remoto

Para que Wake-on-LAN funcione, el dispositivo remoto debe:

- Tener **Wake-on-LAN habilitado** en la BIOS/UEFI
- Estar **conectado por cable** (Ethernet)
- Tener **Wake-on-LAN configurado** en el sistema operativo
- Estar en la **misma red** o accesible vía broadcast

## Desarrollo

### Requisitos
- macOS 12.0+
- Xcode 14.0+
- Swift 5.7+

### Configuración del Proyecto
```
Interface: SwiftUI
Language: Swift  
Testing System: XCTest (opcional)
Storage: None
```

---

Desarrollado por Manuel Alonso Rodriguez