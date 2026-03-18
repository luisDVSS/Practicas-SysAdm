# ============================================================
#  prep_repo.ps1  -  Practica 7 (Windows Server 2022)
#  Descarga los binarios reales de Apache/Nginx,
#  genera sus .sha256 y pobla el repositorio FTP.
#  Ejecutar UNA VEZ antes de usar main.ps1
# ============================================================

#Requires -RunAsAdministrator

$REPO_BASE = "C:\srv\ftp\repo"
$TEMP_DIR  = "C:\Temp\practica7\downloads"

# ── URLs de descarga ──────────────────────────────────────────
# Apache: apachelounge.com requiere header Referer para no bloquear
#         Revisar ultima version en: https://www.apachelounge.com/download/
# Nginx : binario oficial Windows nginx.org
$URLS = @{
    "IIS"      = $null
    "Apache"   = "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.65-250724-Win64-VS17.zip"
    "Nginx"    = "https://nginx.org/download/nginx-1.26.3.zip"
    "VCredist" = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
}

Write-Host "======================================================"
Write-Host "  Preparando repositorio FTP para Practica 7"
Write-Host "======================================================"

# ── Verificacion de conectividad ─────────────────────────────
Write-Host ""
Write-Host "  Verificando conectividad..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($h in @("www.apachelounge.com", "nginx.org", "aka.ms")) {
    $ping = Test-Connection -ComputerName $h -Count 1 -Quiet -ErrorAction SilentlyContinue
    $estado = if ($ping) { "[OK]" } else { "[SIN PING - puede ser normal si ICMP bloqueado]" }
    Write-Host "    $estado $h"
}
Write-Host ""

# ── Crear estructura de directorios ──────────────────────────
$dirs = @(
    "$REPO_BASE\http\Windows\IIS",
    "$REPO_BASE\http\Windows\Apache",
    "$REPO_BASE\http\Windows\Nginx"
)
foreach ($d in $dirs) {
    if (-not (Test-Path $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Write-Host "  [OK] Creado: $d"
    }
}
if (-not (Test-Path $TEMP_DIR)) {
    New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null
}

# ── Helper: validar que un archivo es un ZIP real ─────────────
function Validar-ZIP {
    param([string]$Ruta)
    if (-not (Test-Path $Ruta)) { return $false }
    $tamano = (Get-Item $Ruta).Length
    if ($tamano -lt 500KB) { return $false }
    try {
        $bytes = New-Object byte[] 4
        $fs = [System.IO.File]::OpenRead($Ruta)
        $fs.Read($bytes, 0, 4) | Out-Null
        $fs.Close()
        return ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B -and
                $bytes[2] -eq 0x03 -and $bytes[3] -eq 0x04)
    } catch { return $false }
}

