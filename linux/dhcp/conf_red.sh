#!/bin/bash
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
archivo="/etc/netplan/99-${interfaz}-estatica.yaml"
echo "Configurando interfaz: $interfaz..."
sudo tee "$archivo" > /dev/null <<EOF
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
