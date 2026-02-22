#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$PROJECT_ROOT/linux/lib_func.sh"

if ! isRoot; then
    echo "[OJITO] Debes ejectuar este script en modo ROOT"
    exit 1
fi
echo "Script de configuracion de SSH"
if ! isInstalled openssh-client; then
    if getService openssh-client; then
        systemctl enable ssh
        systemctl start ssh
    fi
fi
if ! valid_interfaz enp0s9; then
    echo "Configurando Interfaz a usar en ssh"
    setLocalRed enp0s9 192.168.99.15 24
fi
echo "Terminando configuracion.."
sleep 4
sshConecTo luisd 192.168.99.10
