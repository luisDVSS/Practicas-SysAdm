# =========================================
# Importar scripts auxiliares
# =========================================
. .\Funciones.ps1
. .\config_dns.ps1

# =========================================
# Confirmar configuración DNS
# =========================================
function Ask-Conf {

    $cont = Read-Host "¿Deseas continuar con la configuración? [s/n]"

    switch ($cont.ToLower()) {
        "s" {
            Write-Host "Continuando con la configuración..."
            Set-ConfigDns
        }
        "n" {
            Write-Host "Saliendo del script..."
            exit 0
        }
        default {
            Write-Host "Opción no válida"
        }
    }
}

# =========================================
# Menú principal
# =========================================
while ($true) {

    Write-Host ""
    Write-Host "Selecciona una opción"
    Write-Host "1) Ver si el servicio DNS está instalado"
    Write-Host "2) Instalar servicio DNS"
    Write-Host "3) Eliminar un dominio"
    Write-Host "4) Dominios registrados"
    Write-Host "5) Salir"
    Write-Host ""

    $opc = Read-Host "Opción"

    switch ($opc) {

        # ===============================
        # Verificar instalación DNS
        # ===============================
        "1" {
            if (Is-Installed "DNS") {
                Write-Host "El servicio DNS YA está instalado."
            } else {
                Write-Host "El servicio DNS NO está instalado."
            }
        }

        # ===============================
        # Instalar DNS
        # ===============================
        "2" {
            Write-Host "Validando instalación del servicio DNS..."

            if (Is-Installed "DNS") {
                Write-Host "El servicio DNS ya está instalado."
                Ask-Conf
            } else {
                Write-Host "Procediendo con la instalación del servicio DNS..."
                Get-ServiceFeature DNS
                Write-Host "Servicio DNS instalado correctamente."
                Ask-Conf
            }
        }

        # ===============================
        # Eliminar dominio
        # ===============================
        "3" {
            if (Is-Installed "DNS") {
                Delete-Domain
            } else {
                Write-Host "El servicio DNS no está instalado."
            }
        }

        # ===============================
        # Mostrar dominios
        # ===============================
        "4" {
            Get-Domains
        }

        # ===============================
        # Salir
        # ===============================
        "5" {
            Write-Host "Saliendo..."
            break
        }

        # ===============================
        # Opción inválida
        # ===============================
        default {
            Write-Host "Opción inválida"
        }
    }
}
