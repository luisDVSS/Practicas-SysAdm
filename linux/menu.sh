#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib_func.sh"

echo "<----------------MENU---------------->"
echo ""
while :; do
    echo "1) DHCP"
    echo "2) DNS"
    echo "3) SSH"
    read -r opc
    case "$opc" in
    1)
        sudo "$SCRIPT_DIR/dhcp/main.sh"
        ;;
    2)
        sudo "$SCRIPT_DIR/dns/main.sh"
        ;;
    3)
        sudo "$SCRIPT_DIR/ssh/main.sh"
        ;;
    esac

done
