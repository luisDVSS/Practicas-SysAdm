# ============================================================
#  http.ps1  -  Practica 7 (Windows Server 2022)
#  Instala Apache y Nginx desde FTP o internet, con HTTPS
# ============================================================
#Requires -RunAsAdministrator

. "$PSScriptRoot\config.ps1"

# ════════════════════════════════════════════════════════════
#  CLIENTE FTP
# ════════════════════════════════════════════════════════════

$script:FtpHost = ""
$script:FtpUser = ""
$script:FtpPass = ""
$script:FtpSsl  = $false

function Connect-FtpRepo {
    Write-Host "`n=== Conexion al repositorio FTP ===" -ForegroundColor Cyan
    $script:FtpHost = Read-Host "  IP del servidor FTP"
    $script:FtpUser = Read-Host "  Usuario"
    $sec            = Read-Host "  Contrasena" -AsSecureString
    $script:FtpPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    )
    $modoSsl       = Read-Host "  Usar FTPS (SSL)? [s/N]"
    $script:FtpSsl = $modoSsl -match '^[sS]$'
    Write-Host "  Modo: $(if ($script:FtpSsl) { 'FTPS (SSL)' } else { 'FTP plain' })" -ForegroundColor Cyan

    if (-not (Test-Path $CFG_DOWNLOAD_DIR)) {
        New-Item -ItemType Directory -Path $CFG_DOWNLOAD_DIR -Force | Out-Null
    }
}

function New-FtpReq {
    param([string]$Uri, [string]$Metodo, [bool]$Ssl)
    $req                  = [System.Net.FtpWebRequest]::Create($Uri)
    $req.Method           = $Metodo
    $req.Credentials      = New-Object System.Net.NetworkCredential($script:FtpUser, $script:FtpPass)
    $req.EnableSsl        = $Ssl
    $req.UsePassive       = $true
    $req.UseBinary        = $true
    $req.Timeout          = 30000
    $req.ReadWriteTimeout = 120000
    if ($Ssl) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }
    return $req
}

function Get-FtpListing {
    param([string]$Ruta)
    $uri = "ftp://$($script:FtpHost)$Ruta/"
    try {
        $req    = New-FtpReq -Uri $uri -Metodo ([Net.WebRequestMethods+Ftp]::ListDirectory) -Ssl $script:FtpSsl
        $resp   = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $text   = $reader.ReadToEnd()
        $reader.Close(); $resp.Close()
        return ($text -split "`n" | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -ne "" -and $_ -notmatch "^\." })
    } catch {
        $msg = $_.Exception.Message
        if     ($msg -match "530") { Write-Host "  [ERROR] Credenciales rechazadas (530)." -ForegroundColor Red }
        elseif ($msg -match "550") { Write-Host "  [ERROR] Ruta no encontrada: $Ruta" -ForegroundColor Red }
        else {
            Write-Host "  [ERROR] No se pudo listar $Ruta" -ForegroundColor Red
            Write-Host "          $msg" -ForegroundColor DarkRed
        }
        return @()
    }
}

function Save-FtpFile {
    param([string]$RutaRemota, [string]$LocalDest, [int]$MinBytes = 0)

    $uri         = "ftp://$($script:FtpHost)$RutaRemota"
    $nombreCorto = Split-Path $RutaRemota -Leaf
    Write-Host "  Descargando $nombreCorto ..." -NoNewline

    try {
        $req    = New-FtpReq -Uri $uri -Metodo ([Net.WebRequestMethods+Ftp]::DownloadFile) -Ssl $script:FtpSsl
        $resp   = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $file   = [System.IO.File]::Create($LocalDest)
        $stream.CopyTo($file)
        $file.Close(); $stream.Close(); $resp.Close()

        $bytes = (Get-Item $LocalDest -ErrorAction SilentlyContinue).Length
        if ($MinBytes -gt 0 -and $bytes -lt $MinBytes) {
            Write-Host " FALLO (demasiado pequeno: $bytes bytes)" -ForegroundColor Red
            Remove-Item $LocalDest -Force -ErrorAction SilentlyContinue
            return $false
        }
        Write-Host " OK ($([math]::Round($bytes/1KB,1)) KB)" -ForegroundColor Green
        return $true
    } catch {
        Write-Host " FALLO" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor DarkRed
        return $false
    }
}

function Test-FileIntegrity {
    param([string]$Archivo)
    $hashFile = "$Archivo.sha256"
    if (-not (Test-Path $hashFile)) {
        Write-Host "  [WARN] Sin .sha256, omitiendo verificacion." -ForegroundColor Yellow
        return $true
    }
    $esperado  = (Get-Content $hashFile -Raw).Trim().Split()[0].ToLower()
    $calculado = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    if ($esperado -eq $calculado) {
        Write-Host "  [OK] SHA256 verificado." -ForegroundColor Green
        return $true
    }
    Write-Host "  [ERROR] Hash no coincide - archivo corrupto." -ForegroundColor Red
    Write-Host "          Esperado : $esperado"
    Write-Host "          Calculado: $calculado"
    return $false
}

