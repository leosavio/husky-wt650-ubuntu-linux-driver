#!/bin/bash
# ------------------------------------------------------------------
# Script Assertivo para Instalação do VMware Workstation Player
# ------------------------------------------------------------------
set -e # Garante que o script pare imediatamente se houver um erro

# --- 1. Instalar Dependências de Compilação (Módulos do Kernel) ---
# O VMware precisa compilar módulos do kernel (vmmon, vmnet)
echo "⚙️  Instalando dependências de compilação (build-essential, headers)..."
sudo apt update
sudo apt install -y build-essential linux-headers-$(uname -r)

# --- 2. Baixar o VMware Player ---
echo "📥 Baixando o bundle de instalação do VMware Player..."
echo "https://diolinux.com.br/tutoriais/guia-instalar-vmware-workstation.html"
VM_BUNDLE_FILE="VMware-Workstation-Full-25H2-24995812.x86_64.bundle"

if [ ! -f "$VM_BUNDLE_FILE" ]; then
    echo "❌ Erro: Falha ao baixar o arquivo do VMware."
    exit 1
fi

echo "🔧 Tornando o instalador executável..."
chmod +x "$VM_BUNDLE_FILE"

# --- 3. Instalar o VMware (Modo Não Interativo) ---
echo "🚀 Executando o instalador do VMware (aceitando EULAs)..."
# Flags para uma instalação rápida e assertiva:
# --required: Pula perguntas opcionais
# --eulas-agreed: Aceita os termos de licença automaticamente
sudo ./"$VM_BUNDLE_FILE" --required --eulas-agreed

echo "🧹 Limpando o arquivo de instalação..."
rm "$VM_BUNDLE_FILE"

echo "---"
echo "✅ Sucesso! O VMware Workstation Player foi instalado."
echo "Você pode iniciá-lo pelo seu menu de aplicativos."
echo "---"
