#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/Funciones.sh"
source "$SCRIPT_DIR/config_dns.sh"
source "$SCRIPT_DIR/../lib_func.sh"
askDhcp() {
    read -r -p "¿Configurar o entrar al modulo de DHCP?[s/n]" cont
    case $cont in
    s)
        echo "Continuando con la configuracion..."
        source "$SCRIPT_DIR/../dhcp/main.sh"
        ;;
    n)
        echo "saliendo del script.."
        exit 0
        ;;

    esac
}
askConf() {
    # shellcheck disable=SC2313
    read -r -p "¿Deses crearun dominio? [s/n]" cont
    case $cont in
    s)
        echo "Continuando con la configuracion..."
        setConfigDns
        ;;
    n)
        echo "saliendo del script.."
        exit 0
        ;;

    esac
}
while :; do
    echo "Selecciona una opcion"
    echo "1) Ver si Bind9 esta intalado"
    echo "2) Instalar Bind9"
    echo "3) Eliminar un dominio"
    echo "4) Agregar dominios"
    echo "5) Dominios registrados"
    echo "6) Salir"
    read -r opc
    case "$opc" in
    1)
        if isInstalled bind9 bind9utils bind9-doc; then
            echo "Los servicios de DNS service YA estan intalados."
        else
            echo "Los servicios de DNS NO estan instalado."
        fi

        ;;
    2)
        echo "Validando la instalacion de bind9..."
        if isInstalled bind9 bind9-doc bind9utils; then
            echo "Los servicios de DNS ya estan instalados"
            #askDhcp
            continue
        else
            echo "Procediendo con la instalacion de bind9.."
            getService bind9 bind9-doc bind9utils
            echo "servicios instalados correctamente"
            #askDhcp
            continue
        fi
        ;;
    3)
        if isInstalled bind9 bind9-doc bind9utils; then
            deleteDomain
        else
            echo "Los servicios no estan instalados.."
            continue
        fi
        ;;
    4)
        askConf
        ;;
    5)
        getDomains
        ;;
    6)
        echo "Saliendo.."
        break

        ;;
    *)
        echo "Opcion invalida"
        continue
        ;;

    esac
done
