#!/bin/bash
# --------------------------------------------------------------------------
# SCRIPT DE INSTALAÇÃO E AUTOMAÇÃO DO DRIVER
# AIO Husky Ice Comet (aa88:8666) no Linux
# --------------------------------------------------------------------------

# Parar o script se qualquer comando falhar
set -e

echo "=== INICIANDO INSTALAÇÃO DO DRIVER AIO HUSKY (aa88:8666) ==="
echo ""

# --- PASSO 1/7: Instalação de Dependências do Sistema ---
echo "PASSO 1/7: Instalando dependências (lm-sensors, python3-pip, git)..."
apt update
apt install -y lm-sensors python3 python3-pip git
echo "Dependências do sistema instaladas."
echo ""

# --- PASSO 2/7: Instalação de Dependências Python ---
echo "PASSO 2/7: Instalando biblioteca Python (pyusb)..."
pip3 install pyusb
echo "PyUSB instalado."
echo ""

# --- PASSO 3/7: Configuração do lm-sensors ---
echo "PASSO 3/7: Detectando sensores (lm-sensors)..."
# Usamos '--auto' para aceitar os padrões sem interação do usuário
sensors-detect --auto
echo "Carregando módulos do kernel detectados..."
service kmod start
echo "Configuração do lm-sensors concluída."
echo ""

# --- PASSO 4/7: Criação do Script do Driver ---
DRIVER_DIR="/opt/husky-aio-driver"
DRIVER_FILE="$DRIVER_DIR/display_control_FINAL.py"
SENSOR_NAME="k10temp-pci-00c3.Tctl" # Sensor que identificamos

echo "PASSO 4/7: Criando o script do driver em $DRIVER_FILE..."
mkdir -p "$DRIVER_DIR"

# Usamos 'cat' com HEREDOC para criar o arquivo Python
# Você pediu para não mostrar o código, então o script apenas o cria.
cat > "$DRIVER_FILE" <<'EOF'
#!/usr/bin/env python3

import sys
import time
import argparse
import usb.core
import usb.util
import signal
from pathlib import Path

# --- Protocolo Descoberto ---
VENDOR_ID = 0xAA88
PRODUCT_ID = 0x8666
ENDPOINT_ADDRESS = 0x02 
PACKET_SIZE = 8
# ----------------------------------------------------

def find_device():
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID)
    if dev is None:
        raise ValueError(f"Dispositivo AIO não encontrado (ID: {hex(VENDOR_ID)}:{hex(PRODUCT_ID)}). Verifique conexões/udev.")
    
    try:
        if dev.is_kernel_driver_active(0):
            print("Desanexando driver do kernel...")
            dev.detach_kernel_driver(0)
            usb.util.claim_interface(dev, 0)
            print("Dispositivo reivindicado.")
    except usb.core.USBError as e:
        sys.exit(f"Erro ao reivindicar: {e}. (Tente rodar com sudo se o udev falhou)")
    except NotImplementedError:
        pass

    return dev

def send_temp_to_device(dev, temp):
    if temp < 0:
        temp = 0
    if temp > 99:
        temp = 99
    
    temp_int = int(round(temp))

    packet = [0] * PACKET_SIZE
    packet[0] = temp_int

    print(f"Enviando: {temp_int}°C -> Pacote: {packet}")

    try:
        dev.write(ENDPOINT_ADDRESS, packet)
    except usb.core.USBError as e:
        print(f"Erro ao enviar dados para o AIO: {e}")

def get_sensor_temp(sensor_path):
    try:
        temp_raw = Path(sensor_path).read_text()
        temp_mC = int(temp_raw)
        temp_C = temp_mC / 1000.0
        return temp_C
    except FileNotFoundError:
        sys.exit(f"Erro: Arquivo do sensor não encontrado: {sensor_path}")
    except Exception as e:
        print(f"Erro ao ler o sensor: {e}")
        return 0

