#Requires -RunAsAdministrator
Clear-Host
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " FASE 7: MFA VIA SSH + TOTP (DEFINITIVA)        " -ForegroundColor Cyan
Write-Host " Windows Server 2022 - Sin entorno grafico      " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# ----------------------------------------------------------
# VARIABLES BASE
# ----------------------------------------------------------
$RutaMSI      = "C:\temp\MFA_Install.msi"
$RutaMultiOTP = "C:\Program Files\multiOTP"
$ExeMultiOTP  = "$RutaMultiOTP\multiotp.exe"
$LogMSI       = "C:\mfa_install.log"
$VCDest       = "C:\vc_redist.x64.exe"
$sshdConfig   = "C:\ProgramData\ssh\sshd_config"
$sshdScript   = "C:\ProgramData\ssh\multiotp_auth.ps1"

# Usuarios a registrar en multiOTP con sus llaves Base32
# Llave del administrador ya registrada en Google Authenticator
$usuarios = @{
    "administrator"   = "JLDWY3DPEHPK3PXP"
    "admin_identidad" = "JLDWY3DPEHPK3PXA"
    "admin_storage"   = "JLDWY3DPEHPK3PXB"
    "admin_politicas" = "JLDWY3DPEHPK3PXC"
    "admin_auditoria" = "JLDWY3DPEHPK3PXD"
}

# ----------------------------------------------------------
# PASO 1: Verificar instalador MSI
# ----------------------------------------------------------
Write-Host "`n> 1. Verificando instalador MSI..." -ForegroundColor Yellow

if (-not (Test-Path $RutaMSI)) {
    Write-Host "  [-] No se encontro el instalador en: $RutaMSI" -ForegroundColor Red
    exit
}
Write-Host "  [+] Instalador encontrado." -ForegroundColor Green

# ----------------------------------------------------------
# PASO 2: Instalar Visual C++ Redistributable x64
# APRENDIDO: Sin esto el MSI falla con error 1603
# ----------------------------------------------------------
Write-Host "`n> 2. Verificando Visual C++ Redistributable x64..." -ForegroundColor Yellow

$vcInstalado = Get-ItemProperty `
    "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" `
    -ErrorAction SilentlyContinue

if ($vcInstalado -and $vcInstalado.Installed -eq 1) {
    Write-Host "  [+] VC++ ya instalado (version $($vcInstalado.Version))." -ForegroundColor Green
} else {
    Write-Host "  [!] VC++ no encontrado. Descargando..." -ForegroundColor Yellow
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest `
            -Uri     "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
            -OutFile $VCDest `
            -UseBasicParsing
        Write-Host "  [+] Descarga completada." -ForegroundColor Green
    } catch {
        Write-Host "  [-] Error: $($_.Exception.Message)" -ForegroundColor Red
        exit
    }

    $vcResult = Start-Process $VCDest `
        -ArgumentList "/install /quiet /norestart" `
        -Wait -PassThru

    switch ($vcResult.ExitCode) {
        0    { Write-Host "  [+] VC++ instalado." -ForegroundColor Green }
        3010 { Write-Host "  [+] VC++ instalado (reinicio pendiente, continuamos)." -ForegroundColor Green }
        default {
            Write-Host "  [-] VC++ fallo: $($vcResult.ExitCode)" -ForegroundColor Red
            exit
        }
    }
    Start-Sleep -Seconds 5
}

# ----------------------------------------------------------
# PASO 3: Instalar motor multiOTP
# ----------------------------------------------------------
Write-Host "`n> 3. Instalando motor multiOTP..." -ForegroundColor Yellow

if (Test-Path $LogMSI) { Remove-Item $LogMSI -Force }

Start-Process "msiexec.exe" `
    -ArgumentList "/i `"$RutaMSI`" /quiet /norestart /L*V `"$LogMSI`"" `
    -Wait

Start-Sleep -Seconds 3

$hayError = Get-Content $LogMSI -ErrorAction SilentlyContinue |
            Where-Object { $_ -match "Return value 3|error 1603|Installation failed" }

if ($hayError) {
    Write-Host "  [-] MSI reporto errores:" -ForegroundColor Red
    $hayError | Select-Object -First 3 |
        ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    exit
}

if (-not (Test-Path $ExeMultiOTP)) {
    Write-Host "  [-] multiotp.exe no encontrado." -ForegroundColor Red
    exit
}
Write-Host "  [+] Motor multiOTP instalado." -ForegroundColor Green

# ----------------------------------------------------------
# PASO 4: Dar permisos a la carpeta de multiOTP
# APRENDIDO: En contexto SSH el proceso corre como usuario
# de dominio y necesita permisos de lectura/escritura en
# la carpeta users para leer los archivos .db
# ----------------------------------------------------------
Write-Host "`n> 4. Aplicando permisos en carpeta multiOTP..." -ForegroundColor Yellow

