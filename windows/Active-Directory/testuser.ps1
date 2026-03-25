New-ADUser -Name "userNoPad" `
           -SamAccountName "usernopad" `
           -AccountPassword (ConvertTo-SecureString "Luisito55dmkk_123" -AsPlainText -Force) `
           -Path "OU=NoCuates,DC=empresa,DC=local" `
           -Enabled $true

# Horario ilimitado - todos los dias todas las horas
$bytesIlimitado = [byte[]](
    255,255,255, 255,255,255,
    255,255,255, 255,255,255,
    255,255,255, 255,255,255,
    255,255,255
)

Set-ADUser -Identity "usernopad" -Replace @{logonHours = $bytesIlimitado}
