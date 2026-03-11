#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../lib_func.sh"
source "$SCRIPT_DIR/http_funciones.sh"

echo "HTTP SERVICE"
echo "-------------------"
echo "1) Ver estado de instalacion de HTTP"
echo "2) Instalar un servicio HTTP"
echo "3) Cambiar puerto de un servicio HTTP"

read -p "Selecciona una opcion: " opc
case "$opc" in
1)
  echo "Estado de servicios HTTP:"
  for svc in apache2 nginx tomcat9 tomcat10 tomcat11; do
    if dpkg -s "$svc" &>/dev/null; then
      status=$(systemctl is-active "$svc" 2>/dev/null || echo "desconocido")
      echo "  [$status] $svc"
    fi
  done
  ;;
2) GetVersionesHTTP ;;
3) cambiarPuertoMenu ;;
*) echo "Opcion invalida" ;;
esac
