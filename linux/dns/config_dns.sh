#!/bin/bash
. Funciones.sh
setConfigDns() {
    echo "Configurando dns.."
    while :; do
        #validacion si el nombre del dominio es valido
        read -p "Ingresa el nombre del dominio: " dominio
        if ! isDomName "$dominio"; then
            echo "nombre de dominio no valido"
            continue
        fi
        #validacion si el dominio existe en la configuracion de los named
        #puede haber "n" numeros de dominios pero no pueden ser los mismo
        if grep -qi "zone \"$dominio\"" /etc/bind/named.conf.local; then
            echo "Este dominio ya esta agregado"
            continue
        else
            break
        fi
    done

    #validacion de la ip
    while :; do
        read -p "Ingresa la ip: " ip_add

        if ! isHostIp "$ip_add"; then
            echo "Ip no valida"
            continue
        fi

        dominio_inverso="$(getZonaInversa "$ip_add")"
        archivo_inverso="/etc/bind/db.$dominio_inverso"
        ultimo_octeto="$(getOcteto "$ip_add" 4)"

        # Validar si ya existe ese PTR
        if [ -f "$archivo_inverso" ]; then
            if grep -qE "^${ultimo_octeto}[[:space:]]+IN[[:space:]]+PTR" "$archivo_inverso"; then
                echo "Esta IP ya esta registrada"
                continue
            fi
        fi

        break
    done
    setConf_files "$dominio" "$ip_add" "$dominio_inverso"
    resetBind
}

setConf_files() {
    local dominio="$1"
    local ip_add="$2"
    local dominio_inverso="$3"
    local archivo_inverso="/etc/bind/db.$dominio_inverso"
    local ultimo_octeto
    ultimo_octeto="$(getOcteto "$ip_add" 4)"
    #Adicion de las dos zonnas de una, inversa y nombre de dom
    if ! domainExists "$dominio"; then
        cat <<EOF >>/etc/bind/named.conf.local
zone "$dominio" {
    type master;
    file "/etc/bind/db.$dominio";
};
EOF
    fi

    if ! domainInvExists "$dominio_inverso"; then
        cat <<EOF >>/etc/bind/named.conf.local
zone "$dominio_inverso.in-addr.arpa" {
    type master;
    file "/etc/bind/db.$dominio_inverso";
};
EOF
    fi
    #Registro de dominio
    cat <<EOF >/etc/bind/db."$dominio"
\$TTL 604800
@   IN  SOA ns1.$dominio. admin.$dominio. (
        2         ; Serial
        604800    ; Refresh
        86400     ; Retry
        2419200   ; Expire
        604800 )  ; Negative Cache TTL

@       IN  NS  ns1.$dominio.
@       IN  A   $ip_add
ns1     IN  A   $ip_add
www     IN  A   $ip_add
EOF
    if [ ! -f "$archivo_inverso" ]; then
        #Registro de dominio inverso
        cat <<EOF >/etc/bind/db."$dominio_inverso"
\$TTL 604800
@   IN  SOA ns1.$dominio. admin.$dominio. (
        2         ; Serial
        604800    ; Refresh
        86400     ; Retry
        2419200   ; Expire
        604800 )  ; Negative Cache TTL

@       IN  NS  ns1.$dominio.
$ultimo_octeto     IN  PTR   ns1.$dominio.
EOF
    else
        echo "$ultimo_octeto     IN  PTR   ns1.$dominio." >>"$archivo_inverso"
    fi

}
