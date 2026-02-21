#!/usr/bin/env bash
source ./funciones.sh
if ! isRoot; then
    echo "[OJITO] Debes ejectuar este script en modo ROOT"
    exit 1
fi
echo "Script de configuracion de SSH"
if ! validacion_servicio openssh-server; then
    if getService openssh-server; then
        systemctl enable ssh
        systemctl start ssh
    fi
fi
echo "Configurando Interfaz a usar en ssh"
config_redsv enp0s10 192.168.99.10 24
