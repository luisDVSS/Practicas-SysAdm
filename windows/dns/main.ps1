
# Importar scripts auxiliares

. "$PSScriptRoot\Funciones.ps1"
. "$PSScriptRoot\config_red.ps1"

# Confirmar configuracion DNS

function Ask-Conf {

    $cont = Read-Host "¿Deseas continuar con la configuracion? [s/n]"

    switch ($cont.ToLower()) {
        "s" {
            Write-Host "Continuando con la configuracion..."
            Set-ConfigDns
        }
        "n" {
            Write-Host "Saliendo del script..."
            exit 0
        }
        default {
            Write-Host "Opcion no valida"
        }
    }
}

function Ask-Dhcp {

    $cont_dhc = Read-Host "¿Deseas continuar al menu de dhcp? [s/n]"

    switch ($cont_dhc.ToLower()) {
        "s" {
            Write-Host "Cambiando al menu de dhcp..."
        & "$PSScriptRoot\..\dhcpwin\main.ps1"
        }
        "n" {
            Write-Host "Saliendo del script..."
            exit 0
        }
        default {
            Write-Host "Opcion no valida"
        }
    }
}
function menu{
while ($true) {

    Write-Host ""
    Write-Host "Selecciona una opcion"
    Write-Host "1) Ver si el servicio DNS esta instalado"
    Write-Host "2) Instalar servicio DNS"
    Write-Host "3) Eliminar un dominio"
    Write-Host "4) Dominios registrados"
    Write-Host "5) Configurar DHCP"
    Write-Host "6) Salir"
    
    Write-Host ""

    $opc = Read-Host "Opcion"

    switch ($opc) {

      
        # Verificar instalacion DNS
       
        "1" {
            if (Is-Installed "DNS") {
                Write-Host "El servicio DNS YA esta instalado."
            } else {
                Write-Host "El servicio DNS NO esta instalado."
            }
        }

       # Instalar DNS
     
        "2" {
            Write-Host "Validando instalacion del servicio DNS..."

            if (Is-Installed "DNS") {
                Write-Host "El servicio DNS ya esta instalado."
                Ask-Conf
            } else {
                Write-Host "Procediendo con la instalacion del servicio DNS..."
                Get-ServiceFeature DNS
                Write-Host "Servicio DNS instalado correctamente."
                Ask-Conf
            }
        }

      
        # Eliminar dominio
    
        "3" {
            if (Is-Installed "DNS") {
                Delete-Domain
            } else {
                Write-Host "El servicio DNS no esta instalado."
            }
        }

       
        # Mostrar dominios
      
        "4" {
            Get-Domains
        }

      
        # Salir
       
        "5" {
            Ask-Dhcp
            
        }
         "6" {
            Write-Host "Saliendo..."
            exit 0
        }

        # ===============================
        # Opcion invalida
        # ===============================
        default {
            Write-Host "Opcion invalida"
        }
    }
}

}


# Menu principal
if (-not (Test-IPStatica -Interfaz "Ethernet 2")) {

    Write-Host "ERROR: El servidor debe tener IP estatica antes de instalar DNS" -ForegroundColor Red
    $confdef = Read-Host "¿Desea aplicar una configuracion por defecto a la red interna? [s/n]"

    switch ($confdef.ToLower()) {
        "s" { 
            Write-Host "Aplicando configuracion por defecto..."
            Set-ConfigDefaultEthernet2

            Start-Sleep -Seconds 2

            if (-not (Test-IPStatica -Interfaz "Ethernet 2")) {
                Write-Host "No se pudo aplicar la IP estatica. Abortando." -ForegroundColor Red
                exit 1
            }
        }
        default {
            Write-Host "Saliendo del script..."
            exit 0
        }
    }
}

Write-Host "Puedes continuar con la instalacion del DNS" -ForegroundColor Green
menu
