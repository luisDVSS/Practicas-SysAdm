#!/bin/bash
getService() {
    apt install -y "$@" &>/dev/null
}

getDomains() {
    local conf="/etc/bind/named.conf.local"

    printf "%-30s %-15s\n" "DOMINIO" "IP"
    printf "%-30s %-15s\n" "------------------------------" "---------------"

    awk '
    BEGIN { FS="\"" }

    /^[[:space:]]*zone[[:space:]]+"/ {
        zone=$2
        if (zone !~ /arpa/) {
            inzone=1
        } else {
            inzone=0
        }
    }

    inzone && /file/ {
        file=$2
        gsub(";", "", file)

        cmd = "awk '\''/\\sA\\s/ {print $NF; exit}'\'' " file
        cmd | getline ip
        close(cmd)

        if (ip != "")
            printf "%-30s %-15s\n", zone, ip
    }

    ' "$conf"
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
#validacion debil
#validacion de formato y
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
isDomName() {
    #regex validacion de nombre de dominio
    # Solo acepta formato: nombre.com (solo letras)
    local regex='^[a-zA-Z]+\.com$'
    local nombre=$1

    if [[ $nombre =~ $regex ]]; then
        return 0
    else
        return 1
    fi

}
# local regex='^(www\.)?([a-zA-Z0-9](-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,}$'
#  local nombre=$1
#   if [[ ! $nombre =~ $regex ]]; then
#     return 1
#  else
#       return 0
#
#    fi
isInstalled() {
    # shellcheck disable=SC2086
    if dpkg -s "$@" &>/dev/null; then
        return 0
    else
        return 1
    fi
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
prefijo_a_mascara() {
    local prefijo=$1
    local bits=$((32 - prefijo))
    # shellcheck disable=SC2323
    local mask=$((((0xFFFFFFFF << bits) & 0xFFFFFFFF)))
    intToip $mask
}
getZonaInversa() {
    local ip="$1"

    # Validar formato básico de IP
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    IFS='.' read -r o1 o2 o3 o4 <<<"$ip"

    # Validar rango 0-255
    for octeto in $o1 $o2 $o3 $o4; do
        if ((octeto < 0 || octeto > 255)); then
            return 1
        fi
    done

    # Retornar zona inversa tipo /24
    echo "$o3.$o2.$o1"
    #echo "$o3.$o2.$o1.in-addr.arpa" antigua linea
}

ipToInt() {
    local IFS=.
    read -r a b c d <<<"$1"
    # shellcheck disable=SC2323
    echo $((((a << 24) | (b << 16) | (c << 8) | d)))
}
resetBind() {
    systemctl restart bind9
}
getOcteto() {
    local ip="$1"
    local num="$2"

    # Validar numero de octeto
    if ! [[ "$num" =~ ^[1-4]$ ]]; then
        return 1
    fi

    # Validar formato básico IP
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        return 1
    fi

    IFS='.' read -r o1 o2 o3 o4 <<<"$ip"

    # Validar rango 0-255
    for octeto in $o1 $o2 $o3 $o4; do
        if ((octeto < 0 || octeto > 255)); then
            return 1
        fi
    done
    case "$num" in
    1) echo "$o1" ;;
    2) echo "$o2" ;;
    3) echo "$o3" ;;
    4) echo "$o4" ;;
    esac
}
getIpDomain() {
    local dominio="$1"
    grep -E "^[[:space:]]*@.*IN[[:space:]]+A" /etc/bind/db.$dominio | awk '{print $NF}'
}

domainExists() {
    local dominio="$1"
    grep -qi "zone \"$dominio\"" /etc/bind/named.conf.local
}
domainInvExists() {
    local dominio_inverso="$1"
    grep -qi "zone \"$dominio_inverso.in-addr.arpa\"" /etc/bind/named.conf.local
}
zonaInversaTieneMasPtr() {
    local archivo="$1"
    local cantidad
    cantidad=$(grep -c "IN[[:space:]]\+PTR" "$archivo")
    if [ "$cantidad" -gt 1 ]; then
        return 0
    else
        return 1
    fi

}
deleteDomain() {
    read -p "Dominio a eliminar" dominio
    if ! domainExists "$dominio"; then
        echo "El dominio no existe"
        return 1
    fi

    ip_add=$(getIpDomain "$dominio")

    if [ -z "$ip_add" ]; then
        echo "No se pudo obtener la IP del dominio"
        return 1
    fi
    dominio_inverso=$(getZonaInversa "$ip_add")
    archivo_inverso="/etc/bind/db.$dominio_inverso"
    ultimo_octeto=$(getOcteto "$ip_add" 4)
    sed -i "/zone \"$dominio\" {/,/};/d" /etc/bind/named.conf.local
    rm -f /etc/bind/db."$dominio"
    if [ -f "$archivo_inverso" ]; then

        total_ptr=$(grep -c "IN[[:space:]]\+PTR" "$archivo_inverso")

        if [ "$total_ptr" -gt 1 ]; then
            # Solo borrar el PTR
            sed -i "/^[[:space:]]*${ultimo_octeto}[[:space:]]\+IN[[:space:]]\+PTR/d" "$archivo_inverso"
        else
            # Era el ultimo PTR → borrar zona completa
            sed -i "/zone \"$dominio_inverso.in-addr.arpa\" {/,/};/d" /etc/bind/named.conf.local
            rm -f "$archivo_inverso"
        fi
    fi

    echo "Dominio eliminado correctamente"
    resetBind

}
