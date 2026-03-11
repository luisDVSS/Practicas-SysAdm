#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "[ERROR] Ejecuta este script como root o con sudo."
    exit 1
fi
set_puerto_tomcat() {
    local puerto=$1
    local conf

    # Buscar server.xml dinamicamente
    conf=$(find /etc/tomcat* /opt/tomcat* -name "server.xml" 2>/dev/null | head -1)

    if [ -z "$conf" ]; then
        echo "[ERROR] No se encontro server.xml de Tomcat."
        return 1
    fi

    sed -i "s/port=\"[0-9]*\" protocol=\"HTTP/port=\"$puerto\" protocol=\"HTTP/" "$conf"
    echo "[OK] Puerto de Tomcat cambiado a $puerto en $conf."

    # Detectar nombre del servicio tomcat instalado
    local svc
    svc=$(systemctl list-units --type=service | grep -i tomcat | awk '{print $1}' | head -1)
    if [ -n "$svc" ]; then
        systemctl restart "$svc"
        echo "[OK] Tomcat reiniciado."
    else
        echo "[ADVERTENCIA] No se encontro el servicio tomcat. Reinicia manualmente."
    fi
}
get_versiones() {
    local paquete=$1
    # Devolver version completa como apt la conoce
    apt-cache madison "$paquete" 2>/dev/null | awk '{print $3}' | head -8
}

select_version() {
    local etiqueta=$1
    shift
    local versiones=("$@")
    local total=${#versiones[@]}

    if [ $total -eq 0 ]; then
        echo "[ERROR] No se encontraron versiones de $etiqueta."
        return 1
    fi

    local lts_idx=$((total / 2))

    echo ""
    echo "  Versiones disponibles de $etiqueta:"
    for ((i = 0; i < total; i++)); do
        local label=""
        if [ $i -eq 0 ]; then
            label="  (Latest)"
        elif [ $i -eq $lts_idx ] && [ $total -ge 3 ]; then
            label="  (LTS / Estable)"
        elif [ $i -eq $((total - 1)) ]; then
            label="  (Oldest)"
        fi
        echo "  $((i + 1))) ${versiones[$i]}$label"
    done

    while true; do
        read -rp "
  ¿Cual version deseas instalar? [1-$total]: " eleccion
        if [[ "$eleccion" =~ ^[0-9]+$ ]] && [ "$eleccion" -ge 1 ] && [ "$eleccion" -le $total ]; then
            VERSION_ELEGIDA="${versiones[$((eleccion - 1))]}"
            return 0
        fi
        echo "  Opcion invalida."
    done
}

read_puerto() {
    local default=$1

    while true; do
        read -rp "  ¿En que puerto deseas configurar el servicio? [default: $default]: " puerto
        puerto="${puerto:-$default}"

        if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
            echo "  Solo se permiten numeros."
            continue
        fi

        if [ "$puerto" -lt 1 ] || [ "$puerto" -gt 65535 ]; then
            echo "  Puerto fuera de rango (1-65535)."
            continue
        fi

        local reservados=(21 22 25 53 110 143 3306 5432 6379 27017 3389 445 139)
        local reservado=false
        for r in "${reservados[@]}"; do
            if [ "$puerto" -eq "$r" ]; then
                echo "  El puerto $puerto esta reservado para otro servicio."
                reservado=true
                break
            fi
        done
        [ "$reservado" = true ] && continue

        if [ "$puerto" -lt 1024 ]; then
            echo "  [ADVERTENCIA] El puerto $puerto es privilegiado (<1024)."
        fi

        PUERTO_ELEGIDO=$puerto
        return 0
    done
}

new_index_html() {
    local servicio=$1
    local version=$2
    local puerto=$3
    local webroot

    case "$servicio" in
    apache2) webroot="/var/www/html" ;;
    nginx) webroot="/var/www/html" ;;
    tomcat*) webroot="/var/lib/${servicio}/webapps/ROOT" ;;
    *) webroot="/var/www/html" ;;
    esac

    mkdir -p "$webroot"

    cat >"$webroot/index.html" <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$servicio</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: #f0f2f5;
        }
        .card {
            background: white;
            border-radius: 8px;
            padding: 40px 60px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.1);
            text-align: center;
        }
        h1 { color: #333; margin-bottom: 24px; }
        table { border-collapse: collapse; width: 100%; }
        td { padding: 10px 20px; text-align: left; }
        td:first-child { font-weight: bold; color: #555; }
        tr:nth-child(even) { background: #f9f9f9; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Servidor activo</h1>
        <table>
            <tr><td>Servicio</td><td>$servicio</td></tr>
            <tr><td>Version</td><td>$version</td></tr>
            <tr><td>Puerto</td><td>$puerto</td></tr>
        </table>
    </div>
</body>
</html>
EOF

    echo "[OK] index.html generado en: $webroot/index.html"
}

set_puerto_apache2() {
    local puerto=$1
    local conf="/etc/apache2/ports.conf"

    sed -i "s/Listen [0-9]*/Listen $puerto/" "$conf"
    sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:$puerto>/" /etc/apache2/sites-enabled/*.conf 2>/dev/null
    echo "[OK] Puerto de Apache2 cambiado a $puerto."
    systemctl restart apache2
    echo "[OK] Apache2 reiniciado."
}

set_puerto_nginx() {
    local puerto=$1
    local conf="/etc/nginx/sites-enabled/default"

    sed -i "s/listen [0-9]* /listen $puerto /" "$conf"
    sed -i "s/listen \[::\]:[0-9]*/listen [::]:$puerto/" "$conf"
    echo "[OK] Puerto de Nginx cambiado a $puerto."
    systemctl restart nginx
    echo "[OK] Nginx reiniciado."
}

install_servicio() {
    local servicio=$1
    local version=$2
    local puerto=$3

    echo ""
    echo "======================================================"
    echo "  Instalando $servicio $version en puerto $puerto"
    echo "======================================================"

    apt-get update

    case "$servicio" in
    apache2)
        # Instalar con version exacta, si falla instalar la disponible
        if ! apt-get install -y "apache2=$version" 2>/dev/null; then
            echo "[ADVERTENCIA] Version $version no disponible, instalando version actual..."
            apt-get install -y apache2
        fi
        systemctl enable apache2
        systemctl start apache2
        set_puerto_apache2 "$puerto"
        ;;
    nginx)
        if ! apt-get install -y "nginx=$version" 2>/dev/null; then
            echo "[ADVERTENCIA] Version $version no disponible, instalando version actual..."
            apt-get install -y nginx
        fi
        systemctl enable nginx
        systemctl start nginx
        set_puerto_nginx "$puerto"
        ;;
    tomcat*)
        if ! apt-get install -y "$servicio=$version" 2>/dev/null; then
            echo "[ADVERTENCIA] Version $version no disponible, instalando version actual..."
            apt-get install -y "$servicio"
        fi

        # Detectar nombre del servicio
        local svc
        svc=$(systemctl list-units --type=service | grep -i tomcat | awk '{print $1}' | head -1)
        if [ -n "$svc" ]; then
            systemctl enable "$svc"
            systemctl start "$svc"
        fi

        set_puerto_tomcat "$puerto"
        ;;
    esac

    echo ""
    # Obtener version real instalada
    local version_real
    version_real=$(dpkg -l "$servicio" 2>/dev/null | awk '/^ii/{print $3}')

    echo "[OK] $servicio instalado correctamente. Version real: $version_real"
    new_index_html "$servicio" "$version_real" "$puerto"
}
echo ""
echo "======================================================"
echo "   Instalador de servidor HTTP para Ubuntu 24.04"
echo "======================================================"
echo "  1) Apache2"
echo "  2) Nginx"
echo "  3) Tomcat"
echo "  0) Salir"
echo ""

