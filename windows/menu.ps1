# Obtener la carpeta donde está este script
$SCRIPT_DIR = $PSScriptRoot

# Cargar librería
. (Join-Path $SCRIPT_DIR "lib_func.ps1")

Write-Host "<----------------MENU---------------->"
Write-Host ""

while ($true) {

    Write-Host "1) DHCP"
    Write-Host "2) DNS"
    Write-Host "3) SSH"

    $opc = Read-Host "Seleccione una opcion"

    switch ($opc) {

        "1" {
            Start-Process powershell -Verb RunAs -ArgumentList "-File `"$SCRIPT_DIR\dhcp\main.ps1`""
        }

        "2" {
            Start-Process powershell -Verb RunAs -ArgumentList "-File `"$SCRIPT_DIR\dns\main.ps1`""
        }

        "3" {
            Start-Process powershell -Verb RunAs -ArgumentList "-File `"$SCRIPT_DIR\ssh\main.ps1`""
        }

        default {
            Write-Host "Opcion no valida"
        }
    }

    Write-Host ""
}