function Get-FromFtp {
    param([string]$Servicio)

    Connect-FtpRepo
    $rutaServicio = "$CFG_FTP_REPO_BASE/$Servicio"

    Write-Host "`n  Listando $rutaServicio ..."
    # Mostrar solo ZIPs (excluir .sha256, .exe, .info)
    $archivos = @(Get-FtpListing -Ruta $rutaServicio | Where-Object { $_ -match '\.zip$' })

    if ($archivos.Count -eq 0) {
        Write-Host "  [ERROR] No se encontraron ZIPs en $rutaServicio" -ForegroundColor Red
        return $null
    }

    Write-Host "  Archivos disponibles:"
    for ($i = 0; $i -lt $archivos.Count; $i++) { Write-Host "    $($i+1)) $($archivos[$i])" }

    do { $idx = Read-Host "  Selecciona [1-$($archivos.Count)]" }
    while ($idx -notmatch '^\d+$' -or [int]$idx -lt 1 -or [int]$idx -gt $archivos.Count)

    $archivo    = $archivos[[int]$idx - 1]
    $rutaRemota = "$rutaServicio/$archivo"
    $localBin   = "$CFG_DOWNLOAD_DIR\$archivo"

    # ZIP: minimo 1 MB
    $ok = Save-FtpFile -RutaRemota $rutaRemota -LocalDest $localBin -MinBytes 1MB
    if (-not $ok) { return $null }

    # .sha256: sin MinBytes (solo tiene 64 bytes)
    Save-FtpFile -RutaRemota "$rutaRemota.sha256" -LocalDest "$localBin.sha256" | Out-Null

    if (-not (Test-FileIntegrity -Archivo $localBin)) { return $null }

    return $localBin
}

# ════════════════════════════════════════════════════════════
#  HELPERS COMUNES
# ════════════════════════════════════════════════════════════

