#!/bin/bash
. Funciones.sh
setConfigDns() {
    echo "Configurando dns.."
    while :; do
        read -pr"Ingresa el nombre del dominio" dominio
        if ! isDomName "$dominio"; then
            echo "nombre de dominio no valido"
            continue
        fi

        if grep -qi "zone \"$dominio\"" /etc/bind/named.conf.local; then
            echo "Este dominio ya esta agregado"
            continue
        else
            break
        fi
    done
    while :; do
        read -pr "Ingresa la ip" ip_add
        if isHostIp "$ip_add"; then
            echo "IP Correcta"
            break
        else
            echo "Ingresa ip valida"
        fi
    done

    cat <<EOF >>/etc/bind/named.conf.local
zone "$dominio" {
    type master;
    file "/etc/bind/db.$dominio";
};
EOF
    dominio_inverso=getZonaInversa $ip

    cat <<EOF >>/etc/bind/named.conf.local
zone "$dominio_inverso.in-addr.arpa" {
    type master;
    file "/etc/bind/db.$dominio_inverso";
};
EOF

}
