#!/usr/bin/env python3

import sys
import time
import argparse
import usb.core
import usb.util
import signal
from pathlib import Path

# --- Protocolo Descoberto (Obrigado, Wireshark!) ---
VENDOR_ID = 0xAA88
PRODUCT_ID = 0x8666
# Nós descobrimos que ele usa 'URB_INTERRUPT out' no Endpoint 0x02
ENDPOINT_ADDRESS = 0x02 
PACKET_SIZE = 8
# ----------------------------------------------------

# Função para encontrar o dispositivo USB
def find_device():
    dev = usb.core.find(idVendor=VENDOR_ID, idProduct=PRODUCT_ID)
    if dev is None:
        raise ValueError(f"Dispositivo AIO não encontrado (ID: {hex(VENDOR_ID)}:{hex(PRODUCT_ID)}). Verifique conexões/udev.")
    
    # Tenta desanexar o driver do kernel (necessário no Linux)
    try:
        if dev.is_kernel_driver_active(0):
            print("Desanexando driver do kernel...")
            dev.detach_kernel_driver(0)
            usb.util.claim_interface(dev, 0)
            print("Dispositivo reivindicado.")
    except usb.core.USBError as e:
        sys.exit(f"Erro ao reivindicar: {e}. (Tente rodar com sudo se o udev falhou)")
    except NotImplementedError:
        pass # SO não suporta (ex: Windows)

    return dev

# --- Função de Envio (MODIFICADA) ---
def send_temp_to_device(dev, temp):
    # Garante que a temperatura é um inteiro e está no intervalo de 1 byte (0-255)
    # Vamos limitar a 99 para o display
    if temp < 0:
        temp = 0
    if temp > 99:
        temp = 99
    
    temp_int = int(round(temp))

    # Cria o pacote de 8 bytes (formato: [TEMP, 0, 0, 0, 0, 0, 0, 0])
    packet = [0] * PACKET_SIZE
    packet[0] = temp_int

    print(f"Enviando: {temp_int}°C -> Pacote: {packet}")

    try:
        # Usa dev.write() para enviar um 'URB_INTERRUPT out'
        # para o endpoint que descobrimos (0x02)
        dev.write(ENDPOINT_ADDRESS, packet)
        
    except usb.core.USBError as e:
        print(f"Erro ao enviar dados para o AIO: {e}")

# Função para ler a temperatura do sensor (lm-sensors)
def get_sensor_temp(sensor_path):
    try:
        # Lê o arquivo do sensor (ex: 50000)
        temp_raw = Path(sensor_path).read_text()
        temp_mC = int(temp_raw)
        
        # Converte de miliCelsius para Celsius
        temp_C = temp_mC / 1000.0
        return temp_C # Retorna o float para arredondamento na função de envio
    except FileNotFoundError:
        sys.exit(f"Erro: Arquivo do sensor não encontrado: {sensor_path}")
    except Exception as e:
        print(f"Erro ao ler o sensor: {e}")
        return 0 # Retorna 0 em caso de falha

# Função para lidar com o sinal de interrupção (Ctrl+C)
def signal_handler(sig, frame):
    print("\nInterrupção recebida. Tentando redefinir o display para 0°C...")
    try:
        if dev:
            # Envia 0°C antes de sair
            send_temp_to_device(dev, 0)
            usb.util.release_interface(dev, 0)
            print("Interface liberada.")
    except Exception as e:
        print(f"Erro ao liberar interface: {e}")
    sys.exit(0)

# --- Função Principal (Sem modificações) ---
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

    # Resolve o caminho do sensor
    sensor_name = args.sensor
    sensor_path = ""
    if "/" in sensor_name:
        sensor_path = sensor_name # Caminho completo
    else:
        # Tenta encontrar o caminho pelo nome (ex: k10temp-pci-00c3.Tctl)
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