icacls $RutaMultiOTP /grant "Todos:(OI)(CI)F" /T 2>$null | Out-Null
Write-Host "  [+] Permisos aplicados a: $RutaMultiOTP" -ForegroundColor Green

# ----------------------------------------------------------
# PASO 5: Sincronizar reloj del servidor
# APRENDIDO: TOTP depende del tiempo. Si el reloj difiere
# mas de 30 segundos el token siempre falla con ExitCode 99
# Se configura permanentemente en el registro para que
# sobreviva reinicios del servidor.
# ----------------------------------------------------------
Write-Host "`n> 5. Sincronizando reloj del servidor..." -ForegroundColor Yellow

# Configurar NTP permanente en el registro
Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
    -Name "NtpServer" -Value "time.google.com,0x8"
Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" `
    -Name "Type" -Value "NTP"

# Configurar intervalo de sincronizacion cada hora
Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient" `
    -Name "SpecialPollInterval" -Value 3600 -ErrorAction SilentlyContinue

w32tm /config /manualpeerlist:"time.google.com,0x8" /syncfromflags:manual /reliable:YES /update 2>$null | Out-Null
net stop w32tm  2>$null | Out-Null
net start w32tm 2>$null | Out-Null
w32tm /resync /force 2>$null | Out-Null
Start-Sleep -Seconds 3

$syncStatus = w32tm /query /status 2>$null
if ($syncStatus -match "Capa: [2-9]|Stratum: [2-9]") {
    Write-Host "  [+] Reloj sincronizado con time.google.com." -ForegroundColor Green
} else {
    Write-Host "  [!] Sincronizacion pendiente, continuando..." -ForegroundColor Yellow
}

# ----------------------------------------------------------
# PASO 6: Crear usuarios TOTP en multiOTP
# APRENDIDO:
# - Borrar .db antes de crear (evita "User already exists")
# - Usar -createga (acepta Base32, no usar -create)
# - Configurar bloqueo global
# ----------------------------------------------------------
Write-Host "`n> 6. Configurando usuarios TOTP en multiOTP..." -ForegroundColor Yellow

# Configuracion global de bloqueo
& $ExeMultiOTP -config max-block-failures=3      2>$null
& $ExeMultiOTP -config failure-delayed-time=1800  2>$null

foreach ($u in $usuarios.GetEnumerator()) {
    $nombre = $u.Key
    $llave  = $u.Value
    $dbPath = "$RutaMultiOTP\users\$nombre.db"

    # Borrar .db anterior si existe
    if (Test-Path $dbPath) {
        Remove-Item $dbPath -Force
    }

    # Crear usuario con -createga
    & $ExeMultiOTP -createga $nombre $llave 2>$null
    Start-Sleep -Seconds 1

    # Sin PIN adicional
    & $ExeMultiOTP -set $nombre prefix-pin=0 2>$null

    # Verificar con ProcessStartInfo
    $p = New-Object System.Diagnostics.ProcessStartInfo
    $p.FileName               = $ExeMultiOTP
    $p.Arguments              = "-user-info $nombre"
    $p.WorkingDirectory       = $RutaMultiOTP
    $p.RedirectStandardOutput = $true
    $p.RedirectStandardError  = $true
    $p.UseShellExecute        = $false
    $proc = [System.Diagnostics.Process]::Start($p)
    $proc.WaitForExit()

    if ($proc.ExitCode -eq 19) {
        Write-Host "  [+] $nombre | Llave: $llave" -ForegroundColor Green
    } else {
        Write-Host "  [-] Error creando $nombre (ExitCode: $($proc.ExitCode))" -ForegroundColor Red
    }
}

