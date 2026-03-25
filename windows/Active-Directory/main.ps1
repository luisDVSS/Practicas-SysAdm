
. "$PSScriptRoot\funciones_ad.ps1"

#importacion de los modulos necesarios
Import-Module ActiveDirectory
Import-Module GroupPolicy
Import-Module FileServerResourceManager
#
#configuracion de todas 

#
#
while($true)
{
Write-Host "SERVICIO DE ACTIVE DIRECTORY MENU"
Write-Host "1) Instalacion de active directoriy / init Forest & domininio empresa.local "
Write-Host "2) Crear OUs"
Write-Host "3) Crear GPOS"
Write-Host "4) Configurar GPO cuates"
Write-Host "5) Configurar GPO no cuates"
Write-Host "6) Añadir las reglas de no/si ejecucion a cada grupo"
Write-Host "7) Linkear los grupos con su OU"
Write-Host "8) registro de usuarios (del csv)"
Write-Host "9) Configurar Fsrm para bloqueo de archivos formato(mp3,mp4,exe,msi)"
#compartir en la red la carpeta usuarios 
#recorre los usuarios noCuates y cuates
#y setea su homedirectory en \\empresa.local\Usuearios\(usuario en particular)
#tambien le da permisos acl a cada usuario a su carpeta
Write-Host "10) Configurar carpetas de usuarios"
Write-Host "11) Setear las horas permititdas"
Write-Host "12) PROCESAR TODOS LOS DATOS DE MANERA PREDEFINIDA"
Write-Host "0)salir"

    $opc= Read-Host "Opcion a ejecutar:"
switch($opc){
  "1"{
    #FLUJO NORMAL BASICO DE ACTIVE DIRECTORY
    Write-Host "Iniciando descarga"
    getADfeatures
    promoverServidor
    }
  "2"{
    Write-Host "Creando OU( Unidad Organizacional)" 
    crearOU
    }
  "3"{
    Write-Host "Creando GPOS...(Group Policy Object)" 
    crearGPOS
    }
  "4"{
    Write-Host "Configurando GPO de cuates"
    configGPOcuates
    }
  "5"{
    Write-Host "Configurando GPO de NoCuates" 
    configGPONocuates
    }
  "6"{ 
    Write-Host "Creando las reglas de los GPOS"
    setRulesGpos
    }
  "7"{
    Write-Host "Linkeando las reglas con esos GPOS"
    linkearGPOS
    }
  "8"{
    Write-Host "Registrando los usuarios en el csv: ..\usuarios.csv "
    regUsers
    }
  "9"{
    Write-Host "Configurando limites de tipos de archivos"
    configFsrm
    }
  "10"{
    Write-Host "Estableciendo las carpetas de usuario en red y asignando permisos"
    accesFolders
    }
    "11"{
      Write-Host "Seteando las horas establecidas." 
    setHours
    }
  "12"{
    # getADfeatures
    # promoverServidor
    crearOU
    crearGPOS
    configGPOcuates
    configGPONocuates
    setRulesGpos
    linkearGPOS
    regUsers
    configFsrm
    accesFolders  # <- faltaba
    setHours    
  }
  "0"{
      return
    }
    "*"{
        Write-Host "Opcion no valida"
        continue
      }

}



#final while
}