function Set-FirewallRule {
    param([string]$Nombre, [int]$Puerto)
    $ex = Get-NetFirewallRule -DisplayName $Nombre -ErrorAction SilentlyContinue
    if ($ex) { Remove-NetFirewallRule -DisplayName $Nombre }
    New-NetFirewallRule -DisplayName $Nombre -Direction Inbound `
        -Protocol TCP -LocalPort $Puerto -Action Allow | Out-Null
    Write-Host "  [OK] Firewall: puerto $Puerto abierto." -ForegroundColor Green
}

function Read-Port {
    param([int]$Default = 80, [string]$Label = "Puerto")
    $reservados = @(21, 22, 25, 53, 110, 143, 3389, 445)
    while ($true) {
        $raw = Read-Host "  $Label [default: $Default]"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $Default }
        if ($raw -match '^\d+$') {
            $p = [int]$raw
            if ($p -ge 1 -and $p -le 65535 -and $reservados -notcontains $p) { return $p }
        }
        Write-Host "  Puerto invalido o reservado." -ForegroundColor Yellow
    }
}

function New-IndexPage {
    param([string]$Servicio, [string]$Version, [int]$Puerto, [string]$Webroot, [bool]$Https = $false)
    if (-not (Test-Path $Webroot)) { New-Item -ItemType Directory -Path $Webroot -Force | Out-Null }
    $proto = if ($Https) { "HTTPS" } else { "HTTP" }
    @"
<!DOCTYPE html><html lang="es"><head><meta charset="UTF-8">
<title>$Servicio activo</title>
<style>body{font-family:monospace;display:flex;justify-content:center;align-items:center;
height:100vh;margin:0;background:#1a1a2e;color:#eee;}
.box{border:2px solid #0f3460;padding:40px 60px;text-align:center;}
h1{color:#e94560;} td{padding:6px 16px;} td:first-child{color:#aaa;}</style></head>
<body><div class="box"><h1>$Servicio</h1><table>
<tr><td>Version</td><td>$Version</td></tr>
<tr><td>Puerto</td><td>$Puerto</td></tr>
<tr><td>Protocolo</td><td>$proto</td></tr>
</table></div></body></html>
"@ | Set-Content "$Webroot\index.html" -Encoding UTF8
}

function Get-WebFile {
    param([string]$URL, [string]$Dest)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $headers = @{
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0"
        "Referer"    = "https://www.apachelounge.com/download/"
    }
    try {
        Invoke-WebRequest -Uri $URL -OutFile $Dest -Headers $headers `
            -UseBasicParsing -MaximumRedirection 10 -ErrorAction Stop
        return $true
    } catch {}
    $curl = "$env:SystemRoot\System32\curl.exe"
    if (Test-Path $curl) {
        & $curl -L -o $Dest -H "User-Agent: Mozilla/5.0" `
            -H "Referer: https://www.apachelounge.com/download/" --silent --show-error $URL
        return ($LASTEXITCODE -eq 0)
    }
    return $false
}

# ════════════════════════════════════════════════════════════
#  SSL - certificado autofirmado compartido Apache/Nginx
# ════════════════════════════════════════════════════════════

$CFG_SSL_DIR  = "C:\ssl\practica7"
$CFG_SSL_CRT  = "$CFG_SSL_DIR\server.crt"
$CFG_SSL_KEY  = "$CFG_SSL_DIR\server.key"
$CFG_SSL_PFX  = "$CFG_SSL_DIR\server.pfx"
$CFG_SSL_PASS = ConvertTo-SecureString "practica7ssl" -AsPlainText -Force

function New-SslCert {
    # Genera certificado autofirmado y exporta CRT+KEY en PEM para Apache/Nginx
    # Devuelve $true si el par esta listo

    if ((Test-Path $CFG_SSL_CRT) -and (Test-Path $CFG_SSL_KEY)) {
        Write-Host "  [OK] Certificado SSL ya existe en $CFG_SSL_DIR" -ForegroundColor Green
        return $true
    }

    Write-Host "  Generando certificado autofirmado..."
    if (-not (Test-Path $CFG_SSL_DIR)) { New-Item -ItemType Directory -Path $CFG_SSL_DIR -Force | Out-Null }

    # Crear en el store de Windows
    $cert = New-SelfSignedCertificate `
        -DnsName "localhost","127.0.0.1" `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddDays(365) `
        -KeyAlgorithm RSA -KeyLength 2048 `
        -FriendlyName "Practica7-SSL" `
        -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature,KeyEncipherment `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")

    # Exportar PFX
    Export-PfxCertificate -Cert $cert -FilePath $CFG_SSL_PFX -Password $CFG_SSL_PASS | Out-Null

    # Exportar CRT en PEM
    $derFile  = "$CFG_SSL_DIR\server.der"
    Export-Certificate -Cert $cert -FilePath $derFile -Type CERT | Out-Null
    $derBytes = [System.IO.File]::ReadAllBytes($derFile)
    $b64      = [Convert]::ToBase64String($derBytes)
    $pem      = "-----BEGIN CERTIFICATE-----`n"
    for ($i = 0; $i -lt $b64.Length; $i += 64) {
        $pem += $b64.Substring($i, [Math]::Min(64, $b64.Length - $i)) + "`n"
    }
    $pem += "-----END CERTIFICATE-----"
    $pem | Set-Content $CFG_SSL_CRT -Encoding ASCII

    # Exportar KEY en PEM
    # Estrategia: instalar openssl via winget (incluido en WS2022) si no esta disponible
    $opensslExe = "C:\Program Files\OpenSSL-Win64\bin\openssl.exe"
    $openssl    = Get-Command openssl -ErrorAction SilentlyContinue

    if (-not $openssl -and -not (Test-Path $opensslExe)) {
        Write-Host "  [INFO] Instalando OpenSSL via winget..." -ForegroundColor Yellow
        winget install -e --id ShiningLight.OpenSSL.Light `
            --accept-source-agreements --accept-package-agreements --silent 2>$null
    }

    # Refrescar PATH por si winget acaba de instalarlo
    if (-not $openssl) {
        $env:PATH = [System.Environment]::GetEnvironmentVariable("PATH","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("PATH","User")
        $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    }

    if ($openssl) {
        & openssl pkcs12 -in $CFG_SSL_PFX -nocerts -nodes `
            -out $CFG_SSL_KEY -passin "pass:practica7ssl" 2>$null
        Write-Host "  [OK] Clave exportada con openssl." -ForegroundColor Green
    } elseif (Test-Path $opensslExe) {
        & $opensslExe pkcs12 -in $CFG_SSL_PFX -nocerts -nodes `
            -out $CFG_SSL_KEY -passin "pass:practica7ssl" 2>$null
        Write-Host "  [OK] Clave exportada con openssl." -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] No se pudo instalar openssl automaticamente." -ForegroundColor Red
        Write-Host "          Instala manualmente: winget install ShiningLight.OpenSSL.Light" -ForegroundColor Yellow
        Write-Host "          Luego vuelve a ejecutar esta opcion." -ForegroundColor Yellow
        return $false
    }

    Write-Host "  [OK] CRT: $CFG_SSL_CRT" -ForegroundColor Green
    Write-Host "  [OK] KEY: $CFG_SSL_KEY" -ForegroundColor Green
    return $true
}

# ════════════════════════════════════════════════════════════
#  APACHE
# ════════════════════════════════════════════════════════════

function Install-Apache {
    param([int]$Puerto = 80, [string]$ZipLocal = "")

    Write-Host "`n======================================================" -ForegroundColor Cyan
    Write-Host "  Instalando Apache httpd en puerto $Puerto"
    Write-Host "======================================================"

    if (-not (Test-Path $CFG_TEMP_DIR)) { New-Item -ItemType Directory -Path $CFG_TEMP_DIR -Force | Out-Null }

    # ── Obtener ZIP ───────────────────────────────────────────
    $zipPath = "$CFG_TEMP_DIR\apache.zip"
    if ($ZipLocal -ne "" -and (Test-Path $ZipLocal)) {
        Write-Host "  Usando archivo local: $ZipLocal"
        Copy-Item $ZipLocal $zipPath -Force
    } else {
        Write-Host "  Descargando Apache desde internet..."
        if (-not (Get-WebFile -URL $CFG_APACHE_URL -Dest $zipPath)) {
            Write-Host "  [ERROR] No se pudo descargar Apache." -ForegroundColor Red; return
        }
    }

    # ── VCredist ──────────────────────────────────────────────
    $vcPath = "$CFG_TEMP_DIR\vc_redist.x64.exe"
    $vcSrc  = @("$CFG_DOWNLOAD_DIR\vc_redist.x64.exe",
                "$CFG_FTP_REPO\http\Windows\Apache\vc_redist.x64.exe",
                $vcPath) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($vcSrc -and $vcSrc -ne $vcPath) { Copy-Item $vcSrc $vcPath -Force }
    if (-not (Test-Path $vcPath)) {
        Write-Host "  Descargando Visual C++ Redistributable..."
        Get-WebFile -URL $CFG_VCREDIST_URL -Dest $vcPath | Out-Null
    }
    if (Test-Path $vcPath) {
        Write-Host "  Instalando VCredist..."
        Start-Process $vcPath -ArgumentList "/install /quiet /norestart" -Wait
        Write-Host "  [OK] VCredist instalado." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] VCredist no disponible. Apache puede no iniciar." -ForegroundColor Yellow
    }

    # ── Extraer ZIP ───────────────────────────────────────────
    $extractTemp = "$CFG_TEMP_DIR\apache_extract"
    if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
    New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null

    Write-Host "  Extrayendo ZIP..."
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractTemp -Force -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] Expand-Archive fallo: $_" -ForegroundColor Red; return
    }

    $src = Join-Path $extractTemp "Apache24"
    if (-not (Test-Path "$src\bin\httpd.exe")) {
        $found = Get-ChildItem $extractTemp -Recurse -Filter "httpd.exe" -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) { $src = $found.Directory.Parent.FullName }
        else { Write-Host "  [ERROR] httpd.exe no encontrado en el ZIP." -ForegroundColor Red; return }
    }

    # ── Mover a C:\Apache24 ───────────────────────────────────
    $dest = $CFG_APACHE_DIR
    if (Test-Path $dest) {
        Stop-Service $CFG_APACHE_SVC -Force -ErrorAction SilentlyContinue
        Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
    Move-Item $src $dest -Force
    Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path "$dest\bin\httpd.exe")) {
        Write-Host "  [ERROR] httpd.exe no encontrado en $dest." -ForegroundColor Red; return
    }
    Write-Host "  [OK] Apache extraido en $dest" -ForegroundColor Green

    Set-ApacheConf -Puerto $Puerto

    # ── Registrar y arrancar servicio ─────────────────────────
    $svc = Get-Service -Name $CFG_APACHE_SVC -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-Host "  Registrando servicio $CFG_APACHE_SVC ..."
        & "$dest\bin\httpd.exe" -k install 2>&1 | Out-Null
    }
    Start-Service $CFG_APACHE_SVC -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $status = (Get-Service $CFG_APACHE_SVC -ErrorAction SilentlyContinue).Status
    if ($status -eq "Running") {
        Write-Host "  [OK] Servicio $CFG_APACHE_SVC : Running" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Servicio no arranco. Revisa: $dest\logs\error.log" -ForegroundColor Yellow
    }

    $webroot = "$dest\htdocs\apache"
    $version = "2.4.x"
    try { $version = (& "$dest\bin\httpd.exe" -v 2>&1 | Select-String "Server version") -replace ".*Apache/","" -replace " .*","" } catch {}

    Set-FirewallRule -Nombre "Apache-HTTP-$Puerto" -Puerto $Puerto
    New-IndexPage -Servicio "Apache" -Version $version -Puerto $Puerto -Webroot $webroot
    Write-Host "  [OK] Apache instalado, puerto $Puerto." -ForegroundColor Green
}

