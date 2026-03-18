# ============================================================
#  http_funciones.ps1  -  Practica 7 (Windows Server 2022)
#  Instalacion y configuracion de servidores HTTP:
#    IIS, Apache httpd, Nginx
# ============================================================

# ── Rutas base ────────────────────────────────────────────────
$WEBROOT_IIS    = "C:\inetpub\wwwroot\iis"
$WEBROOT_APACHE = "C:\Apache24\htdocs\apache"
$WEBROOT_NGINX  = "C:\nginx\html\nginx"
$APACHE_URL     = "https://www.apachelounge.com/download/VS17/binaries/httpd-2.4.65-250724-Win64-VS17.zip"
$VCREDIST_URL   = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
$NGINX_URL      = "https://nginx.org/download/nginx-1.26.3.zip"
$TEMP_DIR       = "C:\Temp\practica7"

# ── Helper: descargar con manejo de redirects 308/301 ────────
function Descargar-Web {
    param([string]$URL, [string]$Destino)
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.Headers.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
    try {
        $wc.DownloadFile($URL, $Destino)
        return $true
    } catch {
        try {
            Invoke-WebRequest -Uri $URL -OutFile $Destino -UseBasicParsing `
                -MaximumRedirection 10 -UserAgent "Mozilla/5.0"
            return $true
        } catch {
            Write-Host "[ERROR] Descarga fallida: $_" -ForegroundColor Red
            return $false
        }
    } finally { $wc.Dispose() }
}

# ── Verificar si un servicio Windows existe ───────────────────
function Servicio-Instalado {
    param([string]$Nombre)
    return [bool](Get-Service -Name $Nombre -ErrorAction SilentlyContinue)
}

# ── Verificar si un feature IIS está instalado ────────────────
function Feature-Instalada {
    param([string]$Feature)
    $f = Get-WindowsFeature -Name $Feature -ErrorAction SilentlyContinue
    return ($f -and $f.Installed)
}

# ── Leer puerto con validación ────────────────────────────────
function Leer-Puerto {
    param([int]$Default = 80)

    $reservados = @(21, 22, 25, 53, 110, 143, 3306, 5432, 6379, 27017, 3389, 445, 139)

    while ($true) {
        $input_puerto = Read-Host "  Puerto para el servicio [default: $Default]"
        if ([string]::IsNullOrWhiteSpace($input_puerto)) { $input_puerto = "$Default" }

        if ($input_puerto -notmatch '^\d+$') {
            Write-Host "  Solo se permiten numeros." -ForegroundColor Yellow
            continue
        }
        $p = [int]$input_puerto
        if ($p -lt 1 -or $p -gt 65535) {
            Write-Host "  Puerto fuera de rango (1-65535)." -ForegroundColor Yellow
            continue
        }
        if ($reservados -contains $p) {
            Write-Host "  El puerto $p esta reservado para otro servicio." -ForegroundColor Yellow
            continue
        }
        return $p
    }
}

# ── Generar index.html ────────────────────────────────────────
function New-IndexHtml {
    param(
        [string]$Servicio,
        [string]$Version,
        [int]$Puerto
    )

    $webroot = switch ($Servicio) {
        "iis"    { $WEBROOT_IIS }
        "apache" { $WEBROOT_APACHE }
        "nginx"  { $WEBROOT_NGINX }
        default  { "C:\inetpub\wwwroot" }
    }

    if (-not (Test-Path $webroot)) { New-Item -ItemType Directory -Path $webroot -Force | Out-Null }

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$Servicio</title>
    <style>
        body { font-family: Arial, sans-serif; display: flex; justify-content: center;
               align-items: center; height: 100vh; margin: 0; background: #f0f2f5; }
        .card { background: white; border-radius: 8px; padding: 40px 60px;
                box-shadow: 0 2px 12px rgba(0,0,0,0.1); text-align: center; }
        h1 { color: #333; margin-bottom: 24px; }
        table { border-collapse: collapse; width: 100%; }
        td { padding: 10px 20px; text-align: left; }
        td:first-child { font-weight: bold; color: #555; }
        tr:nth-child(even) { background: #f9f9f9; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Servidor activo</h1>
        <table>
            <tr><td>Servicio</td><td>$Servicio</td></tr>
            <tr><td>Version</td><td>$Version</td></tr>
            <tr><td>Puerto</td><td>$Puerto</td></tr>
        </table>
    </div>
</body>
</html>
"@
    $html | Set-Content -Path "$webroot\index.html" -Encoding UTF8
    Write-Host "[OK] index.html generado en: $webroot\index.html" -ForegroundColor Green
    return $webroot
}

# ── Configurar regla de firewall ──────────────────────────────
function Abrir-Puerto-Firewall {
    param([string]$Nombre, [int]$Puerto)
    $regla = Get-NetFirewallRule -DisplayName $Nombre -ErrorAction SilentlyContinue
    if ($regla) { Remove-NetFirewallRule -DisplayName $Nombre }
    New-NetFirewallRule -DisplayName $Nombre -Direction Inbound `
        -Protocol TCP -LocalPort $Puerto -Action Allow | Out-Null
    Write-Host "[OK] Firewall: puerto $Puerto abierto ($Nombre)." -ForegroundColor Green
}

# ════════════════════════════════════════════════════════════════
#  IIS
# ════════════════════════════════════════════════════════════════

function Instalar-IIS {
    param([int]$Puerto = 80)

    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  Instalando IIS en puerto $Puerto"
    Write-Host "======================================================"

    # Instalar features necesarios
    $features = @(
        "Web-Server", "Web-Common-Http", "Web-Default-Doc",
        "Web-Static-Content", "Web-Http-Logging", "Web-Stat-Compression",
        "Web-Filtering", "Web-Mgmt-Tools", "Web-Mgmt-Console"
    )
    foreach ($f in $features) {
        if (-not (Feature-Instalada $f)) {
            Write-Host "  Instalando feature: $f ..."
            Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
        }
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Cambiar puerto del sitio Default Web Site
    Set-Puerto-IIS -Puerto $Puerto

    # Apuntar al directorio propio
    if (-not (Test-Path $WEBROOT_IIS)) { New-Item -ItemType Directory -Path $WEBROOT_IIS -Force | Out-Null }
    Set-ItemProperty "IIS:\Sites\Default Web Site" -Name physicalPath -Value $WEBROOT_IIS

    Restart-WebItem "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue
    Start-Service W3SVC

    $version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $version) { $version = "IIS (Windows Server 2022)" }

    Abrir-Puerto-Firewall -Nombre "IIS-HTTP-$Puerto" -Puerto $Puerto
    New-IndexHtml -Servicio "iis" -Version $version -Puerto $Puerto | Out-Null

    Write-Host "[OK] IIS instalado y activo en puerto $Puerto." -ForegroundColor Green
}

function Set-Puerto-IIS {
    param([int]$Puerto)
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $binding = Get-WebBinding -Name "Default Web Site" -Protocol "http" -ErrorAction SilentlyContinue
    if ($binding) {
        Set-WebBinding -Name "Default Web Site" -BindingInformation "*:80:" `
            -PropertyName "bindingInformation" -Value "*:${Puerto}:" -ErrorAction SilentlyContinue
    } else {
        New-WebBinding -Name "Default Web Site" -Protocol "http" -Port $Puerto | Out-Null
    }
    Write-Host "[OK] Puerto IIS cambiado a $Puerto." -ForegroundColor Green
}

# ════════════════════════════════════════════════════════════════
#  Apache httpd (Win64 binario de apachelounge.com)
# ════════════════════════════════════════════════════════════════

function Instalar-Apache {
    param(
        [int]$Puerto = 80,
        [string]$ArchivoLocal = ""   # ruta a .zip descargado via FTP, si aplica
    )

    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  Instalando Apache httpd en puerto $Puerto"
    Write-Host "======================================================"

    if (-not (Test-Path $TEMP_DIR)) { New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null }

    # ── Obtener el ZIP de Apache ──────────────────────────────────
    $zipPath = "$TEMP_DIR\apache.zip"
    if ($ArchivoLocal -ne "" -and (Test-Path $ArchivoLocal)) {
        Write-Host "  Usando archivo local: $ArchivoLocal"
        Copy-Item $ArchivoLocal $zipPath -Force
    } else {
        Write-Host "  Descargando Apache desde $APACHE_URL ..."
        $ok = Descargar-Web -URL $APACHE_URL -Destino $zipPath
        if (-not $ok) {
            Write-Host "[ERROR] No se pudo descargar Apache." -ForegroundColor Red
            return
        }
    }

    # ── Instalar Visual C++ Redistributable ──────────────────────
    # Buscar primero en el repositorio FTP local (ya descargado por prep_repo)
    # y si no, descargarlo desde la web.
    $vcPath = "$TEMP_DIR\vc_redist.x64.exe"
    $vcRepoPath = "C:\Temp\practica7\repo_ftp\vc_redist.x64.exe"
    if (Test-Path $vcRepoPath) {
        Write-Host "  [INFO] VCredist encontrado en repo local: $vcRepoPath"
        Copy-Item $vcRepoPath $vcPath -Force
    } elseif (-not (Test-Path $vcPath)) {
        Write-Host "  Descargando Visual C++ Redistributable ..."
        $okVc = Descargar-Web -URL $VCREDIST_URL -Destino $vcPath
        if (-not $okVc) {
            Write-Host "  [ADVERTENCIA] No se pudo obtener VCredist." -ForegroundColor Yellow
            Write-Host "               Si Apache falla al iniciar, instalalo manualmente desde:"
            Write-Host "               https://aka.ms/vs/17/release/vc_redist.x64.exe"
        }
    }
    if (Test-Path $vcPath) {
        Write-Host "  Instalando VCredist (silencioso) ..."
        Start-Process $vcPath -ArgumentList "/install /quiet /norestart" -Wait
        Write-Host "  [OK] Visual C++ Redistributable instalado." -ForegroundColor Green
    }

    # ── Extraer ZIP a directorio temporal intermedio ──────────────
    # Expand-Archive no es confiable extrayendo directo a C:\ en WS2022.
    # Se extrae a un directorio temporal y luego se mueve Apache24 a C:\.
    $extractTemp = "$TEMP_DIR\apache_extract"
    if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
    New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null

    Write-Host "  Extrayendo en $extractTemp ..."
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractTemp -Force -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Expand-Archive fallo: $_" -ForegroundColor Red
        return
    }

    # El ZIP de apachelounge contiene una carpeta raiz "Apache24"
    $apache24Extraido = Join-Path $extractTemp "Apache24"
    if (-not (Test-Path "$apache24Extraido\bin\httpd.exe")) {
        # Intentar buscar httpd.exe en cualquier subcarpeta (ZIP puede variar)
        $encontrado = Get-ChildItem $extractTemp -Recurse -Filter "httpd.exe" -ErrorAction SilentlyContinue |
                      Select-Object -First 1
        if ($encontrado) {
            $apache24Extraido = $encontrado.Directory.Parent.FullName
            Write-Host "  [INFO] httpd.exe encontrado en: $apache24Extraido"
        } else {
            Write-Host "[ERROR] No se encontro httpd.exe en el ZIP extraido." -ForegroundColor Red
            Write-Host "        Contenido de $extractTemp :" -ForegroundColor Yellow
            Get-ChildItem $extractTemp -Recurse | Select-Object -First 20 |
                ForEach-Object { Write-Host "          $($_.FullName)" }
            return
        }
    }

    # Mover Apache24 a C:\ (reemplazar si ya existe)
    $destino = "C:\Apache24"
    if (Test-Path $destino) {
        # Detener servicio antes de sobrescribir
        Stop-Service -Name "Apache2.4" -Force -ErrorAction SilentlyContinue
        Remove-Item $destino -Recurse -Force -ErrorAction SilentlyContinue
    }
    Move-Item $apache24Extraido $destino -Force
    Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path "C:\Apache24\bin\httpd.exe")) {
        Write-Host "[ERROR] No se encontro C:\Apache24\bin\httpd.exe tras mover la extraccion." -ForegroundColor Red
        return
    }
    Write-Host "  [OK] Apache24 extraido en C:\Apache24" -ForegroundColor Green

    # ── Crear directorio web y configurar ────────────────────────
    if (-not (Test-Path $WEBROOT_APACHE)) {
        New-Item -ItemType Directory -Path $WEBROOT_APACHE -Force | Out-Null
    }
    Set-Puerto-Apache -Puerto $Puerto

    # ── Instalar y arrancar como servicio Windows ─────────────────
    $apacheExe = "C:\Apache24\bin\httpd.exe"
    $svcExiste = Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    if (-not $svcExiste) {
        Write-Host "  Registrando servicio Apache2.4 ..."
        $resultado = & $apacheExe -k install 2>&1
        Write-Host "  [httpd -k install] $resultado"
    }
    Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue

    $svcStatus = (Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue).Status
    if ($svcStatus -eq "Running") {
        Write-Host "  [OK] Servicio Apache2.4: Running" -ForegroundColor Green
    } else {
        Write-Host "  [ADVERTENCIA] Servicio Apache2.4 no arranco (estado: $svcStatus)." -ForegroundColor Yellow
        Write-Host "               Revisa el log: C:\Apache24\logs\error.log"
        Write-Host "               Causa mas comun: falta Visual C++ Redistributable."
    }

    $version = (& $apacheExe -v 2>&1 | Select-String "Server version") -replace ".*Apache/", "" -replace " .*", ""
    if (-not $version) { $version = "2.4.x" }

    Abrir-Puerto-Firewall -Nombre "Apache-HTTP-$Puerto" -Puerto $Puerto
    New-IndexHtml -Servicio "apache" -Version $version -Puerto $Puerto | Out-Null

    Write-Host "[OK] Apache instalado como servicio 'Apache2.4', puerto $Puerto." -ForegroundColor Green
}

function Set-Puerto-Apache {
    param([int]$Puerto)
    $conf = "C:\Apache24\conf\httpd.conf"
    if (-not (Test-Path $conf)) {
        Write-Host "[ERROR] No se encontro $conf" -ForegroundColor Red
        return
    }
    # Cambiar puerto Listen
    (Get-Content $conf) -replace "^Listen \d+", "Listen $Puerto" |
        Set-Content $conf

    # Cambiar DocumentRoot al nuestro (escapar barras para regex)
    $escapedNew = $WEBROOT_APACHE -replace "\\", "/"
    (Get-Content $conf) -replace 'DocumentRoot ".*"', "DocumentRoot `"$escapedNew`"" |
        Set-Content $conf
    (Get-Content $conf) -replace '<Directory ".*htdocs">', "<Directory `"$escapedNew`">" |
        Set-Content $conf

    Restart-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Write-Host "[OK] Puerto Apache cambiado a $Puerto." -ForegroundColor Green
}

# ════════════════════════════════════════════════════════════════
#  Nginx (binario oficial Windows)
# ════════════════════════════════════════════════════════════════

function Instalar-Nginx {
    param(
        [int]$Puerto = 8080,
        [string]$ArchivoLocal = ""
    )

    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "  Instalando Nginx en puerto $Puerto"
    Write-Host "======================================================"

    if (-not (Test-Path $TEMP_DIR)) { New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null }

    $zipPath = "$TEMP_DIR\nginx.zip"
    if ($ArchivoLocal -ne "" -and (Test-Path $ArchivoLocal)) {
        Write-Host "  Usando archivo local: $ArchivoLocal"
        Copy-Item $ArchivoLocal $zipPath -Force
    } else {
        Write-Host "  Descargando Nginx desde $NGINX_URL ..."
        $ok = Descargar-Web -URL $NGINX_URL -Destino $zipPath
        if (-not $ok) {
            Write-Host "[ERROR] No se pudo descargar Nginx." -ForegroundColor Red
            return
        }
    }

    # ── Extraer a directorio temporal intermedio ──────────────────
    $extractTemp = "$TEMP_DIR\nginx_extract"
    if (Test-Path $extractTemp) { Remove-Item $extractTemp -Recurse -Force }
    New-Item -ItemType Directory -Path $extractTemp -Force | Out-Null

    Write-Host "  Extrayendo en $extractTemp ..."
    try {
        Expand-Archive -Path $zipPath -DestinationPath $extractTemp -Force -ErrorAction Stop
    } catch {
        Write-Host "[ERROR] Expand-Archive fallo: $_" -ForegroundColor Red
        return
    }

    # El ZIP de nginx.org extrae como nginx-X.XX.X\
    $nginxExtraido = Get-ChildItem $extractTemp -Directory | Where-Object { $_.Name -like "nginx*" } | Select-Object -First 1
    if (-not $nginxExtraido -or -not (Test-Path "$($nginxExtraido.FullName)\nginx.exe")) {
        $encontrado = Get-ChildItem $extractTemp -Recurse -Filter "nginx.exe" -ErrorAction SilentlyContinue |
                      Select-Object -First 1
        if ($encontrado) {
            $nginxExtraido = Get-Item $encontrado.Directory.FullName
        } else {
            Write-Host "[ERROR] No se encontro nginx.exe en el ZIP extraido." -ForegroundColor Red
            return
        }
    }

    # Mover a C:\nginx (reemplazar si ya existe)
    $destino = "C:\nginx"
    if (Test-Path $destino) {
        Stop-Service -Name "nginx" -Force -ErrorAction SilentlyContinue
        Remove-Item $destino -Recurse -Force -ErrorAction SilentlyContinue
    }
    Move-Item $nginxExtraido.FullName $destino -Force
    Remove-Item $extractTemp -Recurse -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path "C:\nginx\nginx.exe")) {
        Write-Host "[ERROR] No se encontro C:\nginx\nginx.exe tras mover la extraccion." -ForegroundColor Red
        return
    }
    Write-Host "  [OK] Nginx extraido en C:\nginx" -ForegroundColor Green

    if (-not (Test-Path $WEBROOT_NGINX)) { New-Item -ItemType Directory -Path $WEBROOT_NGINX -Force | Out-Null }

    Set-Puerto-Nginx -Puerto $Puerto

    # Registrar Nginx como servicio con sc.exe
    $svcExiste = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
    if (-not $svcExiste) {
        Write-Host "  Registrando servicio nginx ..."
        sc.exe create nginx binPath= "C:\nginx\nginx.exe" start= auto | Out-Null
    }
    Start-Service -Name "nginx" -ErrorAction SilentlyContinue

    $svcStatus = (Get-Service -Name "nginx" -ErrorAction SilentlyContinue).Status
    if ($svcStatus -eq "Running") {
        Write-Host "  [OK] Servicio nginx: Running" -ForegroundColor Green
    } else {
        Write-Host "  [ADVERTENCIA] Servicio nginx no arranco (estado: $svcStatus)." -ForegroundColor Yellow
        Write-Host "               Nginx en Windows no funciona bien como servicio nativo con sc.exe."
        Write-Host "               Iniciando directamente con Start-Process ..."
        Start-Process "C:\nginx\nginx.exe" -WorkingDirectory "C:\nginx"
        Start-Sleep -Seconds 2
        $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
        if ($proc) {
            Write-Host "  [OK] nginx.exe corriendo como proceso (PID $($proc[0].Id))." -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] No se pudo iniciar nginx. Revisa C:\nginx\logs\error.log" -ForegroundColor Red
        }
    }

    $version = ($NGINX_URL -replace ".*nginx-", "" -replace "\.zip", "")

    Abrir-Puerto-Firewall -Nombre "Nginx-HTTP-$Puerto" -Puerto $Puerto
    New-IndexHtml -Servicio "nginx" -Version $version -Puerto $Puerto | Out-Null

    Write-Host "[OK] Nginx instalado, puerto $Puerto." -ForegroundColor Green
}

function Set-Puerto-Nginx {
    param([int]$Puerto)
    $conf = "C:\nginx\conf\nginx.conf"
    if (-not (Test-Path $conf)) {
        Write-Host "[ERROR] No se encontro $conf" -ForegroundColor Red
        return
    }

    $rootEscapado = $WEBROOT_NGINX -replace "\\", "/"

    $contenido = Get-Content $conf -Raw
    # Cambiar puerto listen
    $contenido = $contenido -replace "listen\s+\d+", "listen $Puerto"
    # Cambiar root
    $contenido = $contenido -replace "root\s+[^;]+;", "root $rootEscapado;"
    $contenido | Set-Content $conf

    $svc = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
    if ($svc) { Restart-Service -Name "nginx" -ErrorAction SilentlyContinue }
    Write-Host "[OK] Puerto Nginx cambiado a $Puerto." -ForegroundColor Green
}

# ── Cambiar puerto de un servidor ya instalado ────────────────
function Cambiar-Puerto {
    param([string]$Servicio, [int]$Puerto)
    switch ($Servicio.ToLower()) {
        "iis"    { Set-Puerto-IIS -Puerto $Puerto }
        "apache" { Set-Puerto-Apache -Puerto $Puerto }
        "nginx"  { Set-Puerto-Nginx -Puerto $Puerto }
        default  { Write-Host "[ERROR] Servicio '$Servicio' no reconocido." -ForegroundColor Red }
    }
    Abrir-Puerto-Firewall -Nombre "$Servicio-HTTP-$Puerto" -Puerto $Puerto
}