# ── Funcion principal de descarga ─────────────────────────────
# Apachelounge requiere: User-Agent de navegador real + header Referer.
# Sin Referer devuelve una pagina HTML de ~2 KB en lugar del ZIP.
function Descargar-Archivo {
    param([string]$URL, [string]$Destino)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (Test-Path $Destino) { Remove-Item $Destino -Force }

    # Intento 1: Invoke-WebRequest con Referer
    try {
        $headers = @{
            "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"
            "Referer"    = "https://www.apachelounge.com/download/"
            "Accept"     = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        }
        Invoke-WebRequest -Uri $URL -OutFile $Destino `
            -Headers $headers -UseBasicParsing -MaximumRedirection 10 `
            -ErrorAction Stop
        return $true
    } catch {
        Write-Host "    [INFO] Invoke-WebRequest: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Intento 2: WebClient con Referer
    try {
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0")
        $wc.Headers.Add("Referer",    "https://www.apachelounge.com/download/")
        $wc.DownloadFile($URL, $Destino)
        $wc.Dispose()
        return $true
    } catch {
        Write-Host "    [INFO] WebClient: $($_.Exception.Message)" -ForegroundColor Yellow
        try { $wc.Dispose() } catch {}
    }

    # Intento 3: curl.exe del sistema (incluido en Windows Server 2022)
    $curlExe = "$env:SystemRoot\System32\curl.exe"
    if (Test-Path $curlExe) {
        try {
            & $curlExe -L -o $Destino `
                -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" `
                -H "Referer: https://www.apachelounge.com/download/" `
                --retry 3 --retry-delay 2 --silent --show-error $URL
            if ($LASTEXITCODE -eq 0) { return $true }
            Write-Host "    [INFO] curl.exe codigo de salida: $LASTEXITCODE" -ForegroundColor Yellow
        } catch {
            Write-Host "    [INFO] curl.exe: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    return $false
}

# ── Funcion: descargar paquete, validar y generar .sha256 ─────
function Descargar-Paquete {
    param([string]$Nombre, [string]$URL, [string]$DestinoDir)

    Write-Host ""
    Write-Host "  Descargando $Nombre ..."
    Write-Host "  URL: $URL"

    $nombreArchivo = $URL.Split("/")[-1]
    $tempPath      = "$TEMP_DIR\$nombreArchivo"
    $destPath      = "$DestinoDir\$nombreArchivo"

    if (Test-Path $destPath)          { Remove-Item $destPath          -Force }
    if (Test-Path "$destPath.sha256") { Remove-Item "$destPath.sha256" -Force }

    $ok = Descargar-Archivo -URL $URL -Destino $tempPath
    if (-not $ok) {
        Write-Host "  [ERROR] Todos los metodos de descarga fallaron para $Nombre." -ForegroundColor Red
        Write-Host "  --> Descarga manualmente el archivo desde:" -ForegroundColor Yellow
        Write-Host "      $URL"
        Write-Host "      y coloca el ZIP en: $DestinoDir\"
        Write-Host "      Luego genera el hash:"
        Write-Host "      `$h = (Get-FileHash '$DestinoDir\$nombreArchivo' -Algorithm SHA256).Hash.ToLower()"
        Write-Host "      `$h | Set-Content '$DestinoDir\$nombreArchivo.sha256' -Encoding ASCII -NoNewline"
        return $false
    }

    # Validar que no es una pagina HTML de error (problema tipico de apachelounge)
    $tamano = (Get-Item $tempPath -ErrorAction SilentlyContinue).Length
    if ($tamano -lt 500KB) {
        $primeros = ""
        try {
            $rawBytes = [System.IO.File]::ReadAllBytes($tempPath)
            $primeros = [System.Text.Encoding]::UTF8.GetString($rawBytes[0..([Math]::Min(200, $rawBytes.Length - 1))])
        } catch {}
        Write-Host "  [ERROR] Descarga incompleta o bloqueada ($tamano bytes)." -ForegroundColor Red
        Write-Host "          Primeros bytes: $primeros" -ForegroundColor Yellow
        Write-Host "  --> Descarga manualmente:" -ForegroundColor Yellow
        Write-Host "      $URL"
        Write-Host "      Guarda en: $DestinoDir\$nombreArchivo"
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    $ext = [System.IO.Path]::GetExtension($nombreArchivo).ToLower()
    if ($ext -eq ".zip" -and -not (Validar-ZIP -Ruta $tempPath)) {
        Write-Host "  [ERROR] El archivo descargado no tiene firma ZIP valida." -ForegroundColor Red
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        return $false
    }

    Copy-Item $tempPath $destPath -Force

    $hash = (Get-FileHash -Path $destPath -Algorithm SHA256).Hash.ToLower()
    $hash | Set-Content "$destPath.sha256" -Encoding ASCII -NoNewline

    Write-Host "  [OK] $nombreArchivo  ($([math]::Round($tamano/1MB,1)) MB)" -ForegroundColor Green
    Write-Host "       SHA256: $hash"
    return $true
}

# ── IIS: marcador informativo ─────────────────────────────────
$iisInfo = "$REPO_BASE\http\Windows\IIS\IIS-WindowsServer2022.info"
@"
IIS se instala como rol de Windows Server, no como archivo descargable.
Para instalar usa main.ps1 opcion 1 (instalacion via WEB).
Rol principal : Web-Server
Comando       : Install-WindowsFeature -Name Web-Server -IncludeManagementTools
"@ | Set-Content $iisInfo -Encoding UTF8
Write-Host "  [OK] Marcador IIS: $iisInfo"

# ── Visual C++ Redistributable ────────────────────────────────
Write-Host ""
Write-Host "  Descargando Visual C++ Redistributable (requerido por Apache)..."
$vcDest = "$REPO_BASE\http\Windows\Apache\vc_redist.x64.exe"
$okVc   = Descargar-Archivo -URL $URLS["VCredist"] -Destino $vcDest
$vcSize = (Get-Item $vcDest -ErrorAction SilentlyContinue).Length
if ($okVc -and $vcSize -gt 1MB) {
    $hashVc = (Get-FileHash -Path $vcDest -Algorithm SHA256).Hash.ToLower()
    $hashVc | Set-Content "$vcDest.sha256" -Encoding ASCII -NoNewline
    Write-Host "  [OK] vc_redist.x64.exe ($([math]::Round($vcSize/1MB,1)) MB)" -ForegroundColor Green
} else {
    Write-Host "  [ADVERTENCIA] VCredist no descargado correctamente." -ForegroundColor Yellow
    Write-Host "               Descarga manual: https://aka.ms/vs/17/release/vc_redist.x64.exe"
}

# ── Apache ────────────────────────────────────────────────────
$okApache = Descargar-Paquete -Nombre "Apache httpd VS17" `
    -URL $URLS["Apache"] -DestinoDir "$REPO_BASE\http\Windows\Apache"

# ── Nginx ─────────────────────────────────────────────────────
$okNginx = Descargar-Paquete -Nombre "Nginx" `
    -URL $URLS["Nginx"] -DestinoDir "$REPO_BASE\http\Windows\Nginx"

# ── Permisos para usuario repo ────────────────────────────────
$repoUser = Get-LocalUser -Name "repo" -ErrorAction SilentlyContinue
if ($repoUser) {
    $acl  = Get-Acl $REPO_BASE
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "repo", "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.SetAccessRule($rule)
    Set-Acl -Path $REPO_BASE -AclObject $acl
    Write-Host ""
    Write-Host "  [OK] Permisos de lectura asignados al usuario 'repo'."
}

# ── Resumen ───────────────────────────────────────────────────
Write-Host ""
Write-Host "======================================================"
Write-Host "  Repositorio en: $REPO_BASE"
Write-Host "  Archivos:"
Get-ChildItem -Path $REPO_BASE -Recurse -File |
    Select-Object FullName, @{N="MB";E={[math]::Round($_.Length/1MB,2)}} |
    ForEach-Object { Write-Host "    $($_.FullName)  ($($_.MB) MB)" }
Write-Host ""
if (-not $okApache) {
    Write-Host "  [!!] Apache NO descargado automaticamente." -ForegroundColor Red
    Write-Host "       Descarga manual necesaria:"
    Write-Host "       1) Abre en el navegador: $($URLS['Apache'])"
    Write-Host "       2) Guarda el ZIP en: $REPO_BASE\http\Windows\Apache\"
    Write-Host "       3) Genera el hash:"
    Write-Host "          `$h=(Get-FileHash '$REPO_BASE\http\Windows\Apache\httpd-2.4.65-250724-Win64-VS17.zip' -Algorithm SHA256).Hash.ToLower()"
    Write-Host "          `$h | Set-Content '$REPO_BASE\http\Windows\Apache\httpd-2.4.65-250724-Win64-VS17.zip.sha256' -Encoding ASCII -NoNewline"
}
Write-Host "======================================================"