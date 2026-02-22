#!/usr/bin/env bash
isInstalled() {
    echo "Validando que el servicio: $service este instlado.."
    if dpkg -s "$@" &>/dev/null; then
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
sshConecTo() {
    local user="$1"
    local ip="$2"
    ssh "$user"@"$ip"
}
setLocalRed() {
    local interfaz="$1"
    local ip="$2"
    local prefijo="$3"
    if [[ -z $interfaz || -z $ip || -z $prefijo ]]; then
        echo "Uno de los datos esta vacio"
        exit 1
    fi
    echo "Inhabilitando otras configuraciones configuraciones previas..."
    sudo grep -l "^[[:space:]]*$interfaz:" /etc/netplan/*.yaml 2>/dev/null | xargs -r -I{} sudo mv {} {}.bak
    archivo="/etc/netplan/99-${interfaz}-estatica.yaml"
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

valid_interfaz() {
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

valid_conf_ya() {
    local serv="$1"
    systemctl is-active --quiet "$serv" || return 1
    return 0
}
intToip() {
    local ip=$1
    echo "$(((ip >> 24) & 255)).$(((ip >> 16) & 255)).$(((ip >> 8) & 255)).$((ip & 255))"
}
dhcp_status() {
    systemctl restart isc-dhcp-server
    systemctl enable isc-dhcp-server
    echo "DHCP server configurado y activo"
}
validar_ip_network() {
    local ip="$1"
    local prefijo="$2"

    # Separar octetos y validar rango
    IFS='.' read -r o1 o2 o3 o4 <<<"$ip"
    for octeto in $o1 $o2 $o3 $o4; do
        if ((octeto < 0 || octeto > 255)); then
            return 1
        fi
    done

    # Bloquear redes inválidas comunes
    if [[ "$ip" == "0.0.0.0" ]] || ((o1 == 127)); then
        return 1
    fi

    # Convertir a entero
    local ip_int=$(ipToint "$ip")
    local mask=$((0xFFFFFFFF << (32 - prefijo) & 0xFFFFFFFF))

    #Calcular network real
    local network=$((ip_int & mask))

    #Verificar que la IP sea exactamente la network
    if ((ip_int == network)); then
        return 0
    else
        return 1
    fi
}
prefijo_a_mascara() {
    local prefijo=$1
    local mask=$((0xFFFFFFFF << (32 - prefijo) & 0xFFFFFFFF))
    intToip $mask
}
isHostIp() {
    local ip="$1"

    # Validar formato general
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    # Separar octetos
    IFS='.' read -r o1 o2 o3 o4 <<<"$ip"

    # Validar rango 0-255 en cada octeto
    for octeto in $o1 $o2 $o3 $o4; do
        if ((octeto < 0 || octeto > 255)); then
            return 1
        fi
    done

    # IPs no permitidas explícitamente
    if [[ "$ip" == "0.0.0.0" ||
        "$ip" == "1.0.0.0" ||
        "$ip" == "127.0.0.0" ||
        "$ip" == "127.0.0.1" ||
        "$ip" == "255.255.255.255" ]]; then
        return 1
    fi

    # Bloquear 0.x.x.x
    if ((o1 == 0)); then
        return 1
    fi

    return 0
}
isIpFormat() {
    local ip="$1"

    # Validar estructura básica X.X.X.X
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    # Separar octetos
    IFS='.' read -r o1 o2 o3 o4 <<<"$ip"

    # Validar rango 0-255
    for octeto in "$o1" "$o2" "$o3" "$o4"; do
        if ((octeto < 0 || octeto > 255)); then
            return 1
        fi
    done

    return 0
}
ipToint() {
    local IFS=.
    read -r a b c d <<<"$1"
    echo $(((a << 24) + (b << 16) + (c << 8) + d))
}

isInt() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

isSameSegment() {
    ip1=$(ipToint "$1")
    ip2=$(ipToint "$2")
    mask=$(ipToint "$3")
    if (((ip1 & mask) == (ip2 & mask))); then
        return 0
    else
        return 1
    fi
}
isInt() {
    [[ "$1" =~ ^[0-9]+$ ]]
}
