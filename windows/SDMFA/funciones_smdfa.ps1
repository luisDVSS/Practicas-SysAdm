function valid_ou_ad{
  Write-Host "Validando que existan los OU: Cuates y NoCuates"
  if(Get-ADOrganizationalUnit -Filter "distinguishedName -eq 'OU=Cuates,DC=empresa,DC=local'"){
    Write-Host "El OU de Cuates existe"
  }
  
  if(Get-ADOrganizationalUnit -Filter "distinguishedName -eq 'OU=NoCuates,DC=empresa,DC=local'"){
    Write-Host "El OU de NoCuates existe."
  }
}
function valid_users_exists{
  Write-Host "Validando la existencia de usuarios en los OU"
  if(Get-ADUser -Filter * -SearchBase "OU=NoCuates,DC=empresa,DC=local"){
    Write-Host "Correcto: Existen usuarios de OU NoCuates"
  }

  if(Get-ADUser -Filter * -SearchBase "OU=Cuates,DC=empresa,DC=local"){
    Write-Host "Correcto: Existen usuarios del OU Cuates"
  }

}
function crear_admins{
  #admin_identidad
  #admin_politicas
  #admin_storage
  #admin_auditoria
   New-ADUser -Name "admin_identidad" -SamAccountName "admin_identidad" -AccountPassword (ConvertTo-SecureString "Password123!" -AsPlainText -Force) -Enabled $true
   New-ADUser -Name "admin_politicas" -SamAccountName "admin_politicas" -AccountPassword (ConvertTo-SecureString "Password123!" -AsPlainText -Force) -Enabled $true
   New-ADUser -Name "admin_storage" -SamAccountName "admin_storage" -AccountPassword (ConvertTo-SecureString "Password123!" -AsPlainText -Force) -Enabled $true
   New-ADUser -Name "admin_auditoria" -SamAccountName "admin_auditoria" -AccountPassword (ConvertTo-SecureString "Password123!" -AsPlainText -Force) -Enabled $true
  

}
function asignar_permisos_admins {

    # ROL 1: admin_identidad
    # Permiso para resetear contraseñas en OU Cuates
    dsacls "OU=Cuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:CA;Reset Password;user"
    # Permiso para crear/eliminar usuarios en OU Cuates
    dsacls "OU=Cuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:CCDC;user"
    # Permiso para modificar atributos básicos (teléfono, oficina, correo)
    dsacls "OU=Cuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:WP;telephoneNumber;user"
    dsacls "OU=Cuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:WP;physicalDeliveryOfficeName;user"
    dsacls "OU=Cuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:WP;mail;user"

    # Lo mismo para OU NoCuates
    dsacls "OU=NoCuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:CA;Reset Password;user"
    dsacls "OU=NoCuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:CCDC;user"
    dsacls "OU=NoCuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:WP;telephoneNumber;user"
    dsacls "OU=NoCuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:WP;physicalDeliveryOfficeName;user"
    dsacls "OU=NoCuates,DC=empresa,DC=local" /G "EMPRESA\admin_identidad:WP;mail;user"

    # ROL 2: admin_storage
    # SOLO gestiona FSRM (cuotas y file screening)
    # Se le NIEGA explícitamente resetear contraseñas en TODO el dominio
    
    # Denegación explícita de reset password en ambas OUs
    dsacls "OU=Cuates,DC=empresa,DC=local" /D "EMPRESA\admin_storage:CA;Reset Password;user"
    dsacls "OU=NoCuates,DC=empresa,DC=local" /D "EMPRESA\admin_storage:CA;Reset Password;user"
    # También en la raíz del dominio por si acaso
    dsacls "DC=empresa,DC=local" /D "EMPRESA\admin_storage:CA;Reset Password;user"

    # ROL 3: admin_politicas
    # Lectura en TODO el dominio
    # Escritura SOLO sobre objetos GPO
    
    # Lectura general en el dominio
    dsacls "DC=empresa,DC=local" /G "EMPRESA\admin_politicas:GR"
    
    # Permisos sobre el contenedor de GPOs
    dsacls "CN=Policies,CN=System,DC=empresa,DC=local" /G "EMPRESA\admin_politicas:GRGWGX"
    
    # Permiso para vincular/desvincular GPOs en las OUs
    dsacls "OU=Cuates,DC=empresa,DC=local" /G "EMPRESA\admin_politicas:WP;gPLink"
    dsacls "OU=NoCuates,DC=empresa,DC=local" /G "EMPRESA\admin_politicas:WP;gPLink"

    # ROL 4: admin_auditoria
    # Solo lectura en todo el dominio, sin excepción
    
    dsacls "DC=empresa,DC=local" /G "EMPRESA\admin_auditoria:GR"

    # Permiso para leer los logs de seguridad (Event Viewer)
    # Esto se da agregándolo al grupo local "Event Log Readers"
    Add-LocalGroupMember -Group "Event Log Readers" -Member "EMPRESA\admin_auditoria"

    Write-Host "Permisos asignados correctamente a todos los admins delegados."
}
function extraer_accesos_denegados {

    $fechaHoy = Get-Date -Format "yyyy-MM-dd_HH-mm"
    $archivoSalida = "$PSScriptRoot\reporte_accesos_denegados_$fechaHoy.txt"

    # Extraer los últimos 10 eventos de login fallido (ID 4625)
    $eventos = Get-WinEvent -LogName "Security" -FilterXPath `
        "*[System[EventID=4625]]" -MaxEvents 10 -ErrorAction SilentlyContinue

    if (-not $eventos) {
        Write-Host "No se encontraron eventos de acceso denegado."
        return
    }

    # Escribir el reporte
    "REPORTE DE ACCESOS DENEGADOS - $fechaHoy" | Out-File $archivoSalida
    "================================================" | Out-File $archivoSalida -Append

    foreach ($evento in $eventos) {
        "Fecha/Hora : $($evento.TimeCreated)"          | Out-File $archivoSalida -Append
        "Usuario    : $($evento.Properties[5].Value)"  | Out-File $archivoSalida -Append
        "Equipo     : $($evento.MachineName)"          | Out-File $archivoSalida -Append
        "------------------------------------------------" | Out-File $archivoSalida -Append
    }

    Write-Host "Reporte generado en: $archivoSalida"
}
function configurar_auditoria {

    auditpol /set /subcategory:"Logon" /success:enable /failure:enable
    auditpol /set /subcategory:"Object Access" /success:enable /failure:enable
    
    auditpol /get /subcategory:"Logon"
    auditpol /get /subcategory:"Object Access"

    Write-Host "Auditoria configurada correctamente."
}

function configurar_FGPP {

    # Admins -> minimo 12 caracteres
    New-ADFineGrainedPasswordPolicy -Name "PSO-Admins" `
        -Precedence 10 `
        -MinPasswordLength 12 `
        -ComplexityEnabled $true `
        -PasswordHistoryCount 5 `
        -MaxPasswordAge "30.00:00:00" `
        -MinPasswordAge "1.00:00:00" `
        -LockoutThreshold 3 `
        -LockoutDuration "00:30:00" `
        -LockoutObservationWindow "00:30:00"

    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Admins" -Subjects "admin_identidad"
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Admins" -Subjects "admin_politicas"
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Admins" -Subjects "admin_storage"
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Admins" -Subjects "admin_auditoria"

    # Usuarios normales -> minimo 8 caracteres
    New-ADFineGrainedPasswordPolicy -Name "PSO-Usuarios" `
        -Precedence 20 `
        -MinPasswordLength 8 `
        -ComplexityEnabled $true `
        -PasswordHistoryCount 3 `
        -MaxPasswordAge "60.00:00:00" `
        -MinPasswordAge "1.00:00:00" `
        -LockoutThreshold 5 `
        -LockoutDuration "00:15:00" `
        -LockoutObservationWindow "00:15:00"

    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Usuarios" -Subjects "Cuates"
    Add-ADFineGrainedPasswordPolicySubject -Identity "PSO-Usuarios" -Subjects "NoCuates"

    Write-Host "Politicas FGPP configuradas correctamente."
}
