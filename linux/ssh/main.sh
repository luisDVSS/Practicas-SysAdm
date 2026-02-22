#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib_funciones.sh"

if ! isRoot; then
    echo "[OJITO] Debes ejectuar este script en modo ROOT"
    exit 1
fi
echo "Script de configuracion de SSH"
if ! isInstalled openssh-server; then
    if getService openssh-server; then
        systemctl enable ssh
        systemctl start ssh
    fi
fi
echo "Configurando Interfaz a usar en ssh"
setLocalRed enp0s10 192.168.99.10 24
