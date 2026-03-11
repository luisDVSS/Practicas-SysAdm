# ==============================================================================
# main.ps1  -  Script principal de aprovisionamiento HTTP para Windows Server
# Solo contiene llamadas a funciones (arquitectura modular obligatoria)
# ==============================================================================

# -- Localizar y cargar el archivo de funciones --------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

$FuncionesPath = Join-Path $ScriptDir "http_funciones.ps1"
if (-not (Test-Path $FuncionesPath)) {
    Write-Error "[ERROR] No se encontro http_funciones.ps1 en: $ScriptDir"
    exit 1
}
. $FuncionesPath   # dot-source: carga todas las funciones en el scope actual

# -- Verificar privilegios de administrador antes de continuar -----------------
Test-Admin

# ==============================================================================
# MENU PRINCIPAL
# ==============================================================================

Clear-Host
Write-Host "======================================================" 
Write-Host "        HTTP SERVICE - Windows Server                 " 
Write-Host "======================================================" 
Write-Host ""
Write-Host "  1) Ver estado de instalacion de servicios HTTP"
Write-Host "  2) Instalar un servicio HTTP"
Write-Host "  3) Cambiar puerto de un servicio HTTP"
Write-Host ""

do {
    $opc = Read-Host "  Selecciona una opcion"
    $opc = $opc.Trim()
    if ($opc -notmatch '^\d+$') {
        Write-Warning "  Ingresa solo digitos."
        $opc = ""
    }
} while ($opc -notin @("1","2","3"))

switch ($opc) {
    "1" { Get-EstadoHTTP           }
    "2" { Invoke-GetVersionesHTTP  }
    "3" { Invoke-CambiarPuertoMenu }
}