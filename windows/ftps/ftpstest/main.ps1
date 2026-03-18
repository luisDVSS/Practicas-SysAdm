# ============================================================
#  main.ps1  -  Practica 7: Orquestador principal
#               Windows Server 2022 (sin GUI)
# ============================================================
#Requires -RunAsAdministrator

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition

. "$SCRIPT_DIR\http_funciones.ps1"
. "$SCRIPT_DIR\ftp_funciones.ps1"
. "$SCRIPT_DIR\ssl_funciones.ps1"
. "$SCRIPT_DIR\ftp_cliente.ps1"

# ─────────────────────────────────────────────────────────────
# Verificar si un servicio Windows esta instalado/activo
# ─────────────────────────────────────────────────────────────
function Verificar-Servicio {
    param([string]$Nombre)
    $svc = Get-Service -Name $Nombre -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "  Servicio '$Nombre': $($svc.Status)" -ForegroundColor Cyan
    } else {
        Write-Host "  Servicio '$Nombre' no encontrado." -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────────────────────
# Instalar servidor HTTP (IIS, Apache, Nginx) via WEB o FTP
# ─────────────────────────────────────────────────────────────
function Instalar-ServidorHTTP {
    param([string]$Servidor)

    Write-Host ""
    Write-Host "======================================================"
    Write-Host "  INSTALACION DE: $Servidor"
    Write-Host "======================================================"
    Write-Host "  Origen:"
    Write-Host "    1) WEB  - descarga directa / instalacion de rol"
    Write-Host "    2) FTP  - repositorio FTP privado"
    $origen = Read-Host "  Elige [1/2]"

    switch ($origen) {
        "1" {
            switch ($Servidor.ToLower()) {
                "iis" {
                    $puerto = Leer-Puerto -Default 80
                    Instalar-IIS -Puerto $puerto
                }
                "apache" {
                    $puerto = Leer-Puerto -Default 80
                    Instalar-Apache -Puerto $puerto
                }
                "nginx" {
                    $puerto = Leer-Puerto -Default 8080
                    Instalar-Nginx -Puerto $puerto
                }
            }
        }
        "2" {
            # El cliente FTP maneja todo el flujo interactivo
            Instalar-DesdeFTP
        }
        default {
            Write-Host "  Opcion invalida." -ForegroundColor Yellow
            return
        }
    }

    # ── Preguntar SSL tras instalacion ────────────────────────
    $activarSSL = Read-Host "  Activar SSL en $Servidor? [S/N]"
    if ($activarSSL -match '^[sS]$') {
        # Generar certificado si no existe
        $certExiste = Get-ChildItem $CERT_STORE -ErrorAction SilentlyContinue |
            Where-Object { $_.FriendlyName -like "Practica7*" }
        if (-not $certExiste) { Generar-Certificado | Out-Null }

        switch ($Servidor.ToLower()) {
            "iis"    { SSL-IIS }
            "apache" { SSL-Apache }
            "nginx"  { SSL-Nginx }
        }
    }
}

# ─────────────────────────────────────────────────────────────
# Modulo FTP: instalacion y gestion de usuarios
# ─────────────────────────────────────────────────────────────
function Menu-FTP {
    while ($true) {
        Write-Host ""
        Write-Host "======================================================"
        Write-Host "   CONFIGURACION vsftpd  (IIS FTP en Windows)"
        Write-Host "======================================================"
        Write-Host "  1) Ver estado del servicio FTP"
        Write-Host "  2) Instalar y configurar IIS FTP"
        Write-Host "  3) Registrar usuarios"
        Write-Host "  4) Cambiar de grupo un usuario"
        Write-Host "  5) Eliminar usuario"
        Write-Host "  6) Crear usuario repositorio (repo)"
        Write-Host "  7) Activar FTPS (SSL)"
        Write-Host "  8) Diagnostico usuario 'repo' (verificar junction y permisos)"
        Write-Host "  0) Volver al menu principal"
        Write-Host "------------------------------------------------------"
        $opc = Read-Host "  Opcion"

        switch ($opc) {
            "1" { Get-EstadoFTP }
            "2" { Set-FtpConf }
            "3" {
                Write-Host "  ------- Registro de usuarios -------"
                $numUsers = Read-Host "  Cuantos usuarios registraras"
                for ($i = 1; $i -le [int]$numUsers; $i++) {
                    do {
                        $user = Read-Host "  Nombre del usuario $i"
                        if (Get-LocalUser -Name $user -ErrorAction SilentlyContinue) {
                            Write-Host "  El usuario '$user' ya existe." -ForegroundColor Yellow
                            $user = $null
                        }
                    } while (-not $user)

                    do {
                        Write-Host "  Grupo: Reprobados=1 | Recursadores=2"
                        $gpo = Read-Host "  Grupo para $user"
                    } while ($gpo -notin @("1","2"))

                    $grupo = if ($gpo -eq "1") { "Reprobados" } else { "Recursadores" }
                    Crear-Usuario -User $user -Grupo $grupo
                }
            }
            "4" {
                $user = Read-Host "  Usuario a cambiar de grupo"
                Cambiar-Grupo -User $user
            }
            "5" {
                $user = Read-Host "  Usuario a eliminar"
                Eliminar-Usuario -User $user
            }
            "6" { Crear-UsuarioRepo }
            "7" {
                $certExiste = Get-ChildItem $CERT_STORE -ErrorAction SilentlyContinue |
                    Where-Object { $_.FriendlyName -like "Practica7*" }
                if (-not $certExiste) { Generar-Certificado | Out-Null }
                SSL-FTP
            }
            "8" { Diagnostico-Repo }
            "0" { return }
            default { Write-Host "  Opcion invalida." -ForegroundColor Yellow }
        }
    }
}

# ─────────────────────────────────────────────────────────────
# MENU PRINCIPAL
# ─────────────────────────────────────────────────────────────
while ($true) {
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "   PRACTICA 7 - Orquestador Windows Server 2022"
    Write-Host "                [reprobados.com]"
    Write-Host "======================================================"
    Write-Host "  INSTALACION HTTP"
    Write-Host "  1) IIS"
    Write-Host "  2) Apache httpd"
    Write-Host "  3) Nginx"
    Write-Host "  4) Cambiar puerto de un servidor ya instalado"
    Write-Host ""
    Write-Host "  FTP"
    Write-Host "  5) Gestion de servidor FTP (IIS FTP)"
    Write-Host ""
    Write-Host "  SSL / SEGURIDAD"
    Write-Host "  6) Generar certificado SSL"
    Write-Host "  7) Activar HTTPS -> IIS"
    Write-Host "  8) Activar HTTPS -> Apache"
    Write-Host "  9) Activar HTTPS -> Nginx"
    Write-Host " 10) Activar FTPS  -> IIS FTP"
    Write-Host ""
    Write-Host "  VERIFICACION"
    Write-Host " 11) Resumen SSL (todos los servicios)"
    Write-Host " 12) Verificar integridad de archivo descargado"
    Write-Host ""
    Write-Host "  0) Salir"
    Write-Host "------------------------------------------------------"
    $opc = Read-Host "  Opcion"

    switch ($opc) {
        "1" { Instalar-ServidorHTTP -Servidor "IIS" }
        "2" { Instalar-ServidorHTTP -Servidor "Apache" }
        "3" { Instalar-ServidorHTTP -Servidor "Nginx" }
        "4" {
            Write-Host "  Servidor: IIS=1 | Apache=2 | Nginx=3"
            $srv = Read-Host "  Selecciona"
            $nombre = switch ($srv) { "1" { "iis" } "2" { "apache" } "3" { "nginx" } default { $null } }
            if ($nombre) {
                $puerto = Leer-Puerto
                Cambiar-Puerto -Servicio $nombre -Puerto $puerto
            } else {
                Write-Host "  Opcion invalida." -ForegroundColor Yellow
            }
        }
        "5"  { Menu-FTP }
        "6"  { Generar-Certificado | Out-Null }
        "7"  { SSL-IIS }
        "8"  { SSL-Apache }
        "9"  { SSL-Nginx }
        "10" { SSL-FTP }
        "11" { Resumen-SSL }
        "12" {
            $arch = Read-Host "  Ruta del archivo"
            Verificar-Integridad -Archivo $arch
        }
        "0" {
            Write-Host "  Saliendo..."
            exit 0
        }
        default { Write-Host "  Opcion invalida." -ForegroundColor Yellow }
    }
}