while true; do
    read -rp "  Selecciona el servidor a instalar: " opc
    [[ "$opc" =~ ^[0-3]$ ]] && break
    echo "  Opcion invalida."
done

case "$opc" in
0)
    echo "  Saliendo."
    exit 0
    ;;
1)
    mapfile -t versiones < <(get_versiones "apache2")
    select_version "Apache2" "${versiones[@]}"
    read_puerto 80
    install_servicio "apache2" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
    ;;
2)
    mapfile -t versiones < <(get_versiones "nginx")
    select_version "Nginx" "${versiones[@]}"
    read_puerto 80
    install_servicio "nginx" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
    ;;
3)
    # Buscar paquetes tomcat disponibles
    mapfile -t pkgs < <(apt-cache search "^tomcat" | awk '{print $1}' | grep "^tomcat[0-9]" | sort -rV)

    if [ ${#pkgs[@]} -eq 0 ]; then
        echo "[ERROR] No se encontraron paquetes de Tomcat."
        exit 1
    fi

    echo ""
    echo "  Paquetes de Tomcat disponibles:"
    for ((i = 0; i < ${#pkgs[@]}; i++)); do
        echo "  $((i + 1))) ${pkgs[$i]}"
    done

    while true; do
        read -rp "
  ¿Cual paquete deseas instalar? [1-${#pkgs[@]}]: " eleccion
        if [[ "$eleccion" =~ ^[0-9]+$ ]] && [ "$eleccion" -ge 1 ] && [ "$eleccion" -le ${#pkgs[@]} ]; then
            PKG_TOMCAT="${pkgs[$((eleccion - 1))]}"
            break
        fi
        echo "  Opcion invalida."
    done

    mapfile -t versiones < <(get_versiones "$PKG_TOMCAT")
    select_version "Tomcat ($PKG_TOMCAT)" "${versiones[@]}"
    read_puerto 8080
    install_servicio "$PKG_TOMCAT" "$VERSION_ELEGIDA" "$PUERTO_ELEGIDO"
    ;;
esac
