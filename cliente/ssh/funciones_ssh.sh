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
