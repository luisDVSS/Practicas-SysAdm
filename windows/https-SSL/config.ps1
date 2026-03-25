# ============================================================
#  config.ps1  -  Variables globales compartidas
#  Dot-source este archivo en todos los demas scripts:
#    . "$PSScriptRoot\config.ps1"
# ============================================================

# ── Rutas FTP servidor ────────────────────────────────────────
$CFG_FTP_BASE     = "C:\srv\ftp"
$CFG_FTP_REPO     = "$CFG_FTP_BASE\repo"          # repositorio de binarios
$CFG_FTP_SITE     = "Practica7-FTP"
$CFG_FTP_PORT     = 21
$CFG_APPCMD       = "$env:windir\system32\inetsrv\appcmd.exe"

# ── Rutas HTTP servidores ─────────────────────────────────────
$CFG_APACHE_DIR   = "C:\Apache24"
$CFG_NGINX_DIR    = "C:\nginx"
$CFG_APACHE_SVC   = "Apache2.4"
$CFG_NGINX_SVC    = "nginx"

# ── Descarga FTP cliente ──────────────────────────────────────
# Con aislamiento IIS FTP el usuario 'repo' ve su carpeta como "/"
# Dentro hay una junction llamada 'repo' -> C:\srv\ftp\repo
# Por eso la ruta remota es /repo/http/Windows
$CFG_FTP_REPO_BASE = "/repo/http/Windows"
$CFG_DOWNLOAD_DIR  = "C:\Temp\practica7\downloads"

# ── URLs descarga directa (fallback si no hay FTP) ───────────
$CFG_APACHE_URL   = "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.65-250724-Win64-VS17.zip"
$CFG_NGINX_URL    = "https://nginx.org/download/nginx-1.26.3.zip"
$CFG_VCREDIST_URL = "https://aka.ms/vs/17/release/vc_redist.x64.exe"

# ── Directorio temporal general ───────────────────────────────
$CFG_TEMP_DIR     = "C:\Temp\practica7"