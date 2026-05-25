# parche_ssh_enrutamiento.ps1
# Ejecutar como Administrador en el Servidor

$sshdScript = "C:\ProgramData\ssh\multiotp_auth.ps1"

Write-Host "Modificando el script MFA para agregar enrutamiento automatico..." -ForegroundColor Cyan

$scriptContenido = @'
$exe     = "C:\Program Files\multiOTP\multiotp.exe"
$baseDir = "C:\Program Files\multiOTP"
$user    = $env:USERNAME.ToLower()

# Bypass para SCP/SFTP
$originalCmd = $env:SSH_ORIGINAL_COMMAND
if ($originalCmd -match "scp|sftp|rsync") {
    Invoke-Expression $originalCmd
    exit
}

$mapaUsuarios = @{
    "administrador"   = "administrator"
    "administrator"   = "administrator"
    "admin_identidad" = "admin_identidad"
    "admin_storage"   = "admin_storage"
    "admin_politicas" = "admin_politicas"
    "admin_auditoria" = "admin_auditoria"
}

$userMultiOTP = $mapaUsuarios[$user]
if (-not $userMultiOTP) { $userMultiOTP = $user }

Write-Output ""
Write-Output "  AUTENTIFICACION POR TOKEN REQUERIDA"
Write-Output "  Para el usuario: $user"
Write-Output "-----------------------------------------"
Write-Output ""
Write-Output "Ingresa tu codigo Autenticacion:"

$token = [Console]::ReadLine()

$p = New-Object System.Diagnostics.ProcessStartInfo
$p.FileName               = $exe
$p.Arguments              = "$userMultiOTP $token"
$p.WorkingDirectory       = $baseDir
$p.RedirectStandardOutput = $true
$p.RedirectStandardError  = $true
$p.UseShellExecute        = $false
$proc = [System.Diagnostics.Process]::Start($p)
$proc.WaitForExit()
$exitCode = $proc.ExitCode

if ($exitCode -eq 0) {
    Write-Output ""
    Write-Output "[OK] Token valido. Acceso concedido."
    Write-Output ""
    
    # --- NUEVA LOGICA DE ENRUTAMIENTO ---
    # Revisamos si existe su perfil V6 o su carpeta compartida
    $rutaPerfil = "C:\Perfiles\$user.v6"
    $rutaHome   = "C:\Shares\Usuarios\$user"
    
    if (Test-Path $rutaPerfil) {
        Write-Output ">> Enrutando a Perfil Movil: $rutaPerfil"
        Set-Location $rutaPerfil
    } elseif (Test-Path $rutaHome) {
        Write-Output ">> Enrutando a Carpeta de Red: $rutaHome"
        Set-Location $rutaHome
    } else {
        Write-Output ">> Enrutando a raiz del sistema..."
        Set-Location "C:\"
    }
    
    # Lanzamos PowerShell. Como usamos Set-Location antes, heredara esta ruta.
    & powershell.exe -NoExit -NoLogo
} else {
    Write-Output ""
    Write-Output "[-] Token invalido. Acceso denegado."
    Write-Output ""
    exit 1
}
'@

$scriptContenido | Out-File $sshdScript -Encoding UTF8 -Force
Write-Host "[+] Script de validacion actualizado exitosamente." -ForegroundColor Green
Write-Host "La proxima vez que un usuario entre por SSH, aparecera directamente en su carpeta." -ForegroundColor Yellow