function Set-ApacheConf {
    param([int]$Puerto, [bool]$Https = $false)

    $conf    = "$CFG_APACHE_DIR\conf\httpd.conf"
    $webroot = "$CFG_APACHE_DIR\htdocs\apache"
    $wr      = $webroot -replace "\\","/"

    if (-not (Test-Path $conf)) { Write-Host "  [ERROR] No se encontro $conf" -ForegroundColor Red; return }
    if (-not (Test-Path $webroot)) { New-Item -ItemType Directory -Path $webroot -Force | Out-Null }

    $c = Get-Content $conf -Raw

    # Puerto
    $c = $c -replace "(?m)^Listen \d+", "Listen $Puerto"

    # DocumentRoot
    $c = $c -replace 'DocumentRoot "[^"]*"', "DocumentRoot `"$wr`""

    # <Directory> — reemplazar la etiqueta de apertura solamente (evita el bug de comilla doble)
    # Cubre tanto rutas con htdocs como rutas ya modificadas
    $c = $c -replace '<Directory "(?:[^"]*htdocs[^"]*|[^"]*Apache24[^"]*)">', "<Directory `"$wr`">"

    if ($Https) {
        # Descomentar modulos SSL
        $c = $c -replace '#(LoadModule ssl_module)',          '$1'
        $c = $c -replace '#(LoadModule socache_shmcb_module)','$1'
        $c = $c -replace '#(Include conf/extra/httpd-ssl\.conf)', '$1'

        # Escribir httpd-ssl.conf
        $crt     = $CFG_SSL_CRT -replace "\\","/"
        $key     = $CFG_SSL_KEY -replace "\\","/"
        $sslConf = "$CFG_APACHE_DIR\conf\extra\httpd-ssl.conf"
        @"
<VirtualHost _default_:$Puerto>
    DocumentRoot "$wr"
    ServerName localhost:$Puerto
    SSLEngine on
    SSLCertificateFile    "$crt"
    SSLCertificateKeyFile "$key"
    SSLProtocol           all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite        HIGH:!aNULL:!MD5
    <Directory "$wr">
        Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
"@ | Set-Content $sslConf -Encoding UTF8
        Write-Host "  [OK] httpd-ssl.conf escrito." -ForegroundColor Green
    }

    $c | Set-Content $conf -Encoding UTF8

    # Validar sintaxis
    $test = & "$CFG_APACHE_DIR\bin\httpd.exe" -t 2>&1
    if ($test -match "Syntax OK") {
        Write-Host "  [OK] httpd.conf: Syntax OK" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Errores de sintaxis en httpd.conf:" -ForegroundColor Yellow
        $test | ForEach-Object { Write-Host "         $_" }
    }

    $svc = Get-Service $CFG_APACHE_SVC -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") { Restart-Service $CFG_APACHE_SVC -ErrorAction SilentlyContinue }
    Write-Host "  [OK] Apache configurado en puerto $Puerto" -ForegroundColor Green
}

