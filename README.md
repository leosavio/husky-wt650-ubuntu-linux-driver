Que jornada\! Fazer todo esse processo de engenharia reversa, desde o `lm-sensors`, passando pelo `EPIPE` do Python, até a captura de pacotes com VMware e Wireshark para descobrir o protocolo `0x9f`.

-----

# Driver Linux para o Display do AIO Husky Ice Comet (WT650)

Este repositório contém um driver não-oficial e um script de instalação para fazer o display de temperatura do AIO (Water Cooler) **Husky Ice Comet WT650** funcionar no Linux (Ubuntu/Debian e derivados).

Por padrão, a Husky não fornece software para Linux, e o display do AIO não exibe a temperatura da CPU. Este projeto resolve esse problema.

 \#\# 🚀 Instalação Rápida (Ubuntu/Debian)

Este repositório inclui um script "mestre" que automatiza todo o processo.

Ele irá:

1.  Instalar as dependências (`lm-sensors`, `python3-pip`, `git`).
2.  Instalar a biblioteca `pyusb`.
3.  Configurar o `lm-sensors` para ler a temperatura da sua CPU.
4.  Criar o driver Python (`display_control_FINAL.py`) em `/opt/`.
5.  Criar uma regra `udev` para dar ao sistema permissão para acessar o USB do AIO.
6.  Criar um serviço `systemd` (`husky-aio-display.service`) para que o driver inicie automaticamente com o seu computador.

### Passos de Instalação

Abra seu terminal e execute os seguintes comandos:

```bash
# 1. Clone este repositório
git clone https://github.com/leosavio/husky-wt650-ubuntu-linux-driver.git
cd husky-wt650-ubuntu-linux-driver/driver/

# 2. Dê permissão de execução ao script
chmod +x ubuntu_linux_driver_husky_wt650.sh

# 3. Execute o script como root
sudo ./ubuntu_linux_driver_husky_wt650.sh
```

É isso\! Após o script terminar, o display do seu AIO deve começar a exibir a temperatura da CPU imediatamente.

-----

## 🩺 Verificando o Serviço

O script instala um serviço que roda em segundo plano. Você pode verificar o status dele a qualquer momento:

```bash
systemctl status husky-aio-display.service
```

Se tudo estiver correto, você verá um status de `active (running)` e o log do script mostrando o envio da temperatura.

Para ver o log em tempo real:

```bash
journalctl -fu husky-aio-display.service
```

-----

## 🔬 Como Funciona (A Engenharia Reversa)

Este driver só foi possível após uma análise do protocolo USB do dispositivo. Ao contrário da maioria dos AIOs, este modelo não é compatível com o `liquidctl`.

A solução foi encontrada "espionando" (sniffing) a comunicação entre o software oficial do Windows e o AIO, usando VMware, Wireshark e USBPcap.

### O Protocolo Descoberto

Descobrimos que o AIO **Husky Ice Comet WT650** (ID USB `aa88:8666`) não usa o método comum `URB_CONTROL` (`ctrl_transfer`) para enviar dados.

Em vez disso, ele espera um pacote `URB_INTERRUPT out` enviado para o **Endpoint `0x02`**.

O formato do pacote de dados é um *payload* de 8 bytes, onde o **primeiro byte é o valor da temperatura em decimal** (0-255), e o restante é preenchido com zeros.

  * **Exemplo para 51°C:** `[51, 0, 0, 0, 0, 0, 0, 0]`
  * **Exemplo para 159°C (capturado na VM):** `[159, 0, 0, 0, 0, 0, 0, 0]` (que em hexadecimal é `0x9f`)

O script `display_control_FINAL.py` simplesmente lê a temperatura do `lm-sensors` (especificamente do `k10temp` em CPUs AMD) e envia esse pacote de 8 bytes para o AIO a cada 2 segundos.

-----

## 🛠️ Contexto Técnico e Hardware (Logs)

Esta solução foi desenvolvida e testada no seguinte hardware:

  * **CPU:** AMD Ryzen 9 5900X
  * **Placa-Mãe:** ASUS TUF GAMING B550-PLUS (WI-FI)
  * **Water Cooler:** Husky Ice Comet WT650 (ID USB: `aa88:8666`)
  * **OS:** Ubuntu 22.04 (Kernel 6.8)

### Detecção do `lm-sensors`

O `sensors-detect` foi crucial para identificar os sensores corretos. Os drivers-chave encontrados foram:

  * **`k10temp`**: Para a temperatura da CPU AMD (Tctl).
  * **`nct6775`**: Para os sensores da placa-mãe (Super I/O).

<!-- end list -->

```log
# Log do sensors-detect (modo automático)
Driver `nct6775':
  * ISA bus, address 0x290
    Chip `Nuvoton NCT6798D Super IO Sensors' (confidence: 9)

Driver `k10temp' (autoloaded):
  * Chip `AMD Family 17h thermal sensors' (confidence: 9)
```

### Driver Oficial (Windows)

Para referência, o driver oficial do Windows (que foi usado para a engenharia reversa) pode ser encontrado na página da Kabum ou neste link direto do Google Drive:

  * [Link do Driver Windows (Google Drive)](https://drive.google.com/file/d/1NiQT3URlGBtw2bgbuxlJ353Eh_2ZmZXK/view)
