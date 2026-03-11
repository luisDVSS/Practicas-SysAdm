#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib_func.sh"

# ══════════════════════════════════════════════════════════════════════════════
# HELPERS DE SELECCIÓN E INSTALACIÓN
# ══════════════════════════════════════════════════════════════════════════════

_seleccionar_version() {
    local paquete="$1"
    mapfile -t versiones < <(apt-cache madison "$paquete" | awk '{print $3}')
    local total=${#versiones[@]}
    if [[ $total -eq 0 ]]; then
        echo "No se encontraron versiones disponibles para '$paquete'." >&2
        return 1
    fi
    local lts_idx=$((total / 2))
    for ((i = 0; i < total; i++)); do
        local label=""
        if [[ $i -eq 0 ]]; then
            label=" (Latest)"
        elif [[ $i -eq $lts_idx && $total -ge 3 ]]; then
            label=" (LTS)"
        elif [[ $i -eq $((total - 1)) && $total -ge 2 ]]; then
            label=" (Oldest)"
        fi
        printf "%d) %s%s\n" $((i + 1)) "${versiones[$i]}" "$label"
    done
    local eleccion
    while true; do
        read -rp "¿Cuál deseas instalar? [1-${total}]: " eleccion
        if [[ "$eleccion" =~ ^[0-9]+$ ]] && ((eleccion >= 1 && eleccion <= total)); then break; fi
        echo "Opción inválida." >&2
    done
    SELECTED_VERSION="${versiones[$((eleccion - 1))]}"
}

_resolver_tomcat_pkgs() {
    mapfile -t TOMCAT_PKGS < <(
        apt-cache search '^tomcat[0-9]' | awk '{print $1}' |
            grep -E '^tomcat[0-9]+$' | sort -V
    )
    if [[ ${#TOMCAT_PKGS[@]} -eq 0 ]]; then
        echo "No se encontraron paquetes de Tomcat en los repositorios." >&2
        return 1
    fi
}

_seleccionar_tomcat() {
    _resolver_tomcat_pkgs || return 1
    echo "Versiones principales de Tomcat disponibles:"
    for ((i = 0; i < ${#TOMCAT_PKGS[@]}; i++)); do
        local pkg="${TOMCAT_PKGS[$i]}"
        local ver
        ver=$(apt-cache madison "$pkg" | awk 'NR==1{print $3}')
        printf "%d) %s  →  %s\n" $((i + 1)) "$pkg" "$ver"
    done
    local eleccion
    while true; do
        read -rp "¿Cuál major version deseas? [1-${#TOMCAT_PKGS[@]}]: " eleccion
        if [[ "$eleccion" =~ ^[0-9]+$ ]] && ((eleccion >= 1 && eleccion <= ${#TOMCAT_PKGS[@]})); then break; fi
        echo "Opción inválida." >&2
    done
    local paquete_elegido="${TOMCAT_PKGS[$((eleccion - 1))]}"
    echo ""
    echo "Versiones de ${paquete_elegido^} disponibles:"
    _seleccionar_version "$paquete_elegido" || return 1
    SELECTED_PKG="$paquete_elegido"
}

declare -A _HTTP_CONF_FILE=(
    [apache2]="/etc/apache2/ports.conf"
    [nginx]="/etc/nginx/nginx.conf"
    [tomcat9]="/etc/tomcat9/server.xml"
    [tomcat10]="/etc/tomcat10/server.xml"
    [tomcat11]="/etc/tomcat11/server.xml"
)

_resolver_tomcat_instalado() {
    for v in 9 10 11; do
        if dpkg -s "tomcat${v}" &>/dev/null; then
            echo "tomcat${v}"
            return 0
        fi
    done
    return 1
}

_validar_puerto() {
    local p="$1"
    [[ "$p" =~ ^[0-9]+$ ]] && ((p >= 1 && p <= 65535))
}

# ── Devuelve el directorio web raíz según el servicio ─────────────────────────
_web_root() {
    local servicio="$1"
    case "$servicio" in
    apache2) echo "/var/www/html" ;;
    nginx) echo "/var/www/html" ;;
    tomcat*) echo "/var/lib/${servicio}/webapps/ROOT" ;;
    esac
}

# ── Devuelve el usuario del sistema asociado al servicio ──────────────────────
_service_user() {
    local servicio="$1"
    case "$servicio" in
    apache2) echo "www-data" ;;
    nginx) echo "www-data" ;;
    tomcat*) echo "tomcat" ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
# 1. CREAR PÁGINA INDEX PERSONALIZADA
# ══════════════════════════════════════════════════════════════════════════════
crear_index() {
    local servicio="$1"
    local version="$2"
    local puerto="$3"
    local web_root
    web_root=$(_web_root "$servicio")

    echo ""
    echo "=== Creando index.html personalizado ==="

    mkdir -p "$web_root"

    cat >"${web_root}/index.html" <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Servidor HTTP</title>
    <style>
        body { font-family: Arial, sans-serif; background:#1e1e2e; color:#cdd6f4;
               display:flex; justify-content:center; align-items:center; height:100vh; margin:0; }
        .card { background:#313244; border-radius:12px; padding:40px 60px; text-align:center;
                box-shadow:0 4px 20px rgba(0,0,0,0.4); }
        h1 { color:#89b4fa; margin-bottom:20px; }
        .info { font-size:1.2rem; margin:8px 0; }
        .badge { display:inline-block; background:#45475a; border-radius:6px;
                 padding:4px 12px; margin-top:16px; color:#a6e3a1; font-size:0.9rem; }
    </style>
</head>
<body>
    <div class="card">
        <h1> Servidor HTTP Activo</h1>
        <p class="info"><strong>Servidor:</strong> ${servicio^}</p>
        <p class="info"><strong>Versión:</strong> ${version}</p>
        <p class="info"><strong>Puerto:</strong> ${puerto}</p>
        <span class="badge">:D Instalado y configurado correctamente</span>
    </div>
</body>
</html>
EOF

    local svc_user
    svc_user=$(_service_user "$servicio")
    chown "${svc_user}:${svc_user}" "${web_root}/index.html" 2>/dev/null
    echo "[OK] index.html creado en ${web_root}/index.html"
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. VALIDAR Y CONFIGURAR USUARIO DEDICADO + PERMISOS
# ══════════════════════════════════════════════════════════════════════════════
configurar_usuario_dedicado() {
    local servicio="$1"
    local svc_user
    svc_user=$(_service_user "$servicio")
    local web_root
    web_root=$(_web_root "$servicio")

    echo ""
    echo "=== Validando usuario dedicado y permisos ==="

    # Crear usuario del sistema si no existe
    if id "$svc_user" &>/dev/null; then
        echo "[OK] Usuario '$svc_user' ya existe."
    else
        echo "[INFO] Creando usuario dedicado '$svc_user'..."
        useradd --system --no-create-home --shell /usr/sbin/nologin "$svc_user"
        echo "[OK] Usuario '$svc_user' creado."
    fi

    # Verificar shell deshabilitado
    local shell
    shell=$(getent passwd "$svc_user" | cut -d: -f7)
    if [[ "$shell" == "/usr/sbin/nologin" || "$shell" == "/bin/false" ]]; then
        echo "[OK] Login deshabilitado para '$svc_user' ($shell)."
    else
        echo "[ADVERTENCIA] Shell activo detectado: $shell. Deshabilitando..."
        usermod -s /usr/sbin/nologin "$svc_user"
        echo "[OK] Shell deshabilitado."
    fi

    # Asignar permisos al directorio web
    mkdir -p "$web_root"
    chown -R "${svc_user}:${svc_user}" "$web_root"
    chmod 750 "$web_root"
    echo "[OK] $web_root asignado a '$svc_user' con permisos 750."

    # Bloquear acceso de este usuario a directorios sensibles
    echo "[INFO] Verificando restricciones en directorios sensibles..."
    local dirs_sensibles=("/etc/shadow" "/root" "/boot")
    for d in "${dirs_sensibles[@]}"; do
        if [[ -e "$d" ]]; then
            local otros
            otros=$(stat -c '%A' "$d" | cut -c8-10)
            if [[ "$otros" == "---" ]]; then
                echo "[OK] $d está restringido para 'otros'."
            else
                echo "[ADVERTENCIA] $d tiene permisos para 'otros': $otros"
            fi
        fi
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. OCULTAR BANNER DEL SERVIDOR
# ══════════════════════════════════════════════════════════════════════════════
configure_apache_banner() {
    local SECURITY_CONF="/etc/apache2/conf-available/security.conf"
    echo ""
    echo "=== Ocultando banner: Apache ==="
    if [[ ! -f "$SECURITY_CONF" ]]; then
        echo "[ERROR] No se encontró $SECURITY_CONF"
        return 1
    fi
    # ServerTokens
    if grep -q "^ServerTokens" "$SECURITY_CONF"; then
        sed -i 's/^ServerTokens.*/ServerTokens Prod/' "$SECURITY_CONF"
    elif grep -q "^#.*ServerTokens" "$SECURITY_CONF"; then
        sed -i 's/^#.*ServerTokens.*/ServerTokens Prod/' "$SECURITY_CONF"
    else
        echo "ServerTokens Prod" >>"$SECURITY_CONF"
    fi
    echo "[OK] ServerTokens → Prod"
    # ServerSignature
    if grep -q "^ServerSignature" "$SECURITY_CONF"; then
        sed -i 's/^ServerSignature.*/ServerSignature Off/' "$SECURITY_CONF"
    elif grep -q "^#.*ServerSignature" "$SECURITY_CONF"; then
        sed -i 's/^#.*ServerSignature.*/ServerSignature Off/' "$SECURITY_CONF"
    else
        echo "ServerSignature Off" >>"$SECURITY_CONF"
    fi
    echo "[OK] ServerSignature → Off"
}

configure_nginx_banner() {
    local NGINX_CONF="/etc/nginx/nginx.conf"
    echo ""
    echo "=== Ocultando banner: Nginx ==="
    if [[ ! -f "$NGINX_CONF" ]]; then
        echo "[ERROR] No se encontró $NGINX_CONF"
        return 1
    fi
    if grep -q "^\s*server_tokens" "$NGINX_CONF"; then
        sed -i 's/^\s*server_tokens.*/    server_tokens off;/' "$NGINX_CONF"
    elif grep -q "^\s*#.*server_tokens" "$NGINX_CONF"; then
        sed -i 's/^\s*#.*server_tokens.*/    server_tokens off;/' "$NGINX_CONF"
    else
        sed -i '/^http {/a\    server_tokens off;' "$NGINX_CONF"
    fi
    echo "[OK] server_tokens → off"
}

configure_tomcat_banner() {
    local TOMCAT_CONF=""
    local POSSIBLE_PATHS=("/opt/tomcat/conf/server.xml" "/var/lib/tomcat9/conf/server.xml"
        "/var/lib/tomcat10/conf/server.xml" "/etc/tomcat9/server.xml")
    echo ""
    echo "=== Ocultando banner: Tomcat ==="
    for p in "${POSSIBLE_PATHS[@]}"; do
        if [[ -f "$p" ]]; then
            TOMCAT_CONF="$p"
            break
        fi
    done
    if [[ -z "$TOMCAT_CONF" ]]; then
        echo "[ERROR] No se encontró server.xml de Tomcat."
        return 1
    fi
    cp "$TOMCAT_CONF" "${TOMCAT_CONF}.bak"
    if grep -q 'server=' "$TOMCAT_CONF"; then
        sed -i 's/server="[^"]*"/server="."/' "$TOMCAT_CONF"
    else
        sed -i '/protocol="HTTP\/1.1"/s/\(protocol="HTTP\/1.1"\)/\1\n               server="."/' "$TOMCAT_CONF"
    fi
    echo "[OK] Atributo server → '.' en Connector HTTP"
}

ocultar_banner() {
    local servicio="$1"
    case "$servicio" in
    apache2) configure_apache_banner ;;
    nginx) configure_nginx_banner ;;
    tomcat*) configure_tomcat_banner ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
# 4. CONFIGURAR FIREWALL (UFW) — ABRIR PUERTO ELEGIDO, CERRAR DEFAULTS LIBRES
# ══════════════════════════════════════════════════════════════════════════════
configurar_firewall() {
    local nuevo_puerto="$1"

    echo ""
    echo "=== Configurando firewall (UFW) ==="

    if ! command -v ufw &>/dev/null; then
        echo "[INFO] UFW no está instalado. Instalando..."
        apt-get install -y ufw &>/dev/null
    fi

    # Habilitar UFW si no está activo
    if ! ufw status | grep -q "Status: active"; then
        ufw --force enable
        echo "[OK] UFW habilitado."
    fi

    # Abrir el puerto elegido
    ufw allow "${nuevo_puerto}/tcp"
    echo "[OK] Puerto ${nuevo_puerto}/tcp abierto."

    # Cerrar puertos HTTP por defecto si NO son el elegido y no están en uso
    local puertos_default=(80 443 8080 8443)
    for p in "${puertos_default[@]}"; do
        if [[ "$p" -ne "$nuevo_puerto" ]]; then
            if ! ss -tlnp | awk '{print $4}' | grep -qE ":${p}$"; then
                ufw deny "${p}/tcp" 2>/dev/null
                echo "[OK] Puerto $p cerrado (no está en uso)."
            else
                echo "[INFO] Puerto $p en uso por otro servicio, no se cerró."
            fi
        fi
    done
}

# ══════════════════════════════════════════════════════════════════════════════
# 5. CONTROL DE MÉTODOS HTTP + SECURITY HEADERS
# ══════════════════════════════════════════════════════════════════════════════
configurar_seguridad_apache() {
    local CONF="/etc/apache2/conf-available/security.conf"
    echo ""
    echo "=== Métodos HTTP y Security Headers: Apache ==="

    # Deshabilitar TRACE y TRACK
    if ! grep -q "^TraceEnable" "$CONF"; then
        echo "TraceEnable Off" >>"$CONF"
    else
        sed -i 's/^TraceEnable.*/TraceEnable Off/' "$CONF"
    fi
    echo "[OK] TraceEnable → Off"

    # Security headers en el conf
    local HEADERS_CONF="/etc/apache2/conf-available/security-headers.conf"
    cat >"$HEADERS_CONF" <<'EOF'
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</IfModule>
EOF
    a2enmod headers &>/dev/null
    a2enconf security-headers &>/dev/null
    echo "[OK] Security headers configurados en $HEADERS_CONF"

    # Bloquear métodos peligrosos en el VirtualHost por defecto
    local VHOST="/etc/apache2/sites-available/000-default.conf"
    if [[ -f "$VHOST" ]] && ! grep -q "LimitExcept" "$VHOST"; then
        sed -i 's|</VirtualHost>|    <Location />\n        <LimitExcept GET POST HEAD>\n            Require all denied\n        </LimitExcept>\n    </Location>\n</VirtualHost>|' "$VHOST"
        echo "[OK] Bloqueo de métodos peligrosos configurado en $VHOST"
    fi
}

configurar_seguridad_nginx() {
    local NGINX_CONF="/etc/nginx/nginx.conf"
    echo ""
    echo "=== Métodos HTTP y Security Headers: Nginx ==="

    # Bloque de headers de seguridad dentro de http {}
    local SNIPPET="
    # === Security Headers ===
    add_header X-Frame-Options \"SAMEORIGIN\" always;
    add_header X-Content-Type-Options \"nosniff\" always;
    add_header X-XSS-Protection \"1; mode=block\" always;
    add_header Referrer-Policy \"strict-origin-when-cross-origin\" always;
    # Bloquear métodos peligrosos
    if (\$request_method !~ ^(GET|POST|HEAD)$) {
        return 405;
    }"

    if grep -q "X-Frame-Options" "$NGINX_CONF"; then
        echo "[INFO] Security headers ya presentes en $NGINX_CONF"
    else
        sed -i "/^http {/a\\${SNIPPET}" "$NGINX_CONF"
        echo "[OK] Security headers agregados en $NGINX_CONF"
    fi
}

configurar_seguridad_tomcat() {
    local TOMCAT_CONF_DIR=""
    for d in "/etc/tomcat9" "/etc/tomcat10" "/var/lib/tomcat9/conf" "/opt/tomcat/conf"; do
        if [[ -d "$d" ]]; then
            TOMCAT_CONF_DIR="$d"
            break
        fi
    done

    if [[ -z "$TOMCAT_CONF_DIR" ]]; then
        echo "[ERROR] No se encontró directorio de configuración de Tomcat."
        return 1
    fi

    echo ""
    echo "=== Métodos HTTP y Security Headers: Tomcat ==="

    local WEB_XML="${TOMCAT_CONF_DIR}/web.xml"
    if [[ ! -f "$WEB_XML" ]]; then
        echo "[ERROR] No se encontró $WEB_XML"
        return 1
    fi

    cp "$WEB_XML" "${WEB_XML}.bak"

    # Agregar filtro de Security Headers antes de </web-app>
    if grep -q "X-Frame-Options" "$WEB_XML"; then
        echo "[INFO] Security headers ya presentes en $WEB_XML"
    else
        sed -i 's|</web-app>|  <filter>\
    <filter-name>httpHeaderSecurity</filter-name>\
    <filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class>\
    <init-param><param-name>antiClickJackingOption</param-name><param-value>SAMEORIGIN</param-value></init-param>\
    <init-param><param-name>blockContentTypeSniffingEnabled</param-name><param-value>true</param-value></init-param>\
    <init-param><param-name>xssProtectionEnabled</param-name><param-value>true</param-value></init-param>\
  </filter>\
  <filter-mapping>\
    <filter-name>httpHeaderSecurity</filter-name>\
    <url-pattern>/*</url-pattern>\
  </filter-mapping>\
</web-app>|' "$WEB_XML"
        echo "[OK] HttpHeaderSecurityFilter agregado en $WEB_XML"
    fi

    # Deshabilitar TRACE en server.xml
    local SERVER_XML="${TOMCAT_CONF_DIR}/server.xml"
    if [[ -f "$SERVER_XML" ]]; then
        if ! grep -q 'allowTrace' "$SERVER_XML"; then
            sed -i 's/\(protocol="HTTP\/1.1"\)/\1\n               allowTrace="false"/' "$SERVER_XML"
            echo "[OK] allowTrace → false en Connector HTTP"
        else
            sed -i 's/allowTrace="true"/allowTrace="false"/' "$SERVER_XML"
            echo "[OK] allowTrace ya existía → forzado a false"
        fi
    fi
}

configurar_seguridad_headers() {
    local servicio="$1"
    case "$servicio" in
    apache2) configurar_seguridad_apache ;;
    nginx) configurar_seguridad_nginx ;;
    tomcat*) configurar_seguridad_tomcat ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
# 6. VALIDAR PUERTOS RESERVADOS
# ══════════════════════════════════════════════════════════════════════════════
_validar_puerto_no_reservado() {
    local puerto="$1"
    # Puertos reservados para otros servicios conocidos (no HTTP)
    local reservados=(22 21 25 53 110 143 3306 5432 6379 27017)
    for r in "${reservados[@]}"; do
        if [[ "$puerto" -eq "$r" ]]; then
            echo "[ERROR] El puerto $puerto está reservado para otro servicio (ej: SSH=22, MySQL=3306)." >&2
            return 1
        fi
    done
    # Puertos por debajo de 1024 requieren aviso
    if ((puerto < 1024)); then
        echo "[ADVERTENCIA] El puerto $puerto es privilegiado (<1024). Se requiere permisos de root." >&2
    fi
    return 0
}

# ══════════════════════════════════════════════════════════════════════════════
# CAMBIAR PUERTO
# ══════════════════════════════════════════════════════════════════════════════
cambiarPuerto() {
    local servicio="$1"
    local nuevo_puerto="$2"

    if [[ -z "$servicio" || -z "$nuevo_puerto" ]]; then
        echo "[ERROR] Uso: cambiarPuerto <servicio> <puerto>" >&2
        return 1
    fi
    if ! _validar_puerto "$nuevo_puerto"; then
        echo "[ERROR] Puerto inválido: '$nuevo_puerto'." >&2
        return 1
    fi
    # Validar que no sea un puerto reservado para otros servicios
    _validar_puerto_no_reservado "$nuevo_puerto" || return 1

    if [[ "$servicio" == "tomcat" ]]; then
        local tomcat_pkg
        tomcat_pkg=$(_resolver_tomcat_instalado) || {
            echo "[ERROR] No se encontró Tomcat instalado." >&2
            return 1
        }
        servicio="$tomcat_pkg"
        echo "[INFO] Tomcat detectado: $servicio"
    fi

    local conf_file="${_HTTP_CONF_FILE[$servicio]}"
    if [[ -z "$conf_file" ]]; then
        echo "[ERROR] Servicio no reconocido: '$servicio'." >&2
        return 1
    fi
    if ss -tlnp | awk '{print $4}' | grep -qE ":${nuevo_puerto}$"; then
        local proceso
        proceso=$(ss -tlnp | grep ":${nuevo_puerto} " | awk '{print $NF}')
        echo "[ERROR] Puerto $nuevo_puerto ya está en uso por: $proceso" >&2
        return 1
    fi
    echo "[OK] Puerto $nuevo_puerto disponible."
    if ! dpkg -s "$servicio" &>/dev/null; then
        echo "[ERROR] '$servicio' no está instalado." >&2
        return 1
    fi
    if [[ ! -f "$conf_file" ]]; then
        echo "[ERROR] Archivo no encontrado: $conf_file" >&2
        return 1
    fi

    local backup="${conf_file}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$conf_file" "$backup"
    echo "[INFO] Backup: $backup"

    case "$servicio" in
    apache2)
        local pa
        pa=$(grep -m1 '^\s*Listen ' "$conf_file" | awk '{print $2}')
        sed -i "s/^\(\s*Listen\s\+\)[0-9]\+/\1${nuevo_puerto}/" "$conf_file"
        echo "[INFO] Apache2: $pa → $nuevo_puerto"
        ;;
    nginx)
        local pn
        pn=$(grep -m1 'listen\s\+[0-9]' "$conf_file" | grep -oP '\d+' | head -1)
        sed -i "s/\(listen\s\+\)[0-9]\+\(.*;\)/\1${nuevo_puerto}\2/" "$conf_file"
        echo "[INFO] Nginx: $pn → $nuevo_puerto"
        ;;
    tomcat*)
        local pt
        pt=$(grep -oP 'port="\K[0-9]+(?=".*protocol="HTTP)' "$conf_file" | head -1)
        sed -i "s/\(port=\"\)[0-9]*\(\"[^\"]*protocol=\"HTTP\)/\1${nuevo_puerto}\2/" "$conf_file"
        echo "[INFO] Tomcat: $pt → $nuevo_puerto"
        ;;
    esac

    echo "[INFO] Reiniciando $servicio..."
    if systemctl restart "$servicio"; then
        echo "[OK] $servicio reiniciado en el puerto $nuevo_puerto."
    else
        echo "[ERROR] Falló el reinicio. Restaura con: cp '$backup' '$conf_file'" >&2
        return 1
    fi

    # Configurar firewall con el nuevo puerto
    configurar_firewall "$nuevo_puerto"
}

function cambiarPuertoMenu() {
    echo "Cambiar puerto de un servicio HTTP"
    echo "---------------------------------"
    echo "1) Apache2"
    echo "2) Nginx"
    echo "3) Tomcat"
    echo "0) Salir"
    read -rp "Selecciona el servicio: " opc
    local servicio=""
    case "$opc" in
    1) servicio="apache2" ;;
    2) servicio="nginx" ;;
    3) servicio="tomcat" ;;
    0)
        echo "Saliendo"
        exit
        ;;
    *)
        echo "Opción inválida." >&2
        return 1
        ;;
    esac
    read -rp "Ingresa el nuevo puerto para $servicio: " nuevo_puerto
    cambiarPuerto "$servicio" "$nuevo_puerto"
}

