. "$PSScriptRoot\funciones_ad.ps1"
. "$PSScriptRoot\funciones_smdfa.ps1"

# Importacion de modulos necesarios
# Import-Module ActiveDirectory
# Import-Module GroupPolicy
# Import-Module FileServerResourceManager

while($true) {

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   SERVICIO DE ACTIVE DIRECTORY MENU   " -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "--- INSTALACION Y ESTRUCTURA ---" -ForegroundColor Yellow
    Write-Host "1)  Instalacion de Active Directory / init Forest & dominio empresa.local"
    Write-Host "2)  Crear OUs (Cuates, NoCuates, AdminsDelegados)"
    Write-Host "3)  Crear GPOs"
    Write-Host "4)  Configurar GPO Cuates"
    Write-Host "5)  Configurar GPO NoCuates"
    Write-Host "6)  Añadir reglas de ejecucion a cada grupo (AppLocker)"
    Write-Host "7)  Linkear GPOs con sus OUs"
    Write-Host ""
    Write-Host "--- USUARIOS Y RECURSOS ---" -ForegroundColor Yellow
    Write-Host "8)  Registro de usuarios (del CSV)"
    Write-Host "9)  Configurar FSRM (bloqueo mp3, mp4, exe, msi)"
    Write-Host "10) Configurar carpetas de usuarios (red + permisos ACL)"
    Write-Host "11) Setear horarios permitidos"
    Write-Host "12) PROCESAR TODOS LOS DATOS DE MANERA PREDEFINIDA"
    Write-Host ""
    Write-Host "0)  Salir" -ForegroundColor Red
    Write-Host ""

    $opc = Read-Host "Opcion a ejecutar"

    switch($opc) {

        "1" {
            Write-Host "Iniciando instalacion de Active Directory..." -ForegroundColor Cyan
            getADfeatures
            promoverServidor
        }

        "2" {
            Write-Host "Creando OUs (Unidades Organizacionales)..." -ForegroundColor Cyan
            crearOU
        }

        "3" {
            Write-Host "Creando GPOs (Group Policy Objects)..." -ForegroundColor Cyan
            crearGPOS
        }

        "4" {
            Write-Host "Configurando GPO de Cuates..." -ForegroundColor Cyan
            configGPOcuates
        }

        "5" {
            Write-Host "Configurando GPO de NoCuates..." -ForegroundColor Cyan
            configGPONocuates
        }

        "6" {
            Write-Host "Aplicando reglas AppLocker a los GPOs..." -ForegroundColor Cyan
            setRulesGpos
        }

        "7" {
            Write-Host "Linkeando GPOs con sus OUs..." -ForegroundColor Cyan
            linkearGPOS
        }

        "8" {
            Write-Host "Registrando usuarios desde CSV..." -ForegroundColor Cyan
            regUsers
        }

        "9" {
            Write-Host "Configurando FSRM (bloqueo de formatos prohibidos)..." -ForegroundColor Cyan
            configFsrm
        }

        "10" {
            Write-Host "Configurando carpetas de usuarios en red y permisos ACL..." -ForegroundColor Cyan
            accesFolders
        }

        "11" {
            Write-Host "Seteando horarios de acceso permitidos..." -ForegroundColor Cyan
            setHours
        }

        "12" {
            Write-Host ""
            Write-Host ">>> PROCESANDO TODOS LOS DATOS DE MANERA PREDEFINIDA <<<" -ForegroundColor Magenta
            Write-Host ""

            Write-Host "[1/11] Creando OUs..."              -ForegroundColor Gray ; crearOU
            Write-Host "[2/11] Creando GPOs..."             -ForegroundColor Gray ; crearGPOS
            Write-Host "[3/11] Configurando GPO Cuates..."  -ForegroundColor Gray ; configGPOcuates
            Write-Host "[4/11] Configurando GPO NoCuates..." -ForegroundColor Gray ; configGPONocuates
            Write-Host "[5/11] Aplicando reglas AppLocker..." -ForegroundColor Gray ; setRulesGpos
            Write-Host "[6/11] Linkeando GPOs..."           -ForegroundColor Gray ; linkearGPOS
            Write-Host "[7/11] Registrando usuarios CSV..." -ForegroundColor Gray ; regUsers
            Write-Host "[8/11] Configurando FSRM..."        -ForegroundColor Gray ; configFsrm
            Write-Host "[9/11] Configurando carpetas..."    -ForegroundColor Gray ; accesFolders
            Write-Host "[10/11] Seteando horarios..."       -ForegroundColor Gray ; setHours
            Write-Host "[11/11] Creando admins delegados + RBAC + Auditoria + FGPP..." -ForegroundColor Gray
            crear_admins
            asignar_permisos_admins
            configurar_auditoria
            configurar_FGPP

            Write-Host ""
            Write-Host ">>> PROCESO COMPLETO FINALIZADO <<<" -ForegroundColor Magenta
        }
        "0" {
            Write-Host "Saliendo..." -ForegroundColor Red
            return
        }

        default {
            Write-Host "Opcion no valida. Intenta de nuevo." -ForegroundColor Red
            continue
        }
    }
}
