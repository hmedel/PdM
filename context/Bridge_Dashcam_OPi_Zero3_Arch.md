# Bridge Dashcam - Orange Pi Zero 3 con Orange Pi OS (Arch)

## Especificaciones Tecnicas Completas

**Fecha:** Enero 2025  
**Proyecto:** Sistema Bridge para Dashcam Vehicular  
**Plataforma:** Orange Pi Zero 3 4GB + Orange Pi OS (Arch Linux ARM)

---

## 1. Plataforma de Hardware

### 1.1 Single Board Computer

| Especificacion | Detalle |
|----------------|---------|
| **Modelo** | Orange Pi Zero 3 4GB |
| **SoC** | Allwinner H618 (compatible H616) |
| **CPU** | 4x Cortex-A53 @ 1.5GHz (ARMv8-A, AArch64) |
| **GPU** | Mali-G31 MP2 (OpenGL ES 3.2, Vulkan 1.1) |
| **RAM** | 4GB LPDDR4 |
| **Almacenamiento** | microSD (hasta 256GB), SPI Flash 16MB |
| **Ethernet** | Gigabit Ethernet (Motorcomm YT8531C PHY) |
| **WiFi** | 802.11 a/b/g/n/ac (2.4GHz + 5GHz) |
| **Bluetooth** | 5.0 |
| **USB** | 1x USB 2.0 Type-A, 1x USB 2.0 OTG (Type-C) |
| **GPIO** | 26-pin header (3x I2C, 2x UART, 1x SPI) |
| **Alimentacion** | 5V/2A via USB-C |
| **Dimensiones** | 52mm x 53mm |
| **Consumo** | ~3W idle, ~5W carga |
| **Precio** | ~$25 USD |

### 1.2 Interfaces GPIO Disponibles

```
Header 26-pin:
- I2C: TWI2, TWI3, TWI4
- UART: UART2 (con handshake), UART5
- SPI: SPI1 (2x CS)
- PWM: PWM1, PWM2 (soporte limitado en kernel)

Header 13-pin:
- USB 2.0 adicional
- Audio analogico (line-out)
- TV-Out
- IR receptor
```

---

## 2. Sistema Operativo

### 2.1 Orange Pi OS (Arch Linux ARM)

| Componente | Version/Detalle |
|------------|-----------------|
| **Distribucion** | Orange Pi OS basado en Arch Linux ARM |
| **Arquitectura** | aarch64 (ARM64) |
| **Kernel** | 6.1.31-sunxi64 (Orange Pi) / 6.6+ (mainline) |
| **Device Tree** | sun50i-h618-orangepi-zero3.dtb |
| **Init System** | systemd |
| **Package Manager** | pacman |

### 2.2 Soporte de Kernel Mainline

```
Kernel >= 6.5-rc1: Soporte PMIC (AXP313a) y Ethernet PHY (Motorcomm)
Kernel >= 6.6:     Device Tree Binary (DTB) incluido
Kernel >= 6.1.31:  Orange Pi OS oficial (probado y estable)
```

### 2.3 Imagen Recomendada

```bash
# Descargar desde Orange Pi oficial
# Archivo: Opios-arch-aarch64-xfce-opizero3-23.07-linux6.1.31.img.xz

# Flashear a microSD
xzcat Opios-arch-aarch64-*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress

# Primera configuracion
# Usuario: orangepi / ContraseÃ±a: orangepi
# root: root / ContraseÃ±a: orangepi
```

---

## 3. Modem 4G LTE

### 3.1 Modulo Recomendado: Quectel EC25-AF

| Especificacion | Detalle |
|----------------|---------|
| **Modelo** | Quectel EC25-AF (Americas) |
| **Formato** | USB Dongle |
| **Categoria LTE** | Cat 4 (150 Mbps DL / 50 Mbps UL) |
| **Tecnologias** | LTE-FDD, WCDMA, GSM |
| **VID:PID** | 2c7c:0125 |
| **Driver Linux** | qmi_wwan (nativo en kernel >= 4.9) |
| **Precio** | ~$40-45 USD |

