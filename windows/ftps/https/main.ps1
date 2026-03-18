# ============================================================
#  main.ps1  -  Practica 7: Orquestador principal
#               Windows Server 2022
# ============================================================
#Requires -RunAsAdministrator

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Definition

. "$SCRIPT_DIR\config.ps1"
. "$SCRIPT_DIR\http.ps1"
. "$SCRIPT_DIR\ftp_server.ps1"

while ($true) {
    Write-Host "`n======================================================" -ForegroundColor Cyan
    Write-Host "   PRACTICA 7  -  Windows Server 2022"
    Write-Host "======================================================"
    Write-Host "  INSTALACION HTTP"
    Write-Host "  1) Instalar Apache httpd"
    Write-Host "  2) Instalar Nginx"
    Write-Host "  3) Instalar IIS"
    Write-Host ""
    Write-Host "  HTTPS (SSL)"
    Write-Host "  4) Activar HTTPS en Apache"
    Write-Host "  5) Activar HTTPS en Nginx"
    Write-Host "  6) Activar HTTPS en IIS"
    Write-Host ""
    Write-Host "  CAMBIAR PUERTO"
    Write-Host "  7) Cambiar puerto Apache"
    Write-Host "  8) Cambiar puerto Nginx"
    Write-Host ""
    Write-Host "  SERVIDOR FTP (repositorio)"
    Write-Host "  9) Configurar servidor FTP / repositorio"
    Write-Host ""
    Write-Host "  0) Salir"
    Write-Host "------------------------------------------------------"
    $opc = Read-Host "  Opcion"

    switch ($opc) {
        "1" { Install-HttpServer -Servidor "Apache" }
        "2" { Install-HttpServer -Servidor "Nginx"  }
        "3" {
            $puerto = Read-Port -Default 80 -Label "Puerto HTTP"
            Install-IIS -Puerto $puerto
        }
        "4" { Set-Https -Servidor "Apache" }
        "5" { Set-Https -Servidor "Nginx"  }
        "6" {
            $puerto = Read-Port -Default 443 -Label "Puerto HTTPS"
            Enable-IISHttps -Puerto $puerto
        }
        "7" { Set-HttpPort -Servidor "Apache" }
        "8" { Set-HttpPort -Servidor "Nginx"  }
        "9" { Invoke-FtpServerSetup }
        "0" { Write-Host "  Saliendo..."; exit 0 }
        default { Write-Host "  Opcion invalida." -ForegroundColor Yellow }
    }
}