# ----------------------------------------------------------
# PASO 7: Probar token del administrador
# APRENDIDO: Usar ProcessStartInfo con WorkingDirectory
# para capturar ExitCode correctamente
# ----------------------------------------------------------
Write-Host "`n> 7. Prueba del token principal (administrator)..." -ForegroundColor Yellow
Write-Host "  Abre Google Authenticator. Llave: $($usuarios['administrator'])" -ForegroundColor Cyan
Write-Host "  Espera a que el codigo cambie y usalo." -ForegroundColor Yellow
$token = Read-Host "  Codigo de 6 digitos"

$p = New-Object System.Diagnostics.ProcessStartInfo
$p.FileName               = $ExeMultiOTP
$p.Arguments              = "administrator $token"
$p.WorkingDirectory       = $RutaMultiOTP
$p.RedirectStandardOutput = $true
$p.RedirectStandardError  = $true
$p.UseShellExecute        = $false
$proc = [System.Diagnostics.Process]::Start($p)
$proc.WaitForExit()
$exitCode = $proc.ExitCode

Write-Host "  ExitCode: $exitCode" -ForegroundColor DarkGray

if ($exitCode -eq 0) {
    Write-Host "  [OK] Token valido." -ForegroundColor Green
} else {
    Write-Host "  [-] Token invalido (ExitCode: $exitCode)." -ForegroundColor Red
    Write-Host "  [!] Verifica la llave y el reloj antes de continuar." -ForegroundColor Yellow
    Write-Host "      Ejecuta: w32tm /resync /force" -ForegroundColor Yellow
    exit
}

# ----------------------------------------------------------
# PASO 8: Verificar OpenSSH
# ----------------------------------------------------------
Write-Host "`n> 8. Verificando OpenSSH Server..." -ForegroundColor Yellow

$ssh = Get-WindowsCapability -Online |
       Where-Object Name -like 'OpenSSH.Server*'

if ($ssh.State -ne "Installed") {
    Write-Host "  [!] Instalando OpenSSH..." -ForegroundColor Yellow
    Add-WindowsCapability -Online -Name $ssh.Name | Out-Null
}

Set-Service sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue
Write-Host "  [+] OpenSSH activo." -ForegroundColor Green

# ----------------------------------------------------------
# PASO 9: Crear script de validacion MFA para SSH
# APRENDIDO:
# - [Console]::ReadLine() en lugar de Read-Host
#   (Read-Host falla en modo no interactivo de SSH)
# - WorkingDirectory = $RutaMultiOTP
#   (sin esto ExitCode 21 "User doesn't exist")
# - Mapeo administrador -> administrator
#   (Windows en español usa "administrador")
# - Permisos Todos:F en carpeta multiOTP
#   (sin esto ExitCode 99 en contexto SSH)
# - SCP bypass via SSH_ORIGINAL_COMMAND
# ----------------------------------------------------------
Write-Host "`n> 9. Creando script de validacion MFA..." -ForegroundColor Yellow

$scriptContenido = @'
$exe     = "C:\Program Files\multiOTP\multiotp.exe"
$baseDir = "C:\Program Files\multiOTP"
$user    = $env:USERNAME.ToLower()

# Bypass para SCP/SFTP - no pedir token en transferencias
$originalCmd = $env:SSH_ORIGINAL_COMMAND
if ($originalCmd -match "scp|sftp|rsync") {
    Invoke-Expression $originalCmd
    exit
}

# Mapeo Windows -> multiOTP
# "administrador" es el nombre en espanol de "administrator"
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
Write-Output "============================================"
Write-Output "  AUTENTICACION MFA REQUERIDA"
Write-Output "  Usuario: $user"
Write-Output "============================================"
Write-Output ""
Write-Output "Ingresa tu codigo de Google Authenticator:"

# [Console]::ReadLine() funciona en modo no interactivo SSH
# Read-Host NO funciona y lanza PSInvalidOperationException
$token = [Console]::ReadLine()

# WorkingDirectory es CRITICO - sin esto ExitCode 21/99
# en contexto SSH aunque el usuario exista
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
    & powershell.exe -NoLogo
} else {
    Write-Output ""
    Write-Output "[-] Token invalido. Acceso denegado."
    Write-Output ""
    exit 1
}
'@

Remove-Item $sshdScript -Force -ErrorAction SilentlyContinue
$scriptContenido | Out-File $sshdScript -Encoding UTF8 -Force
Write-Host "  [+] Script creado en: $sshdScript" -ForegroundColor Green

