New-Item -Path "C:\FTP\LocalUser\Administrador" -ItemType Directory -Force | Out-Null
cmd /c mklink /J "C:\FTP\LocalUser\Administrador\Instaladores" "C:\FTP\Practica7" | Out-Null
Import-Module WebAdministration
Set-WebConfigurationProperty -Filter "/system.ftpServer/security/authentication/basicAuthentication" -Name Enabled -Value True -PSPath IIS:\ -Location "FTP"
Restart-Service ftpsvc -Force