# ══════════════════════════════════════════════════════════════════════════════
# INSTALACIÓN COMPLETA CON TODOS LOS PASOS DE SEGURIDAD
# ══════════════════════════════════════════════════════════════════════════════
_instalar_y_asegurar() {
    local paquete="$1"
    local version="$2"
    local puerto_default=""

    case "$paquete" in
    apache2) puerto_default=80 ;;
    nginx) puerto_default=80 ;;
    tomcat*) puerto_default=8080 ;;
    esac

    # Pedir puerto personalizado
    echo ""
    read -rp "¿En qué puerto deseas instalar $paquete? [default: $puerto_default]: " puerto_elegido
    puerto_elegido="${puerto_elegido:-$puerto_default}"

    if ! _validar_puerto "$puerto_elegido"; then
        echo "[ERROR] Puerto inválido."
        return 1
    fi
    _validar_puerto_no_reservado "$puerto_elegido" || return 1

    echo ""
    echo "══════════════════════════════════════════════"
    echo " Instalando $paquete versión $version"
    echo "══════════════════════════════════════════════"

    # 1. Instalar servicio
    getService "${paquete}=${version}"

    # 2. Cambiar puerto si es diferente al default
    if [[ "$puerto_elegido" != "$puerto_default" ]]; then
        cambiarPuerto "$paquete" "$puerto_elegido"
    else
        configurar_firewall "$puerto_elegido"
    fi

    # 3. Usuario dedicado y permisos
    configurar_usuario_dedicado "$paquete"

    # 4. Ocultar banner
    ocultar_banner "$paquete"

    # 5. Security headers y bloqueo de métodos peligrosos
    configurar_seguridad_headers "$paquete"

    # 6. Crear index.html personalizado
    crear_index "$paquete" "$version" "$puerto_elegido"

    # 7. Reiniciar para aplicar todo
    echo ""
    echo "=== Aplicando configuración final ==="
    systemctl restart "$paquete" 2>/dev/null || true

    echo ""
    echo "══════════════════════════════════════════════"
    echo " $paquete instalado y asegurado correctamente"
    echo "    Puerto:  $puerto_elegido"
    echo "    Usuario: $(_service_user "$paquete")"
    echo "    Web dir: $(_web_root "$paquete")"
    echo "══════════════════════════════════════════════"
}

function GetVersionesHTTP() {
    echo "Versiones de HTTP disponibles:"
    echo "1) Apache2"
    echo "2) Nginx"
    echo "3) Tomcat"
    echo "0) Salir"
    read -rp "Selecciona el server que deseas usar: " servicio

    local paquete=""
    case "$servicio" in
    1) paquete="apache2" ;;
    2) paquete="nginx" ;;
    3)
        _seleccionar_tomcat || return 1
        _instalar_y_asegurar "$SELECTED_PKG" "$SELECTED_VERSION"
        return 0
        ;;
    0)
        echo "Saliendo"
        exit
        ;;
    *)
        echo "Opción inválida." >&2
        return 1
        ;;
    esac

    echo ""
    echo "Versiones de ${paquete^} disponibles:"
    _seleccionar_version "$paquete" || return 1
    _instalar_y_asegurar "$paquete" "$SELECTED_VERSION"
}