### 3.2 Bandas LTE Soportadas

| Banda | Frecuencia | Telcel Mexico | Notas |
|-------|------------|---------------|-------|
| B2 | 1900 MHz | No | PCS |
| **B4** | 1700/2100 MHz | **SI (Principal)** | AWS |
| B5 | 850 MHz | No | Cellular |
| **B7** | 2600 MHz | **SI** | IMT-E |
| B12 | 700 MHz | No | Lower SMH |
| B13 | 700 MHz | No | Verizon |
| **B66** | 1700/2100 MHz | **SI** | AWS extendido |

### 3.3 Compatibilidad Kernel

```
Kernel >= 4.9:   qmi_wwan con raw IP mode
Kernel >= 4.5:   Quectel VID 0x2c7c en option driver
Kernel 6.1.31:   Soporte completo sin parches

Modulos requeridos:
- qmi_wwan      (CONFIG_USB_NET_QMI_WWAN)
- option        (CONFIG_USB_SERIAL_OPTION)
- cdc_wdm       (CONFIG_USB_WDM)
- usbnet        (CONFIG_USB_USBNET)
```

### 3.4 Configuracion en Arch Linux

```bash
# Instalar paquetes necesarios
sudo pacman -S modemmanager networkmanager libqmi

# Habilitar servicios
sudo systemctl enable --now ModemManager
sudo systemctl enable --now NetworkManager

# Verificar deteccion del modem
lsusb | grep 2c7c
# Bus 001 Device 004: ID 2c7c:0125 Quectel Wireless Solutions Co., Ltd. EC25 LTE modem

# Verificar driver cargado
lsmod | grep qmi
# qmi_wwan               xxxxx  0
# cdc_wdm                xxxxx  1 qmi_wwan

# Verificar ModemManager
mmcli -L
# /org/freedesktop/ModemManager1/Modem/0 [Quectel] EC25

# Informacion del modem
mmcli -m 0

# Crear conexion (APN Telcel)
nmcli connection add type gsm ifname '*' con-name 'Telcel-LTE' apn 'internet.itelcel.com'

# Activar conexion
nmcli connection up Telcel-LTE

# Verificar IP asignada
ip addr show wwan0
```

### 3.5 Configuracion Raw IP Mode (si es necesario)

```bash
# Para kernels antiguos o problemas de conexion
sudo ip link set wwan0 down
echo 1 | sudo tee /sys/class/net/wwan0/qmi/raw_ip
sudo ip link set wwan0 up
```

---

## 4. Sensor IMU

### 4.1 Modulo: MPU6050 (GY-521)

| Especificacion | Detalle |
|----------------|---------|
| **Chip** | InvenSense MPU6050 |
| **Ejes** | 6 DOF (3-axis accel + 3-axis gyro) |
| **Interfaz** | I2C (direccion 0x68 o 0x69) |
| **Voltaje** | 3.3V - 5V (regulador integrado) |
| **Rango Acelerometro** | +/- 2g, 4g, 8g, 16g |
| **Rango Giroscopio** | +/- 250, 500, 1000, 2000 deg/s |
| **Precio** | ~$2-3 USD |

### 4.2 Conexion I2C

```
Orange Pi Zero 3 (Header 26-pin) -> MPU6050
-----------------------------------------
Pin 1  (3.3V)  -> VCC
Pin 6  (GND)   -> GND
Pin 3  (TWI3_SDA / PH5) -> SDA
Pin 5  (TWI3_SCL / PH4) -> SCL
```

### 4.3 Configuracion I2C en Arch

```bash
# Verificar buses I2C disponibles
ls /dev/i2c-*
# /dev/i2c-3  (TWI3 en header 26-pin)

# Instalar herramientas
sudo pacman -S i2c-tools

# Escanear dispositivos
sudo i2cdetect -y 3
#      0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 60: -- -- -- -- -- -- -- -- 68 -- -- -- -- -- -- --

# El MPU6050 aparece en direccion 0x68

# Cargar modulo del kernel (si no esta cargado)
sudo modprobe i2c-dev
```

