#!/usr/bin/env bash
source ./funciones_ssh.sh
if ! isRoot; then
    echo "[OJITO] Debes ejectuar este script en modo ROOT"
    exit 1
fi
echo "Script de configuracion de SSH"
if ! validacion_servicio openssh-client; then
    if getService openssh-client; then
        systemctl enable ssh
        systemctl start ssh
    fi
fi
if ! validar_interfaz enp0s9; then
    echo "Configurando Interfaz a usar en ssh"
    config_redsv enp0s9 192.168.99.15 24
fi
echo "Terminando configuracion.."
sleep 4
conecTo luisd 192.168.99.10
