$sshdConfig = "C:\ProgramData\ssh\sshd_config"
$sshdScript = "C:\ProgramData\ssh\multiotp_auth.ps1"

# Leer config actual
$config = Get-Content $sshdConfig -Raw

# Eliminar ForceCommand y bloque Match anteriores
$config = $config -replace "(?m)^\s*# MFA.*(\r?\n)?", ""
$config = $config -replace "(?m)^\s*ForceCommand.*(\r?\n)?", ""
$config = $config -replace "(?s)Match Group administrators.*", ""

# Agregar configuracion correcta al final
$nuevaConfig = @"

# MFA multiOTP - Token TOTP requerido en cada conexion SSH
ForceCommand powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "$sshdScript"

# Grupo administrators - MFA obligatorio tambien para admins
Match Group administrators
    AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
    ForceCommand powershell.exe -ExecutionPolicy Bypass -NonInteractive -File "$sshdScript"
"@

($config.TrimEnd() + $nuevaConfig) | Out-File $sshdConfig -Encoding UTF8 -Force

Restart-Service sshd -Force
Write-Host "[+] sshd_config corregido. ForceCommand activo para todos." -ForegroundColor Green

# Verificar
Write-Host "`nContenido relevante del sshd_config:" -ForegroundColor Cyan
Get-Content $sshdConfig | Where-Object { $_ -match "ForceCommand|Match" }