function Enable-ApacheHttps {
    param([int]$Puerto = 443)

    Write-Host "`n=== Activando HTTPS en Apache (puerto $Puerto) ===" -ForegroundColor Cyan

    if (-not (Test-Path "$CFG_APACHE_DIR\bin\httpd.exe")) {
        Write-Host "  [ERROR] Apache no esta instalado." -ForegroundColor Red; return
    }
    if (-not (New-SslCert)) { return }

    Set-ApacheConf -Puerto $Puerto -Https $true
    Set-FirewallRule -Nombre "Apache-HTTPS-$Puerto" -Puerto $Puerto

    $webroot = "$CFG_APACHE_DIR\htdocs\apache"
    $version = "2.4.x"
    try { $version = (& "$CFG_APACHE_DIR\bin\httpd.exe" -v 2>&1 | Select-String "Server version") -replace ".*Apache/","" -replace " .*","" } catch {}
    New-IndexPage -Servicio "Apache" -Version $version -Puerto $Puerto -Webroot $webroot -Https $true

    $svc = Get-Service $CFG_APACHE_SVC -ErrorAction SilentlyContinue
    if ($svc) {
        Restart-Service $CFG_APACHE_SVC -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $status = (Get-Service $CFG_APACHE_SVC -ErrorAction SilentlyContinue).Status
        if ($status -eq "Running") {
            Write-Host "  [OK] Apache HTTPS activo en puerto $Puerto." -ForegroundColor Green
        } else {
            Write-Host "  [WARN] Apache no arranco. Revisa: $CFG_APACHE_DIR\logs\error.log" -ForegroundColor Yellow
        }
    }
}

# ════════════════════════════════════════════════════════════
#  NGINX
# ════════════════════════════════════════════════════════════