### 4.4 Libreria Python

```bash
# Instalar dependencias
sudo pacman -S python python-pip python-smbus2

# Instalar libreria MPU6050
pip install mpu6050-raspberrypi --break-system-packages

# Script de prueba
python3 << 'EOF'
from mpu6050 import mpu6050
import time

sensor = mpu6050(0x68, bus=3)

while True:
    accel = sensor.get_accel_data()
    gyro = sensor.get_gyro_data()
    temp = sensor.get_temp()
    
    print(f"Accel: X={accel['x']:.2f} Y={accel['y']:.2f} Z={accel['z']:.2f} g")
    print(f"Gyro:  X={gyro['x']:.2f} Y={gyro['y']:.2f} Z={gyro['z']:.2f} deg/s")
    print(f"Temp:  {temp:.1f} C")
    print("-" * 50)
    time.sleep(0.5)
EOF
```

### 4.5 Umbrales de Deteccion Vehicular

| Evento | Umbral | Accion |
|--------|--------|--------|
| Frenado brusco | > 0.5g (eje Y negativo) | Alerta push |
| Aceleracion rapida | > 0.4g (eje Y positivo) | Log evento |
| Giro brusco | > 0.4g (eje X) | Log evento |
| Impacto/Colision | > 2.0g (cualquier eje) | Alerta CRITICA + solicitar video |
| Vuelco | inclinacion > 45 grados | Alerta CRITICA |

---

## 5. Lector OBD-II

### 5.1 Modulo: ELM327 USB

| Especificacion | Detalle |
|----------------|---------|
| **Chip** | ELM327 (o compatible) |
| **Interfaz** | USB (aparece como /dev/ttyUSB*) |
| **Protocolo** | OBD-II (ISO 9141, ISO 14230, CAN) |
| **Baudrate** | 38400 bps (configurable) |
| **Precio** | ~$10-15 USD |

### 5.2 Configuracion

```bash
# Instalar libreria Python
pip install obd --break-system-packages

# Verificar puerto serial
ls /dev/ttyUSB*
# /dev/ttyUSB0

# Permisos
sudo usermod -aG dialout $USER

# Script de prueba
python3 << 'EOF'
import obd

connection = obd.OBD("/dev/ttyUSB0")

if connection.is_connected():
    print("Conectado al vehiculo")
    
    # Velocidad
    cmd = obd.commands.SPEED
    response = connection.query(cmd)
    print(f"Velocidad: {response.value}")
    
    # RPM
    cmd = obd.commands.RPM
    response = connection.query(cmd)
    print(f"RPM: {response.value}")
    
    # Temperatura motor
    cmd = obd.commands.COOLANT_TEMP
    response = connection.query(cmd)
    print(f"Temp Motor: {response.value}")
else:
    print("No se pudo conectar")

connection.close()
EOF
```

### 5.3 PIDs Recomendados para Telemetria

| PID | Descripcion | Frecuencia |
|-----|-------------|------------|
| 0x0D | Velocidad | 1 Hz |
| 0x0C | RPM | 1 Hz |
| 0x05 | Temp. refrigerante | 0.1 Hz |
| 0x2F | Nivel combustible | 0.1 Hz |
| 0x11 | Posicion acelerador | 1 Hz |
| 0x1F | Tiempo encendido | 0.1 Hz |

---

## 6. Arquitectura de Software

### 6.1 Stack Completo

