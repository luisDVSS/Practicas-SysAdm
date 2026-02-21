#!/usr/bin/env bash
validacion_servicio() {
    local service="$1"
    echo "Validando que el servicio: $service este instlado.."
    if dpkg -s "$service"; then
        echo "El servicio '$service' ya se encuentra instalado"
        return 0
    else
        echo "El servicio '$service' NO se encuentra instalado"
        return 1
    fi

}
getService() {
    echo "Instalando..-"
    apt update -y "$@" &>/dev/null
    apt install -y "$@" &>/dev/null
}

isRoot() {
    if [[ $EUID -ne 0 ]]; then
        echo "Este script debe ejecutarse como root"
        exit 1
    fi
}

conecTo() {
    local user="$1"
    local ip="$2"
    ssh "$user"@"$ip"
}

config_redsv() {
    interfaz="$1"
    ip="$2"
    prefijo="$3"
    if [[ -z $interfaz || -z $ip || -z $prefijo ]]; then
        echo "Uno de los datos esta vacio"
        exit 1
    fi
    echo "Inhabilitando otras configuraciones configuraciones previas..."
    sudo grep -l "^[[:space:]]*$interfaz:" /etc/netplan/*.yaml 2>/dev/null | xargs -r -I{} sudo mv {} {}.bak
    archivo="/etc/netplan/50-${interfaz}-estatica.yaml"
    echo "Configurando interfaz: $interfaz..."
    sudo tee "$archivo" >/dev/null <<EOF
network:
  version: 2
  ethernets:
    $interfaz:
      dhcp4: no
      addresses:
       - $ip/$prefijo
EOF
    sudo chown root:root "$archivo"
    sudo chmod 600 "$archivo"
    echo "Aplicando configuracion..."
    sudo netplan apply
    echo "Configuracion del servidor aplicada correctamente :D"

}
validar_interfaz() {
    echo "Validando que la interfaz exista"
    local interfaz="$1"

    if [[ -z "$interfaz" ]]; then
        echo "La interfaz no existe"
        return 1
    fi

    # Verificar que la interfaz exista
    if ! ip link show "$interfaz" &>/dev/null; then
        echo "La interfaz $interfaz no existe."
        return 1
    fi

    # Verificar que esté UP
    if ! ip link show "$interfaz" | grep -q "state UP"; then
        echo "La interfaz $interfaz está DOWN."
        return 1
    fi

    # Verificar que tenga IP asignada
    if ! ip -4 addr show "$interfaz" | grep -q "inet "; then
        echo "La interfaz $interfaz no tiene IP asignada."
        return 1
    fi

    echo "La interfaz $interfaz está activa y con IP configurada."
    return 0
}
