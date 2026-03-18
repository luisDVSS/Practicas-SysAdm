 . "$PSScriptRoot\http_funciones.ps1"
 . "$PSScriptRoot\Configurar-FTP.ps1"
 
 do{
Write-Host "10. Registrar Grupo FTP"
 Write-Host "14. Blindar FTP con SSL (Práctica 7)"
 Write-Host "16. Servidores Web (HTTP / Orquestador)"

 $op = Read-Host "Seleccione una opcion"
switch ($op) {
      "10" { Registrar-Grupo-FTP }
    "14" { Activar-Seguridad-FTPS }
    
    "16" { 
                Clear-Host
                Write-Host "=== ORQUESTADOR HÍBRIDO (PRÁCTICA 7) ===" -ForegroundColor Yellow
                Write-Host "1. Desplegar IIS (Requisito Forzoso)"
                Write-Host "2. Desplegar Nginx (Web o FTP Privado)"
                Write-Host "3. Desplegar Apache (Web o FTP Privado)"
                $subOp = Read-Host "Seleccione el servidor a instalar"
                
                if ($subOp -eq "1") { Desplegar-IIS }
                elseif ($subOp -eq "2") { Desplegar-Nginx-Windows }
                elseif ($subOp -eq "3") { Desplegar-Apache-Windows }
                else { Write-Host "Opcion invalida"; Pause }
            }
      Default {}
}


}while ($op -ne "0")