function Install-Nginx {
    param([int]$Puerto = 8080, [string]$ZipLocal = "")

    Write-Host "`n======================================================" -ForegroundColor Cyan
    Write-Host "  Instalando Nginx en puerto $Puerto"
    Write-Host "======================================================"

    if (-not (Test-Path $CFG_TEMP_DIR)) { New-Item -ItemType Directory -Path $CFG_TEMP_DIR -Force | Out-Null }

    $zipPath = "$CFG_TEMP_DIR\nginx.zip"
    if ($ZipLocal -ne "" -and (Test-Path $ZipLocal)) {
        Write-Host "  Usando archivo local: $ZipLocal"
        Copy-Item $ZipLocal $zipPath -Force
    } else {
        Write-Host "  Descargando Nginx desde internet..."
        if (-not (Get-WebFile -URL $CFG_NGINX_URL -Dest $zipPath)) {
            Write-Host "  [ERROR] No se pudo descargar Nginx." -ForegroundColor Red; return
        }
    }

    $extractTemp = "$CFG_TEMP_DIR\nginx_extract"
    if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
    New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null

    Write-Host "  Extrayendo ZIP..."
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractTemp -Force -ErrorAction Stop
    } catch {
        Write-Host "  [ERROR] Expand-Archive fallo: $_" -ForegroundColor Red; return
    }

    $src = Get-ChildItem $extractTemp -Directory | Where-Object { $_.Name -like "nginx*" } | Select-Object -First 1
    if (-not $src -or -not (Test-Path "$($src.FullName)\nginx.exe")) {
        $found = Get-ChildItem $extractTemp -Recurse -Filter "nginx.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $src = Get-Item $found.Directory.FullName }
        else { Write-Host "  [ERROR] nginx.exe no encontrado en el ZIP." -ForegroundColor Red; return }
    } else { $src = $src.FullName }

    $dest = $CFG_NGINX_DIR
    if (Test-Path $dest) {
        Stop-Service $CFG_NGINX_SVC -Force -ErrorAction SilentlyContinue
        Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
        Remove-Item $dest -Recurse -Force -ErrorAction SilentlyContinue
    }
    Move-Item $src $dest -Force
    Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path "$dest\nginx.exe")) {
        Write-Host "  [ERROR] nginx.exe no encontrado en $dest." -ForegroundColor Red; return
    }
    Write-Host "  [OK] Nginx extraido en $dest" -ForegroundColor Green

    Set-NginxConf -Puerto $Puerto

    $svc = Get-Service $CFG_NGINX_SVC -ErrorAction SilentlyContinue
    if (-not $svc) { sc.exe create nginx binPath= "$dest\nginx.exe" start= auto | Out-Null }
    Start-Service $CFG_NGINX_SVC -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $status = (Get-Service $CFG_NGINX_SVC -ErrorAction SilentlyContinue).Status
    if ($status -eq "Running") {
        Write-Host "  [OK] Servicio nginx: Running" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] Iniciando nginx como proceso directo..." -ForegroundColor Yellow
        Start-Process "$dest\nginx.exe" -WorkingDirectory $dest
        Start-Sleep -Seconds 2
        $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
        if ($proc) { Write-Host "  [OK] nginx corriendo (PID $($proc[0].Id))." -ForegroundColor Green }
        else { Write-Host "  [ERROR] nginx no pudo iniciarse. Revisa: $dest\logs\error.log" -ForegroundColor Red }
    }

    $webroot = "$dest\html\nginx"
    $version = $CFG_NGINX_URL -replace ".*nginx-","" -replace "\.zip",""
    Set-FirewallRule -Nombre "Nginx-HTTP-$Puerto" -Puerto $Puerto
    New-IndexPage -Servicio "Nginx" -Version $version -Puerto $Puerto -Webroot $webroot
    Write-Host "  [OK] Nginx instalado, puerto $Puerto." -ForegroundColor Green
}

function Set-NginxConf {
    param([int]$Puerto, [bool]$Https = $false, [int]$PuertoHttp = 8080)

    $conf    = "$CFG_NGINX_DIR\conf\nginx.conf"
    $webroot = "$CFG_NGINX_DIR\html\nginx"
    $wr      = $webroot -replace "\\","/"

    if (-not (Test-Path $conf)) { Write-Host "  [ERROR] No se encontro $conf" -ForegroundColor Red; return }
    if (-not (Test-Path $webroot)) { New-Item -ItemType Directory -Path $webroot -Force | Out-Null }

    if ($Https) {
        $crt = $CFG_SSL_CRT -replace "\\","/"
        $key = $CFG_SSL_KEY -replace "\\","/"
        @"
events { worker_connections 1024; }

http {
    include      mime.types;
    default_type application/octet-stream;
    sendfile     on;
    keepalive_timeout 65;

    server {
        listen $PuertoHttp;
        server_name localhost;
        return 301 https://`$host:`$request_uri;
    }

    server {
        listen $Puerto ssl;
        server_name localhost;
        root $wr;

        ssl_certificate     $crt;
        ssl_certificate_key $key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        location / { index index.html; }
    }
}
"@ | Set-Content $conf -Encoding ASCII
    } else {
        # HTTP — editar el conf existente en lugar de reescribirlo
        $c = Get-Content $conf -Raw
        # Reemplazar listen preservando el punto y coma
        $c = $c -replace "(?m)(^\s*listen\s+)\d+(;)", "`${1}$Puerto`$2"
        $c = $c -replace "(?m)(^\s*root\s+)[^;]+;", "`${1}$wr;"
        $c | Set-Content $conf -Encoding ASCII
    }

    $svc  = Get-Service $CFG_NGINX_SVC -ErrorAction SilentlyContinue
    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if (($svc -and $svc.Status -eq "Running") -or $proc) {
        & "$CFG_NGINX_DIR\nginx.exe" -s reload 2>&1 | Out-Null
    }
    Write-Host "  [OK] Nginx configurado en puerto $Puerto" -ForegroundColor Green
}