# ----------------------------------------------------------
# PASO 10: Configurar sshd_config con ForceCommand
# ----------------------------------------------------------
Write-Host "`n> 10. Configurando sshd_config..." -ForegroundColor Yellow

if (-not (Test-Path $sshdConfig)) {
    New-Item -Path (Split-Path $sshdConfig) -ItemType Directory -Force | Out-Null
    @"
Port 22
PasswordAuthentication yes
PubkeyAuthentication yes
"@ | Out-File $sshdConfig -Encoding UTF8
}

$config = Get-Content $sshdConfig -Raw
$config = $config -replace "(?m)^\s*ForceCommand.*(\r?\n)?", ""
$config = $config -replace "(?m)^\s*# MFA.*(\r?\n)?", ""

$forceCmd = "`n# MFA multiOTP - Token TOTP requerido en cada conexion SSH`nForceCommand powershell.exe -ExecutionPolicy Bypass -NonInteractive -File `"$sshdScript`"`n"
($config.TrimEnd() + $forceCmd) | Out-File $sshdConfig -Encoding UTF8 -Force
Write-Host "  [+] ForceCommand configurado." -ForegroundColor Green

# ----------------------------------------------------------
# PASO 11: Firewall y reinicio SSH
# ----------------------------------------------------------
Write-Host "`n> 11. Firewall y reinicio SSH..." -ForegroundColor Yellow

$regla = Get-NetFirewallRule -DisplayName "SSH-MFA-22" -ErrorAction SilentlyContinue
if (-not $regla) {
    New-NetFirewallRule `
        -DisplayName "SSH-MFA-22" `
        -Direction   Inbound `
        -Protocol    TCP `
        -LocalPort   22 `
        -Action      Allow | Out-Null
}

Restart-Service sshd -Force
Start-Sleep -Seconds 2
Write-Host "  [+] SSH estado: $((Get-Service sshd).Status)" -ForegroundColor Green

# ----------------------------------------------------------
# PASO 12: Verificacion final
# ----------------------------------------------------------
Write-Host "`n> 12. Verificacion final..." -ForegroundColor Yellow

$checks = [ordered]@{
    "Motor multiotp.exe"          = (Test-Path $ExeMultiOTP)
    "Permisos carpeta multiOTP"   = ((icacls $RutaMultiOTP 2>$null) -match "Todos")
    "Token administrador valido"  = ($exitCode -eq 0)
    "Script MFA creado"           = (Test-Path $sshdScript)
    "ForceCommand en sshd_config" = ((Get-Content $sshdConfig -Raw) -match "ForceCommand")
    "SSH corriendo"               = ((Get-Service sshd).Status -eq "Running")
}

$todoOK = $true
foreach ($c in $checks.GetEnumerator()) {
    if ($c.Value) {
        Write-Host "  [OK]    $($c.Key)" -ForegroundColor Green
    } else {
        Write-Host "  [FALLO] $($c.Key)" -ForegroundColor Red
        $todoOK = $false
    }
}

Write-Host "`n=================================================" -ForegroundColor Cyan
if ($todoOK) {
    Write-Host " FASE 7 COMPLETADA EXITOSAMENTE                 " -ForegroundColor Green
} else {
    Write-Host " FASE 7 COMPLETADA CON ERRORES                  " -ForegroundColor Red
}
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " Usuarios y llaves para Google Authenticator:   " -ForegroundColor White
Write-Host "   Administrador  : JLDWY3DPEHPK3PXP            " -ForegroundColor DarkGray
Write-Host "   admin_identidad: JLDWY3DPEHPK3PXA            " -ForegroundColor DarkGray
Write-Host "   admin_storage  : JLDWY3DPEHPK3PXB            " -ForegroundColor DarkGray
Write-Host "   admin_politicas: JLDWY3DPEHPK3PXC            " -ForegroundColor DarkGray
Write-Host "   admin_auditoria: JLDWY3DPEHPK3PXD            " -ForegroundColor DarkGray
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " Para conectarte:" -ForegroundColor White
Write-Host "   ssh Administrador@<IP>                       " -ForegroundColor DarkGray
Write-Host "   ssh admin_identidad@<IP>                     " -ForegroundColor DarkGray
Write-Host "=================================================" -ForegroundColor Cyan
