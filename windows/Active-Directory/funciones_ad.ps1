#import de usuarios
function getADfeatures{

 # Instalar FSRM primero
 Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools
 # 1. Active Directory Domain Services
 Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

 # 2. Group Policy Management
 Install-WindowsFeature GPMC

 # 4. DNS (necesario para AD)
 Install-WindowsFeature DNS -IncludeManagementTools

}
function promoverServidor{
   Install-ADDSForest -DomainName "empresa.local" `
                       -DomainNetbiosName "EMPRESA" `
                       -InstallDns:$true `
                       -Force:$true
  }

$global:usuarios = Import-Csv -Path "$PSScriptRoot\usuarios.csv"
#se ejcuta primero que la 'crearGPOS'
function crearOU {
    if (-not (Get-ADOrganizationalUnit -Filter {Name -eq "Cuates"})) {
        New-ADOrganizationalUnit -Name "Cuates" -Path "DC=empresa,DC=local" -Description "Personal de cuates"
    }
    if (-not (Get-ADOrganizationalUnit -Filter {Name -eq "NoCuates"})) {
        New-ADOrganizationalUnit -Name "NoCuates" -Path "DC=empresa,DC=local" -Description "Personal de NoCuates"
    }

    # AGREGAR ESTO:
    if (-not (Get-ADGroup -Filter {Name -eq "Cuates"} -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name "Cuates" -GroupScope Global -GroupCategory Security -Path "OU=Cuates,DC=empresa,DC=local"
    }
    if (-not (Get-ADGroup -Filter {Name -eq "NoCuates"} -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name "NoCuates" -GroupScope Global -GroupCategory Security -Path "OU=NoCuates,DC=empresa,DC=local"
    }
}

function crearGPOS{
  New-GPO -Name "GPO-HorarioCuates"
  New-GPO -Name "GPO-HorarioNoCuates"
}
function setRulesGpos{
    $xmlCuates   = "$PSScriptRoot\Cuates.xml"
    $xmlNoCuates = "$PSScriptRoot\NoCuates.xml"

    Set-AppLockerPolicy -XmlPolicy $xmlCuates `
        -Ldap "LDAP://CN={$((Get-GPO -Name 'GPO-HorarioCuates').Id)},CN=Policies,CN=System,DC=empresa,DC=local"

    Set-AppLockerPolicy -XmlPolicy $xmlNoCuates `
        -Ldap "LDAP://CN={$((Get-GPO -Name 'GPO-HorarioNoCuates').Id)},CN=Policies,CN=System,DC=empresa,DC=local"

    # Aplicar también localmente en cada cliente via GPO script
    # o forzar gpupdate en clientes
    # Invoke-Command -ComputerName DESKTOP-2RPEA3I -Credential empresa\Administrador -ScriptBlock {
    #     gpupdate /force
    # }
}
function configGPOcuates{
  Set-GPRegistryValue -Name "GPO-HorarioCuates" -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" -ValueName "EnableForcedLogOff" -Value 1 -Type DWord

  Set-GPRegistryValue -Name "GPO-HorarioCuates" `
        -Key "HKLM\SYSTEM\ControlSet001\Services\AppIDSvc" `
        -ValueName "Start" -Value 2 -Type DWord
}

function configGPONocuates{
  Set-GPRegistryValue -Name "GPO-HorarioNoCuates" -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" -ValueName "EnableForcedLogOff" -Value 1 -Type DWord

  Set-GPRegistryValue -Name "GPO-HorarioNoCuates" `
        -Key "HKLM\SYSTEM\ControlSet001\Services\AppIDSvc" `
        -ValueName "Start" -Value 2 -Type DWord
}
function linkearGPOS{
  New-GPLink -Name "GPO-HorarioCuates" -Target "OU=Cuates,DC=empresa,DC=local" -LinkEnabled Yes
  New-GPLink -Name "GPO-HorarioNoCuates" -Target "OU=NoCuates,DC=empresa,DC=local" -LinkEnabled Yes
}
#Flujo de ejecucion
#crearGPOS, setRulesGpos, configGpos(cuates y NoCuates) linkearGPOS(linkea los grupos con sus )
function regUsers{
  #horario de los 7 dias de las semana para los cuates
$bytesCuates = [byte[]](
    0,248,127, 0,248,127,
    0,248,127, 0,248,127,
    0,248,127, 0,248,127,
    0,248,127
)
$bytesNoCuates = [byte[]](
    255,1,192, 255,1,192,
    255,1,192, 255,1,192,
    255,1,192, 255,1,192,
    255,1,192
)
  foreach ($usuario in $global:usuarios){
    if($usuario.depto -eq "Cuates"){
     $ou="OU=Cuates,DC=empresa,DC=local"
     $horario=$bytesCuates
     $cuota=10MB
    }
   
    if($usuario.depto -eq "NoCuates"){
     $ou="OU=NoCuates,DC=empresa,DC=local"
     $horario=$bytesNoCuates
     $cuota=5MB
    }
    
    $ruta="C:\Users\$($usuario.accountName)"
    #Creacion de ruta de user
    if (-not(Test-Path $ruta)){ 
    New-Item -Path $ruta -ItemType Directory
    
    }



    #creacion de los usuario
    New-ADUser -Name $usuario.nombre -SamAccountName $usuario.accountName -AccountPassword (ConvertTo-SecureString $usuario.password -AsPlainText -Force) -Path $ou -Enabled $true
Add-ADGroupMember -Identity $usuario.depto -Members $usuario.accountName
    #seteo de los horarios segun su grupo o depto
    Set-ADUser -Identity $usuario.accountName -Replace @{LogonHours=$horario} -HomeDirectory $ruta -HomeDrive "H:"
    
    #Asignacion de la cuota de la carpeta
    New-FsrmQuota -Path $ruta -Size $cuota
    }
  }
function setHours{
$bytesCuates = [byte[]](
    0, 128, 63,   # Domingo
    0, 128, 63,   # Lunes
    0, 128, 63,   # Martes
    0, 128, 63,   # Miércoles
    0, 128, 63,   # Jueves
    0, 128, 63,   # Viernes
    0, 128, 63    # Sábado
)

# NoCuates: 3pm-2am MST (UTC 22:00-09:59) — cruza medianoche UTC
$bytesNoCuates = [byte[]](
    255, 3, 0,    # Domingo  (solo recibe 0:00-9:59 UTC, sin tarde anterior)
    255, 3, 192,  # Lunes
    255, 3, 192,  # Martes
    255, 3, 192,  # Miércoles
    255, 3, 192,  # Jueves
    255, 3, 192,  # Viernes
    255, 3, 192   # Sábado
)

    # 255,255,255, 255,255,255,
    # 255,255,255, 255,255,255,
    # 255,255,255, 255,255,255,
    # 255,255,255

  foreach ($usuario in $global:usuarios){
    if($usuario.depto -eq "Cuates"){
     # $ou="OU=Cuates,DC=empresa,DC=local"
     $horario=$bytesCuates
     # $cuota=10MB
     #
    $ruta="C:\Users\$($usuario.accountName)"
    }
   
    if($usuario.depto -eq "NoCuates"){
     # $ou="OU=NoCuates,DC=empresa,DC=local"
     $horario=$bytesNoCuates
     # $cuota=5MB
     #
    $ruta="C:\Users\$($usuario.accountName)"
    }
    
    Set-ADUser -Identity $usuario.accountName -Replace @{LogonHours=$horario} -HomeDirectory $ruta -HomeDrive "H:"
    }



  }
function configFsrm{
    #bloqueo de formatos distintos de archivos
    New-FsrmFileGroup -Name "ArchivosProhibidos" -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi")
    New-FsrmFileScreen -Path "C:\Users" -IncludeGroup "ArchivosProhibidos"
}
function accesFolders{
  #creacion de el link logico de red de la carpeta users
New-SmbShare -Name "Usuarios" -Path "C:\Users" -FullAccess "Admins. del dominio" -ChangeAccess "Usuarios del dominio"
 #acceso a los usuarios NoCuates a users via red
Get-ADUser -Filter * -SearchBase "OU=Cuates,DC=empresa,DC=local" | ForEach-Object {
 Set-ADUser -Identity $_.SamAccountName `
 -HomeDirectory "\\empresa.local\Usuarios\$($_.SamAccountName)" `
 -HomeDrive "H:"
 }
 #acceso a los usuarios NoCuates a users via red
Get-ADUser -Filter * -SearchBase "OU=NoCuates,DC=empresa,DC=local" | ForEach-Object {
 Set-ADUser -Identity $_.SamAccountName `
 -HomeDirectory "\\empresa.local\Usuarios\$($_.SamAccountName)" `
 -HomeDrive "H:"
}

Get-ADUser -Filter * -SearchBase "OU=Cuates,DC=empresa,DC=local" | ForEach-Object {
 $path = "C:\Users\$($_.SamAccountName)"
 if (Test-Path $path) {
 $acl = Get-Acl $path
 $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($_.SamAccountName, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
 $acl.SetAccessRule($rule)
 Set-Acl $path $acl
  }
}
#acceso al repo esacto de user
Get-ADUser -Filter * -SearchBase "OU=NoCuates,DC=empresa,DC=local" | ForEach-Object {
 $path = "C:\Users\$($_.SamAccountName)"
 if (Test-Path $path) {
 $acl = Get-Acl $path
 $rule = New-Object System.Security.AccessControl.FileSystemAccessRule($_.SamAccountName, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
 $acl.SetAccessRule($rule)
 Set-Acl $path $acl
  }
}

#fin llave
}