def signal_handler(sig, frame):
    print("\nInterrupção recebida. Tentando redefinir o display para 0°C...")
    try:
        if dev:
            send_temp_to_device(dev, 0)
            usb.util.release_interface(dev, 0)
            print("Interface liberada.")
    except Exception as e:
        print(f"Erro ao liberar interface: {e}")
    sys.exit(0)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Controla o display de AIOs (aa88:8666).")
    parser.add_argument(
        '-s', '--sensor', 
        type=str, 
        required=True, 
        help="Caminho/Nome do sensor (ex: k10temp-pci-00c3.Tctl)"
    )
    parser.add_argument(
        '-i', '--interval', 
        type=int, 
        default=2, 
        help="Intervalo de atualização em segundos (padrão: 2)"
    )
    args = parser.parse_args()

    signal.signal(signal.SIGINT, signal_handler)

    sensor_name = args.sensor
    sensor_path = ""
    if "/" in sensor_name:
        sensor_path = sensor_name
    else:
        base_path = Path("/sys/class/hwmon")
        found = False
        for hmon in base_path.glob("hwmon*"):
            chip_name_path = hmon / "name"
            if chip_name_path.exists():
                chip_name = chip_name_path.read_text().strip()
                if sensor_name.startswith(chip_name):
                    sensor_label_name = sensor_name.split('.')[-1]
                    for label_file in hmon.glob("temp*_label"):
                        label = label_file.read_text().strip()
                        if label == sensor_label_name:
                            input_file_name = label_file.name.replace("_label", "_input")
                            sensor_path = hmon / input_file_name
                            found = True
                            break
            if found:
                break
        if not found:
            sys.exit(f"Erro: Não foi possível encontrar o caminho para o sensor '{sensor_name}'.")

    print(f"Dispositivo AIO: {hex(VENDOR_ID)}:{hex(PRODUCT_ID)} @ Endpoint {hex(ENDPOINT_ADDRESS)}")
    print(f"Monitorando sensor: {sensor_name} (Caminho: {sensor_path})")
    print(f"Intervalo de atualização: {args.interval}s")
    print("Pressione Ctrl+C para sair.")

    dev = None
    try:
        dev = find_device()
        while True:
            temp = get_sensor_temp(sensor_path)
            send_temp_to_device(dev, temp)
            time.sleep(args.interval)
    
    except ValueError as e:
        print(e)
    except KeyboardInterrupt:
        signal_handler(None, None)
    finally:
        if dev:
            try:
                usb.util.release_interface(dev, 0)
            except Exception as e:
                pass
EOF

# Tornar o script Python executável
chmod +x "$DRIVER_FILE"
echo "Script do driver criado."
echo ""

# --- PASSO 5/7: Criação da Regra UDEV (Permissão USB) ---
UDEV_RULE_FILE="/etc/udev/rules.d/99-husky-aio.rules"
echo "PASSO 5/7: Criando regra UDEV em $UDEV_RULE_FILE..."

cat > "$UDEV_RULE_FILE" <<'EOF'
# Permissão de acesso para o AIO Husky Ice Comet (aa88:8666)
SUBSYSTEM=="usb", ATTR{idVendor}=="aa88", ATTR{idProduct}=="8666", MODE="0666"
EOF

echo "Recarregando regras UDEV..."
udevadm control --reload-rules
udevadm trigger
echo "Regra UDEV aplicada."
echo ""

# --- PASSO 6/7: Criação do Serviço Systemd ---
SERVICE_FILE="/etc/systemd/system/husky-aio-display.service"
PYTHON_PATH=$(which python3) # Encontra o caminho do python3

echo "PASSO 6/7: Criando o serviço systemd em $SERVICE_FILE..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Husky Ice Comet (aa88:8666) AIO Display Driver
After=multi-user.target

[Service]
Type=simple
User=root
# O 'Restart' garante que ele volte se falhar
Restart=always
RestartSec=3
# Comando para executar (usando o sensor que descobrimos):
ExecStart=$PYTHON_PATH $DRIVER_FILE --sensor $SENSOR_NAME --interval 2

[Install]
WantedBy=multi-user.target
EOF

echo "Serviço systemd criado."
echo ""

# --- PASSO 7/7: Habilitando e Iniciando o Serviço ---
echo "PASSO 7/7: Habilitando e iniciando o serviço 'husky-aio-display'..."
systemctl daemon-reload # Carrega o novo arquivo .service
systemctl enable husky-aio-display.service # Habilita na inicialização
systemctl start husky-aio-display.service # Inicia agora

echo "-----------------------------------------------------------------"
echo "✅ INSTALAÇÃO CONCLUÍDA!"
echo ""
echo "O serviço 'husky-aio-display' está agora em execução."
echo "O display do seu AIO deve estar mostrando a temperatura da CPU."
echo ""
echo "Para verificar o status do serviço a qualquer momento, use:"
echo "systemctl status husky-aio-display.service"
echo "-----------------------------------------------------------------"

exit 0