function Enable-NginxHttps {
    param([int]$Puerto = 443, [int]$PuertoHttp = 8080)

    Write-Host "`n=== Activando HTTPS en Nginx (puerto $Puerto) ===" -ForegroundColor Cyan

    if (-not (Test-Path "$CFG_NGINX_DIR\nginx.exe")) {
        Write-Host "  [ERROR] Nginx no esta instalado." -ForegroundColor Red; return
    }
    if (-not (New-SslCert)) { return }

    Set-NginxConf -Puerto $Puerto -Https $true -PuertoHttp $PuertoHttp
    Set-FirewallRule -Nombre "Nginx-HTTPS-$Puerto" -Puerto $Puerto

    $webroot = "$CFG_NGINX_DIR\html\nginx"
    $version = $CFG_NGINX_URL -replace ".*nginx-","" -replace "\.zip",""
    New-IndexPage -Servicio "Nginx" -Version $version -Puerto $Puerto -Webroot $webroot -Https $true

    $svc = Get-Service $CFG_NGINX_SVC -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Restart-Service $CFG_NGINX_SVC -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Process "$CFG_NGINX_DIR\nginx.exe" -WorkingDirectory $CFG_NGINX_DIR
        Start-Sleep -Seconds 2
    }

    $escucha = Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue
    if ($escucha) {
        Write-Host "  [OK] Nginx HTTPS activo en puerto $Puerto." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Puerto $Puerto no escucha. Revisa: $CFG_NGINX_DIR\logs\error.log" -ForegroundColor Yellow
    }
}

# ════════════════════════════════════════════════════════════
#  PUNTO DE ENTRADA
# ════════════════════════════════════════════════════════════

function Install-HttpServer {
    param([string]$Servidor)

    $defaultPort = if ($Servidor -eq "Nginx") { 8080 } else { 80 }
    $puerto      = Read-Port -Default $defaultPort -Label "Puerto HTTP"

    Write-Host "`n  Origen de instalacion:"
    Write-Host "    1) Repositorio FTP privado"
    Write-Host "    2) Descarga directa desde internet"
    $origen = Read-Host "  Elige [1/2]"

    switch ($origen) {
        "1" {
            $zipLocal = Get-FromFtp -Servicio $Servidor
            if (-not $zipLocal) { return }
            switch ($Servidor) {
                "Apache" { Install-Apache -Puerto $puerto -ZipLocal $zipLocal }
                "Nginx"  { Install-Nginx  -Puerto $puerto -ZipLocal $zipLocal }
            }
        }
        "2" {
            switch ($Servidor) {
                "Apache" { Install-Apache -Puerto $puerto }
                "Nginx"  { Install-Nginx  -Puerto $puerto }
            }
        }
        default { Write-Host "  Opcion invalida." -ForegroundColor Yellow }
    }
}

function Set-HttpPort {
    param([string]$Servidor)
    $puerto = Read-Port -Default 80 -Label "Nuevo puerto"
    switch ($Servidor) {
        "Apache" { Set-ApacheConf -Puerto $puerto }
        "Nginx"  { Set-NginxConf  -Puerto $puerto }
        default  { Write-Host "  Servidor '$Servidor' no reconocido." -ForegroundColor Yellow }
    }
    Set-FirewallRule -Nombre "$Servidor-HTTP-$puerto" -Puerto $puerto
}

function Set-Https {
    param([string]$Servidor)
    $puerto = Read-Port -Default 443 -Label "Puerto HTTPS"
    switch ($Servidor) {
        "Apache" { Enable-ApacheHttps -Puerto $puerto }
        "Nginx"  {
            $puertoHttp = Read-Port -Default 8080 -Label "Puerto HTTP (redireccion)"
            Enable-NginxHttps -Puerto $puerto -PuertoHttp $puertoHttp
        }
        default { Write-Host "  Servidor '$Servidor' no reconocido." -ForegroundColor Yellow }
    }
}

# ════════════════════════════════════════════════════════════
#  IIS
# ════════════════════════════════════════════════════════════

