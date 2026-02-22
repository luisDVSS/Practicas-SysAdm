#!/bin/bash
monitorear() {
	while :; do
		clear
		echo "Selecciona accion"
		echo "========================"
		echo
		echo "1) Ver estado del servicio DHCP"
		echo
		echo "2) Ver Conexiones activas"
		echo
		echo "3) Salir"

		read opc
		case "$opc" in
		1)
			echo
			echo "ESTADO DEL SERVIDOR"
			echo "----------------------"
			echo
			systemctl status isc-dhcp-server
			read -p "Presiona ENTER para volver al menu"
			;;
		2)
			echo
			echo "Conseciones DHCP activas:"
			echo "--------------------------"
			echo
			if [ -f /var/lib/dhcp/dhcpd.leases ]; then
				awk '
			/^lease / {
		       	ip=$2 
			mac=""
			host=""
			active=0
		        }
			/binding state active/ {
		        active=1
		        }
			/hardware ethernet/ {
		        mac=$3
			gsub(";", "", mac)
		        }
			/client-hostname/ {
		        host=$2
			gsub(/[";]/, "", host)
	            	}
			/^}/ {
	           	if (mac != "" && host != "") {
				data[ip] = sprintf("IP: %-15s MAC: %-18s HOST: %s", ip, mac,host)
			    }
		        }
			END {
			for (ip in data)
				print data[ip]
		        }' /var/lib/dhcp/dhcpd.leases
				echo
				echo
				read -p "Presiona ENTER para volver al menu"
			fi
			;;

		3)
			echo
			echo "Saliendo.."
			exit 0

			;;
		*)
			echo
			echo "OPCION INVALIDA"
			echo
			;;

		esac

	done

}