```
+--------------------------------------------------+
|                   SERVIDOR CENTRAL                |
|  (Traccar + PostgreSQL + MediaMTX + Web App)      |
+--------------------------------------------------+
                         ^
                         | MQTT / HTTPS
                         | (via 4G LTE)
+--------------------------------------------------+
|              ORANGE PI ZERO 3 (BRIDGE)            |
+--------------------------------------------------+
|  +------------+  +------------+  +-------------+ |
|  | FastAPI    |  | MQTT       |  | FFmpeg      | |
|  | (API Local)|  | (Paho)     |  | (Video Relay)| |
|  +------------+  +------------+  +-------------+ |
|        |               |               |         |
|  +------------+  +------------+  +-------------+ |
|  | GPS Parser |  | IMU Monitor|  | OBD Reader  | |
|  | (desde     |  | (smbus2)   |  | (python-obd)| |
|  |  dashcam)  |  +------------+  +-------------+ |
|  +------------+        |               |         |
|        |               |               |         |
+--------------------------------------------------+
         |               |               |
    [Dashcam]       [MPU6050]       [ELM327]
    (WiFi/ETH)       (I2C)          (USB)
```

### 6.2 Paquetes Arch Linux Requeridos

```bash
# Sistema base
sudo pacman -S base-devel git wget curl

# Conectividad
sudo pacman -S networkmanager modemmanager libqmi usb_modeswitch

# Python y librerias
sudo pacman -S python python-pip python-smbus2 python-paho-mqtt

# Video/Streaming
sudo pacman -S ffmpeg

# Herramientas
sudo pacman -S i2c-tools usbutils htop tmux

# Dependencias Python adicionales
pip install fastapi uvicorn obd mpu6050-raspberrypi --break-system-packages
```

### 6.3 Servicios systemd

```ini
# /etc/systemd/system/bridge-telemetry.service
[Unit]
Description=Bridge Dashcam Telemetry Service
After=network-online.target ModemManager.service
Wants=network-online.target

[Service]
Type=simple
User=orangepi
WorkingDirectory=/opt/bridge
ExecStart=/usr/bin/python3 /opt/bridge/main.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

---

## 7. Flujo de Datos y Consumo

### 7.1 Telemetria Continua

| Dato | Frecuencia | Tamano/msg | Consumo Mensual |
|------|------------|------------|-----------------|
| GPS (desde dashcam) | cada 15 seg | ~100 bytes | ~17 MB |
| OBD-II | cada 10 seg | ~150 bytes | ~39 MB |
| Heartbeat | cada 60 seg | ~50 bytes | ~2 MB |
| **Subtotal Telemetria** | | | **~58 MB/mes** |

### 7.2 Alertas (Push)

| Evento | Frecuencia Est. | Tamano | Consumo Mensual |
|--------|-----------------|--------|-----------------|
| Frenado brusco | ~10/dia | ~200 bytes | ~60 KB |
| Evento IMU | ~5/dia | ~200 bytes | ~30 KB |
| **Subtotal Alertas** | | | **~100 KB/mes** |

### 7.3 Video Bajo Demanda

| Escenario | Duracion | Calidad | Consumo |
|-----------|----------|---------|---------|
| Vista rapida | 2 min | 480p | ~30 MB |
| Revision evento | 5 min | 720p | ~150 MB |
| Revision extendida | 10 min | 720p | ~300 MB |
| **Estimado mensual** | 10 min/dia | 720p | **~4.5 GB/mes** |

### 7.4 Consumo Total Estimado

```
Telemetria continua:     ~60 MB/mes
Alertas push:            ~0.1 MB/mes
Video bajo demanda:      ~4.5 GB/mes (variable)
-----------------------------------------
TOTAL:                   ~5 GB/mes (uso moderado)
```

---

## 8. Alimentacion Vehicular

### 8.1 Convertidor DC-DC

| Especificacion | Requerimiento |
|----------------|---------------|
| **Entrada** | 9-36V DC (compatible 12V/24V vehicular) |
| **Salida** | 5V / 3A minimo |
| **Tipo** | Buck converter con protecciones |
| **Protecciones** | Sobrevoltaje, sobrecorriente, inversion polaridad |
| **Precio** | ~$8-12 USD |

### 8.2 Consumo del Sistema

| Componente | Consumo Tipico | Consumo Max |
|------------|----------------|-------------|
| Orange Pi Zero 3 | 3W | 5W |
| Quectel EC25-AF | 2W | 4W |
| MPU6050 | <0.01W | 0.01W |
| ELM327 USB | 0.5W | 1W |
| **TOTAL** | **~5.5W** | **~10W** |

### 8.3 Conexion

```
Bateria Vehiculo (12V)
        |
        v
