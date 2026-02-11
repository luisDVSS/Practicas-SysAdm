#!/bin/bash
. validip.sh
. conf_red.sh
. monitor.sh
. valid_segm.sh


#validacion para ver si dhcp ya esta instalado
valid_inst() {
 if dpkg -s isc-dhcp-server &>/dev/null; then
	 return 0
 else
	 return 1
 fi
}
#funcion para validar la existencia de una interfaz
valid_interfaz() {
local iface="$1"
 if ip link show "$iface" &>/dev/null; then
	 return 0
 else
	 return 1
 fi

}
valid_conf_ya(){
 systemctl is-active --quiet isc-dhcp-server || return 1
 return 0
}
intToip() {
 local ip=$1
 echo "$(( (ip>>24)&255 )).$(( (ip>>16)&255 )).$(( (ip>>8)&255 )).$(( ip&255 ))"
}
conf_ipsv() {
 ip_int=$(ipToint "$1") || exit 1
 ip_mas=$(intToip $((ip_int + 1)))
 local prefis=$3
 config_redsv $2 $ip_mas $prefis
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
    IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
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
    local mask=$(( 0xFFFFFFFF << (32 - prefijo) & 0xFFFFFFFF ))

    #Calcular network real
    local network=$(( ip_int & mask ))

    #Verificar que la IP sea exactamente la network
    if (( ip_int == network )); then
        return 0
    else
        return 1
    fi
}

