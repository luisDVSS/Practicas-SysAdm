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
 
 config_redsv $2 $ip_mas 24
}
dhcp_status() {
systemctl restart isc-dhcp-server
systemctl enable isc-dhcp-server
echo "DHCP server configurado y activo"

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
	if valid_ip $network; then
		echo "IP de network valida..."
		echo "Configurando la ip del servidor..."
		break
	else
		echo "[AVISO] IP Invaida, ingresa una nueva"
	fi
	
done
#CONFIGURACION DE RED
 conf_ipsv $network $interfaz
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

	       	if mismo_segmentos $ip_min $ip_mas $mas 255.255.255.0; then 
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
 if valid_ip "$ip_dns"; then
	 echo "IP del dns Valida..."
	 break
 else
	 echo "[AVISO] IP Invalida"
 fi
done
#Validacion Gateway
while :; do
	read -p "IP de la puerta de enlace; " puerta
	if valid_ip $puerta; then
		echo "IP de la puerta de enlace valida..."
		break
	else
		echo "[AVISO] IP Invalida"
	fi
done
#INPUTS DE LOS TIME LEASES
while :; do
	while :; do
		read -p "Tiempo DEFAULT de lease en horas" min_horas
		if ! isInt "$min_horas"; then
			echo "[AVISO] Ingresa un valor numerico entero !"
		else
			break

		fi
	done
	while :; do
		read -p "Tiempo Maximo de lease en horas" max_horas
		if ! isInt "$max_horas"; then
			echo "[AVISO] Ingresa un valor numerico entero !"
		else
			break
		fi
	done
	echo "Validando coherencia de lease time.."
	if (( max_horas < min_horas )); then
		echo "[AVISO] Las horas default no pueden ser mayor a las horas maximas"
	        
	else
		if ( min_horas>0 ); then
			max_horas=$(( max_horas * 3600 ))
			min_horas=$(( min_horas * 3600 ))
			break
		else
			echo "[AVISO] El tiempo de consesion tiene que ser mayor a 0"
		fi
	fi

done
#Configuracion del archivo de intefaces
echo "Configurando la interfaz del DHCP..."
sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$interfaz\"/" /etc/default/isc-dhcp-server
echo "Generando archivo de configuracion del DHCP...."
cat > /etc/dhcp/dhcpd.conf <<EOF
default-lease-time $min_horas;
max-lease-time $max_horas;
authoritative;
subnet $network netmask 255.255.255.0 {
range $ip_min $ip_max;
option routers $puerta;
option domain-name-servers $ip_dns;
}
EOF
dhcp_status
}
#INSTALACION DHCP
instal_dhcp() {
	echo "Instalando isc-dhcp-serer..."
	apt install  >/dev/null 2>&1 
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
				echo "No cuentas con isc-dhcp-server. Procediendo con la instalacion..."
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