+------------------+
| DC-DC Converter  |
| IN: 9-36V        |
| OUT: 5V/3A       |
+------------------+
        |
        v
   USB-C (5V/3A)
        |
        v
  Orange Pi Zero 3
        |
        +---> USB-A: Quectel EC25 + ELM327 (via hub si es necesario)
        +---> I2C: MPU6050
```

---

## 9. Lista de Materiales (BOM)

| # | Componente | Modelo | Cantidad | Precio USD | Subtotal |
|---|------------|--------|----------|------------|----------|
| 1 | SBC | Orange Pi Zero 3 4GB | 1 | $25 | $25 |
| 2 | Modem 4G | Quectel EC25-AF USB Dongle | 1 | $42 | $42 |
| 3 | IMU | MPU6050 GY-521 | 1 | $3 | $3 |
| 4 | OBD-II | ELM327 USB | 1 | $12 | $12 |
| 5 | DC-DC | Buck 9-36V a 5V/3A | 1 | $10 | $10 |
| 6 | microSD | 32GB Clase 10 A1 | 1 | $8 | $8 |
| 7 | Cables | DuPont, USB, alimentacion | 1 | $5 | $5 |
| 8 | Carcasa | Impresa 3D o generica | 1 | $5 | $5 |
| | | | | **TOTAL** | **$110 USD** |

**Precio en MXN:** ~$2,200 MXN (al tipo de cambio de $20 MXN/USD)

---

## 10. Comparativa vs Sistema Completo

| Aspecto | Bridge (Este documento) | Sistema Completo MDVR |
|---------|------------------------|----------------------|
| **Costo Hardware** | $110 USD | $545 USD |
| **Procesamiento AI** | En dashcam existente | Local (NPU RK3588) |
| **Camaras** | Usa dashcam existente | 4x IP dedicadas |
| **Consumo electrico** | ~6W | ~35W |
| **Complejidad** | Baja | Alta |
| **Video local** | No (relay bajo demanda) | Si (NVR local) |
| **Instalacion** | Simple | Compleja |
| **Ahorro** | 80% vs completo | - |

---

## 11. Notas de Compatibilidad

### 11.1 Kernel y Drivers

```
VERIFICADO COMPATIBLE:
- Orange Pi OS (Arch) kernel 6.1.31-sunxi64
- Quectel EC25-AF: qmi_wwan nativo (VID 2c7c, PID 0125)
- MPU6050: i2c-dev + smbus2
- ELM327: USB serial option driver
- WiFi/BT: Integrado en SoC H618

NOTAS:
- No requiere compilar drivers adicionales
- ModemManager detecta EC25 automaticamente
- I2C bus 3 disponible en header 26-pin
```

### 11.2 Limitaciones Conocidas

1. **PWM/SPDIF/I2S**: Soporte limitado en kernel actual
2. **Variante 1.5GB RAM**: Problemas con U-Boot (usar 2GB o 4GB)
3. **Reboot vs Shutdown**: Puede requerir power cycle en algunos casos
4. **USB Hub**: Puede necesitarse si se usan multiples dispositivos USB

---

## 12. Referencias

- [Orange Pi Zero 3 Wiki](http://www.orangepi.org/orangepiwiki/index.php/Orange_Pi_Zero_3)
- [linux-sunxi H618](https://linux-sunxi.org/Xunlong_Orange_Pi_Zero3)
- [Quectel EC25 Linux Driver Guide](https://forums.quectel.com/)
- [Arch Linux ARM](https://archlinuxarm.org/)
- [Armbian Orange Pi Zero 3](https://www.armbian.com/orange-pi-zero-3/)

---

*Documento generado: Enero 2025*  
*Version: 1.0*