function Install-IIS {
    param([int]$Puerto = 80)

    Write-Host "`n======================================================" -ForegroundColor Cyan
    Write-Host "  Instalando IIS en puerto $Puerto"
    Write-Host "======================================================"

    # Instalar features necesarios
    $features = @(
        "Web-Server", "Web-Common-Http", "Web-Default-Doc",
        "Web-Static-Content", "Web-Http-Logging", "Web-Stat-Compression",
        "Web-Filtering", "Web-Mgmt-Tools", "Web-Mgmt-Console"
    )
    foreach ($f in $features) {
        $feat = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
        if ($feat -and -not $feat.Installed) {
            Write-Host "  Instalando feature: $f ..."
            Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
        }
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Cambiar puerto del Default Web Site
    $binding = Get-WebBinding -Name "Default Web Site" -Protocol "http" -ErrorAction SilentlyContinue
    if ($binding) {
        Set-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" `
            -PropertyName "bindingInformation" -Value "*:${Puerto}:" -ErrorAction SilentlyContinue
    } else {
        New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $Puerto | Out-Null
    }

    # Crear y apuntar webroot propio
    $webroot = "C:\inetpub\wwwroot\iis"
    if (-not (Test-Path $webroot)) { New-Item -ItemType Directory -Path $webroot -Force | Out-Null }
    Set-ItemProperty "IIS:\Sites\Default Web Site" -Name physicalPath -Value $webroot

    Start-Service W3SVC -ErrorAction SilentlyContinue
    Restart-WebItem "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue

    $version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $version) { $version = "IIS (Windows Server 2022)" }

    Set-FirewallRule -Nombre "IIS-HTTP-$Puerto" -Puerto $Puerto
    New-IndexPage -Servicio "IIS" -Version $version -Puerto $Puerto -Webroot $webroot

    $status = (Get-Service W3SVC -ErrorAction SilentlyContinue).Status
    if ($status -eq "Running") {
        Write-Host "  [OK] IIS instalado y activo en puerto $Puerto." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] W3SVC no esta Running. Revisa el Event Viewer." -ForegroundColor Yellow
    }
}

function Enable-IISHttps {
    param([int]$Puerto = 443)

    Write-Host "`n=== Activando HTTPS en IIS (puerto $Puerto) ===" -ForegroundColor Cyan

    $iisInstalled = Get-WindowsFeature -Name "Web-Server" -ErrorAction SilentlyContinue
    if (-not $iisInstalled -or -not $iisInstalled.Installed) {
        Write-Host "  [ERROR] IIS no esta instalado. Instala IIS primero." -ForegroundColor Red
        return
    }

    if (-not (New-SslCert)) { return }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Obtener thumbprint del certificado generado
    $cert = Get-ChildItem "Cert:\LocalMachine\My" |
        Where-Object { $_.FriendlyName -eq "Practica7-SSL" } |
        Select-Object -First 1

    if (-not $cert) {
        Write-Host "  [ERROR] No se encontro el certificado Practica7-SSL en el store." -ForegroundColor Red
        return
    }

    # Eliminar binding HTTPS previo si existe
    $bindingExiste = Get-WebBinding -Name "Default Web Site" -Protocol "https" -ErrorAction SilentlyContinue
    if ($bindingExiste) {
        Remove-WebBinding -Name "Default Web Site" -Protocol "https" -ErrorAction SilentlyContinue
    }

    # Crear binding HTTPS
    New-WebBinding -Name "Default Web Site" -Protocol "https" -Port $Puerto -IPAddress "*" -SslFlags 0 | Out-Null
    Write-Host "  [OK] Binding HTTPS creado en puerto $Puerto." -ForegroundColor Green

    # Asociar certificado via netsh
    $sslcertExiste = netsh http show sslcert ipport="0.0.0.0:$Puerto" 2>&1
    if ($sslcertExiste -match "IP:port") {
        netsh http delete sslcert ipport="0.0.0.0:$Puerto" | Out-Null
    }
    $guid = "{$([System.Guid]::NewGuid().ToString())}"
    $netshOut = netsh http add sslcert ipport="0.0.0.0:$Puerto" certhash=$($cert.Thumbprint) appid="$guid" 2>&1

    if ($netshOut -match "successfully") {
        Write-Host "  [OK] Certificado asociado al puerto $Puerto." -ForegroundColor Green
    } else {
        # Fallback via WebAdministration
        try {
            $b = Get-WebBinding -Name "Default Web Site" -Protocol "https" -Port $Puerto
            $b.AddSslCertificate($cert.Thumbprint, "My")
            Write-Host "  [OK] Certificado asociado via WebAdministration." -ForegroundColor Green
        } catch {
            Write-Host "  [WARN] No se pudo asociar el certificado automaticamente: $_" -ForegroundColor Yellow
            Write-Host "         Hazlo manualmente en IIS Manager -> Default Web Site -> Bindings." -ForegroundColor Yellow
        }
    }

    Set-FirewallRule -Nombre "IIS-HTTPS-$Puerto" -Puerto $Puerto

    $webroot = "C:\inetpub\wwwroot\iis"
    $version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $version) { $version = "IIS (Windows Server 2022)" }
    New-IndexPage -Servicio "IIS" -Version $version -Puerto $Puerto -Webroot $webroot -Https $true

    iisreset /restart 2>&1 | Out-Null
    Start-Sleep -Seconds 3

    $escucha = Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue
    if ($escucha) {
        Write-Host "  [OK] IIS HTTPS activo en puerto $Puerto." -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Puerto $Puerto no escucha. Revisa el Event Viewer." -ForegroundColor Yellow
    }
}