prefijo_a_mascara() {
    local prefijo=$1
    local mask=$(( 0xFFFFFFFF << (32 - prefijo) & 0xFFFFFFFF ))
    intToip $mask
}
config_dhcp() {
#validacion de INTERFAZ 
while :; do
	read -p "Ingresa la interfaz de red: " interfaz
	if ! valid_interfaz $interfaz; then
		echo "[AVISO]Interfaz no existente, termina la configuracion de virtual box y vuelve :D"
		exit 1
	fi
	break
done


#Validacion Ip	NETWORK
while :; do
	read -p "IP de la network: " network
	if validar_formato_ip "$network"; then
    echo "Formato IP válido..."

    while :; do
        read -p "Ingresa prefijo de la red: " prefijo

        if ! [[ $prefijo =~ ^[0-9]+$ ]] || (( prefijo < 1 || prefijo > 30 )); then
            echo "El prefijo tiene que ser de 1-30"
        else
            break
        fi
    done

    echo "Validando que sea una IP de red real..."

    if validar_ip_network "$network" "$prefijo"; then
        echo "IP de red válida"
        echo "Configurando la IP del servidor..."
        conf_ipsv "$network" "$interfaz" "$prefijo"
        break
    else
        echo "La IP no corresponde a una network válida"
    fi
else
    echo "[AVISO] Formato IP inválido"
fi
done
mascara=$(prefijo_a_mascara "$prefijo")
#ingreso de rango y validacion de coherencia y sintaxis
while :; do
	while :; do
		echo "[RANGO]Ingresa IP minima: "
		read ip_min
		if valid_ip "$ip_min"; then
			echo "IP VALIDA..."
			break
		else
			echo "[AVISO] IP Invalida, ingresa una nueva"

		fi
	done
	while :; do
		echo "[RANGO]Ingresa IP Maxima: "
		read ip_max
		if valid_ip "$ip_max"; then
			echo "IP VALIDA..."
			break
		else
			echo "[AVISO] IP Invalida, ingresa una nueva"

		fi
	done
 echo "Validando que la ip max sea mayor a ip min..."
 if (( $(ipToint "$ip_max") > $(ipToint "$ip_min") )); then
	echo "Ip maxima e Ip Minima coherentes..."
	echo "validando que network y la ip de la vm esten fuera de rango... "
	if (( $(ipToint "$ip_mas") >$(ipToint "$ip_min") && $(ipToint "$ip_mas") <$(ipToint "$ip_max") )); then
		echo "ips: network= $network--- servidor=$ip_mas"
		echo "[AVISO] La Ip del network y del servidor no pueden estar dentro del rango del servicio"
	else
		echo "IP de network y servidor fuera del rango del servicio: CORRECTO"
		echo "Validando segmentacion coherente.."

	       	if mismo_segmentos $ip_min $ip_mas $mascara; then 
			echo "El rango si esta dentro del segmento"
		       	break
	       	else
			echo "El rango no esta dentro del segmento de red correcto"
		fi
	fi
 else
	 echo "[AVISO] La ip maxima tiene que ser mayor a la ip minima"
 fi

done
#validacion DNS---------
while :; do
read -p "IP del servidor DNS: " ip_dns
 if [ -z "$ip_dns" ]; then
 echo "Haz dejado el dns vacio"
	break
 else
 	if valid_ip "$ip_dns"; then
	 	echo "IP del dns Valida..."
	 	break
	 else
	 	echo "[AVISO] IP Invalida"
 	fi
 fi
 
done
#Validacion Gateway
while :; do
	read -p "IP de la puerta de enlace; " puerta
	if [ -z "$puerta" ]; then
	echo "has dejado la puerta de enlace vacia, procediendo"
	break
	else
	if valid_ip "$puerta"; then
		echo "IP de la puerta de enlace valida..."
		echo "validando que este en el segmento de red correcto.."
		if mismo_segmentos "$puerta" "$network" "$mascara"; then 
			echo "La puerta si esta dentro del segmento"
		       	break
	       	else
			echo "La puerta de enlace no esta dentro del segmento de red correcto"
		fi
	
	else
		echo "[AVISO] IP Invalida"
	fi
	fi
	
done
#INPUTS DE LOS TIME LEASES
while :; do
	while :; do
		read -p "Tiempo DEFAULT de lease en segundos: " min_horas
		if ! isInt "$min_horas"; then
			echo "[AVISO] Ingresa un valor numerico entero !"
		else
			break

		fi
	done
	
	echo "Validando coherencia de lease time.."
	
		if (( min_horas > 0 )); then
		echo "tiempo de consecion valido"
			break
		else
			echo "[AVISO] El tiempo de consesion tiene que ser mayor a 0"
		fi
	

done
#Configuracion del archivo de intefaces
echo "Configurando la interfaz del DHCP..."
sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$interfaz\"/" /etc/default/isc-dhcp-server
echo "Generando archivo de configuracion del DHCP...."
#configuracion del dhcp
cat > /etc/dhcp/dhcpd.conf <<EOF
default-lease-time $min_horas;
authoritative;
subnet $network netmask $mascara {
range $ip_min $ip_max;
EOF
# Agregar router solo si existe
if [ -n "$puerta" ]; then
    echo "option routers $puerta;" >> /etc/dhcp/dhcpd.conf
fi

# Agregar DNS solo si existe
if [ -n "$ip_dns" ]; then
    echo "option domain-name-servers $ip_dns;" >> /etc/dhcp/dhcpd.conf
fi
# Cerrar bloque
echo "}" >> /etc/dhcp/dhcpd.conf



dhcp_status
}
#INSTALACION DHCP
instal_dhcp() {
	echo "Instalando isc-dhcp-serer..."
	apt update -y >/dev/null 2>&1
	apt install -y isc-dhcp-server >/dev/null 2>&1 || {
	       	echo "[ERROR] No se pudo instalar isc-dhcp-server"; 
		echo "[AVISO] Comprueba tu conexion a internet";
	       	return 1
	}
	return 0
}
#MAIN PROGRAM ----------------------------------------------
while :; do
echo "==========MENU->> ACCIONES A REALIZAR=========="
echo "SELECCIONA ACCION A REALIZAR"
echo "1) Instalar DHCP y configurarlo"
echo "2) Ingresar a modulo de MONITOREO"
echo "3) Salir"
read selected
case $selected in
	1)
		echo "1"
		if valid_inst; then
			echo "[AVISO] Ya cuentas con la instalacion de-> 'isc-dhcp-server'"
			echo "validando si ya hay una configuracion de dhcp-server..."
			if valid_conf_ya; then
				read -p "[AVISO] Ya cuentas con con una configuracion de isc-dhcp-server, deseas SOBRE-ESCRIBIRLA? [s/n]" sobrescribir
				case $sobrescribir in
					s)
						echo "Procediendo con la la configuracion de DHCP..."
						config_dhcp
						;;
					n)
						echo "Saliendo del script..."
						exit 0
						;;
					*)
						echo "Caracter errado, saliendo del script..."
						exit 1
						;;
				esac
			else
				echo "No cuentas con ninguna configuracion previa"
				read -p "Desesas proceder a la configuracion? [s/n]" configurar
				case $configurar in
					s)

						echo "Procediendo con la configuracion de DHCP"
						config_dhcp
						;;
					n)
						echo "Abortando..."
						exit 0
						;;
					*)
						echo "Opcion invalida, abortando..."
						exit 1
						;;
				esac
			fi
		else
              		echo "No cuentas con la previa instalacion de isc-dhcp-server"
			echo "Procediendo a la instalacion..."
			if ! instal_dhcp; then
				echo "[ERROR] INSTALACION FALLIDA"
				echo "saliendo...."
				exit 1
			fi
			echo "Instalacion exitosa"
			read -p "Deseas proceder con el proceso de configuracion? [s/n]" seguir_conf
			case $seguir_conf in
				s)
					echo "Configurando...."
					config_dhcp
					;;
				n)
					echo "Saliendo del script..."
					exit 0
					;;
				*)
					echo "Opcion invalida, aboratando..."
					exit 1
					;;
			esac
		fi
		;;
	2)
		echo "2"
		monitorear
		;;
	3)
		echo "Hasta luego"
		break
		;;
	*)
		echo "Opcion Invalida"
		;;
esac
done