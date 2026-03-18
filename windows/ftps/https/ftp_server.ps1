# ============================================================
#  ftp_server.ps1  -  Practica 7 (Windows Server 2022)
#  Configura IIS FTP como servidor de repositorio privado:
#    - Instala features Web-Ftp-Server
#    - Crea sitio FTP con aislamiento por usuario
#    - Crea usuario 'repo' con junction al directorio de binarios
#    - Puebla el repositorio descargando Apache y Nginx
# ============================================================
#Requires -RunAsAdministrator

. "$PSScriptRoot\config.ps1"

# ────────────────────────────────────────────────────────────
# PASO 1: Instalar features de Windows necesarios
# ────────────────────────────────────────────────────────────
function Install-FtpFeatures {
    Write-Host "`n[1/4] Instalando features IIS + FTP..." -ForegroundColor Cyan

    $features = @(
        "Web-Server",
        "Web-Mgmt-Tools",
        "Web-Mgmt-Console",
        "Web-Ftp-Server",
        "Web-Ftp-Service",
        "Web-Ftp-Extensibility"
    )

    foreach ($f in $features) {
        $feat = Get-WindowsFeature -Name $f -ErrorAction SilentlyContinue
        if ($feat -and -not $feat.Installed) {
            Write-Host "  Instalando: $f ..."
            Install-WindowsFeature -Name $f -IncludeManagementTools | Out-Null
        }
    }

    Start-Service W3SVC  -ErrorAction SilentlyContinue
    Start-Service ftpsvc -ErrorAction SilentlyContinue

    Write-Host "  [OK] Features instalados. W3SVC y ftpsvc activos." -ForegroundColor Green
}

# ────────────────────────────────────────────────────────────
# PASO 2: Crear estructura de directorios del repositorio
# ────────────────────────────────────────────────────────────
function New-FtpDirectories {
    Write-Host "`n[2/4] Creando estructura de directorios..." -ForegroundColor Cyan

    $dirs = @(
        $CFG_FTP_BASE,
        "$CFG_FTP_BASE\LocalUser",           # requerido por IIS FTP user isolation
        $CFG_FTP_REPO,
        "$CFG_FTP_REPO\http\Windows\Apache",
        "$CFG_FTP_REPO\http\Windows\Nginx",
        "$CFG_FTP_REPO\http\Windows\IIS"
    )

    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Write-Host "  Creado: $d"
        }
    }

    Write-Host "  [OK] Directorios listos." -ForegroundColor Green
}

# ────────────────────────────────────────────────────────────
# PASO 3: Crear sitio FTP en IIS con aislamiento de usuario
# ────────────────────────────────────────────────────────────
function New-FtpSite {
    Write-Host "`n[3/4] Configurando sitio FTP '$CFG_FTP_SITE'..." -ForegroundColor Cyan

    if (-not (Test-Path $CFG_APPCMD)) {
        Write-Host "  [ERROR] appcmd.exe no encontrado. Asegurate de que IIS este instalado." -ForegroundColor Red
        return $false
    }

    # Eliminar sitio previo para empezar limpio
    $existe = & $CFG_APPCMD list site "/name:$CFG_FTP_SITE" 2>$null
    if ($existe) {
        & $CFG_APPCMD delete site "/site.name:$CFG_FTP_SITE" | Out-Null
        Write-Host "  Sitio anterior eliminado."
    }

    # Crear sitio FTP apuntando a la raiz FTP
    & $CFG_APPCMD add site /name:"$CFG_FTP_SITE" `
        /physicalPath:"$CFG_FTP_BASE" `
        /bindings:"ftp/*:${CFG_FTP_PORT}:" | Out-Null

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Editar applicationHost.config para:
    #   - Habilitar autenticacion basica
    #   - Deshabilitar acceso anonimo
    #   - Modo de aislamiento: IsolateAllDirectories
    $configPath = "$env:windir\system32\inetsrv\config\applicationHost.config"

    # Hacer backup antes de editar
    Copy-Item $configPath "$configPath.bak" -Force

    [xml]$config = Get-Content $configPath -Raw

    $siteNode = $config.configuration.'system.applicationHost'.sites.site |
        Where-Object { $_.name -eq $CFG_FTP_SITE }

    if (-not $siteNode) {
        Write-Host "  [ERROR] Sitio no encontrado en applicationHost.config tras crearlo." -ForegroundColor Red
        return $false
    }

    # Helper para obtener o crear un nodo XML hijo
    function Get-OrCreate-Node {
        param($parent, [string]$nombre)
        $nodo = $parent.$nombre
        if (-not $nodo) {
            $nodo = $config.CreateElement($nombre)
            $parent.AppendChild($nodo) | Out-Null
        }
        return $nodo
    }

    $ftpServer  = Get-OrCreate-Node $siteNode  "ftpServer"
    $security   = Get-OrCreate-Node $ftpServer "security"
    $auth       = Get-OrCreate-Node $security  "authentication"
    $basic      = Get-OrCreate-Node $auth      "basicAuthentication"
    $anon       = Get-OrCreate-Node $auth      "anonymousAuthentication"
    $isolation  = Get-OrCreate-Node $ftpServer "userIsolation"
    $logFile    = Get-OrCreate-Node $ftpServer "logFile"

    $basic.SetAttribute("enabled", "true")
    $anon.SetAttribute("enabled", "false")
    $isolation.SetAttribute("mode", "IsolateAllDirectories")
    $logFile.SetAttribute("enabled", "true")

    $config.Save($configPath)

    # Permitir lectura a todos los usuarios autenticados
    & $CFG_APPCMD set config /section:system.ftpServer/security/authorization `
        "/+[accessType='Allow',roles='',permissions='Read',users='*']" 2>$null

    # Permitir conexiones FTP plain (SslAllow en lugar de SslRequire)
    # Sin esto IIS FTP exige FTPS y rechaza conexiones plain con error 534
    [xml]$cfg2 = Get-Content $configPath -Raw
    $sitio2 = $cfg2.configuration.'system.applicationHost'.sites.site |
        Where-Object { $_.name -eq $CFG_FTP_SITE }
    $sslNode = $sitio2.ftpServer.security.ssl
    if (-not $sslNode) {
        $sslNode = $cfg2.CreateElement("ssl")
        $sitio2.ftpServer.security.AppendChild($sslNode) | Out-Null
    }
    $sslNode.SetAttribute("controlChannelPolicy", "SslAllow")
    $sslNode.SetAttribute("dataChannelPolicy",    "SslAllow")
    $cfg2.Save($configPath)
    Write-Host "  [OK] Politica SSL: SslAllow (acepta FTP plain y FTPS)." -ForegroundColor Green

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Abrir firewall para control FTP y modo pasivo
    $fwRules = @(
        @{ Name = "FTP-Control-P7"; Port = "21" },
        @{ Name = "FTP-Pasivo-P7";  Port = "49152-65535" }
    )
    foreach ($r in $fwRules) {
        if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $r.Name -Direction Inbound `
                -Protocol TCP -LocalPort $r.Port -Action Allow | Out-Null
        }
    }

    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($svc.Status -eq "Running") {
        Write-Host "  [OK] Sitio FTP '$CFG_FTP_SITE' activo en puerto $CFG_FTP_PORT." -ForegroundColor Green
        return $true
    } else {
        Write-Host "  [ERROR] ftpsvc no esta Running. Revisa el Event Viewer." -ForegroundColor Red
        return $false
    }
}

# ────────────────────────────────────────────────────────────
# PASO 4: Crear usuario 'repo' con junction al repositorio
# ────────────────────────────────────────────────────────────
# Con IIS FTP user isolation, cada usuario autenticado ve como "/"
# su carpeta en $CFG_FTP_BASE\LocalUser\<usuario>
# Dentro de esa carpeta creamos una junction llamada 'repo'
# que apunta a $CFG_FTP_REPO, por eso el cliente FTP accede via /repo/
function New-RepoUser {
    Write-Host "`n[4/4] Creando usuario 'repo'..." -ForegroundColor Cyan

    $repoIsolated = "$CFG_FTP_BASE\LocalUser\repo"
    $juncRepo     = "$repoIsolated\repo"

    # Crear usuario local si no existe
    if (-not (Get-LocalUser -Name "repo" -ErrorAction SilentlyContinue)) {
        $pass = Read-Host "  Contrasena para el usuario 'repo'" -AsSecureString
        New-LocalUser -Name "repo" -Password $pass `
            -FullName "Repositorio FTP" `
            -Description "Usuario repositorio Practica7" `
            -PasswordNeverExpires | Out-Null
        Write-Host "  [OK] Usuario 'repo' creado."
    } else {
        Write-Host "  Usuario 'repo' ya existe, reutilizando."
    }

    # Carpeta de aislamiento del usuario
    if (-not (Test-Path $repoIsolated)) {
        New-Item -ItemType Directory -Path $repoIsolated -Force | Out-Null
    }

    # Junction: siempre recrear para garantizar que apunta al repo correcto
    if (Test-Path $juncRepo) {
        cmd /c "rmdir `"$juncRepo`"" | Out-Null
    }
    cmd /c "mklink /J `"$juncRepo`" `"$CFG_FTP_REPO`"" | Out-Null

    if (-not (Test-Path "$juncRepo\http\Windows")) {
        Write-Host "  [ERROR] Junction creada pero $juncRepo\http\Windows no es accesible." -ForegroundColor Red
        Write-Host "          Asegurate de ejecutar Poblar-Repositorio primero." -ForegroundColor Yellow
        return
    }

    # Permisos NTFS: repo puede leer el repositorio y su carpeta de aislamiento
    foreach ($ruta in @($CFG_FTP_REPO, $repoIsolated)) {
        $acl  = Get-Acl $ruta
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "repo", "ReadAndExecute",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $ruta -AclObject $acl
    }

    Write-Host "  [OK] Usuario 'repo' listo." -ForegroundColor Green
    Write-Host "       Ruta FTP visible: /repo/http/Windows" -ForegroundColor Cyan
}

# ────────────────────────────────────────────────────────────
# EXTRA: Poblar repositorio descargando Apache y Nginx
# ────────────────────────────────────────────────────────────
function Get-Binario {
    param([string]$URL, [string]$Destino)

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $headers = @{
        "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0"
        "Referer"    = "https://www.apachelounge.com/download/"
    }

    try {
        Invoke-WebRequest -Uri $URL -OutFile $Destino `
            -Headers $headers -UseBasicParsing -MaximumRedirection 10 -ErrorAction Stop
        return $true
    } catch {}

    # Fallback: curl.exe (incluido en Windows Server 2022)
    $curl = "$env:SystemRoot\System32\curl.exe"
    if (Test-Path $curl) {
        & $curl -L -o $Destino `
            -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0" `
            -H "Referer: https://www.apachelounge.com/download/" `
            --silent --show-error $URL
        return ($LASTEXITCODE -eq 0)
    }

    return $false
}

function Add-Sha256 {
    param([string]$Archivo)
    $hash = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    $hash | Set-Content "$Archivo.sha256" -Encoding ASCII -NoNewline
    return $hash
}

function Invoke-PopularRepositorio {
    Write-Host "`n=== Poblando repositorio FTP ===" -ForegroundColor Cyan

    if (-not (Test-Path $CFG_TEMP_DIR)) {
        New-Item -ItemType Directory -Path $CFG_TEMP_DIR -Force | Out-Null
    }

    # ── VCredist (requerido por Apache) ──────────────────────
    $vcDest = "$CFG_FTP_REPO\http\Windows\Apache\vc_redist.x64.exe"
    if (-not (Test-Path $vcDest)) {
        Write-Host "  Descargando Visual C++ Redistributable..."
        $ok = Get-Binario -URL $CFG_VCREDIST_URL -Destino $vcDest
        if ($ok -and (Get-Item $vcDest).Length -gt 1MB) {
            Add-Sha256 $vcDest | Out-Null
            Write-Host "  [OK] vc_redist.x64.exe" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] VCredist no descargado. Apache puede fallar al iniciar." -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [OK] vc_redist.x64.exe ya existe."
    }

    # ── Apache ───────────────────────────────────────────────
    # apachelounge.com bloquea descargas automaticas — debe copiarse manualmente.
    $apacheDir  = "$CFG_FTP_REPO\http\Windows\Apache"
    $apacheZips = @(Get-ChildItem $apacheDir -Filter "httpd-*.zip" -ErrorAction SilentlyContinue)
    if ($apacheZips.Count -gt 0) {
        foreach ($z in $apacheZips) {
            if (-not (Test-Path "$($z.FullName).sha256")) {
                $hash = Add-Sha256 $z.FullName
                Write-Host "  [OK] $($z.Name) - hash generado: $hash" -ForegroundColor Green
            } else {
                Write-Host "  [OK] $($z.Name) ya existe con hash." -ForegroundColor Green
            }
        }
    } else {
        Write-Host ""
        Write-Host "  [!] Apache httpd NO esta en el repositorio." -ForegroundColor Yellow
        Write-Host "      Descarga el ZIP en tu maquina desde:" -ForegroundColor Yellow
        Write-Host "      $CFG_APACHE_URL" -ForegroundColor Cyan
        Write-Host "      Luego copialo al servidor con scp:" -ForegroundColor Yellow
        Write-Host "      scp httpd-*.zip usuario@<IP>:$apacheDir\" -ForegroundColor Cyan
        Write-Host "      Y vuelve a ejecutar esta opcion para generar el hash." -ForegroundColor Yellow
        Write-Host ""
    }

    # ── Nginx ─────────────────────────────────────────────────
    $nginxDest = "$CFG_FTP_REPO\http\Windows\Nginx\$($CFG_NGINX_URL.Split('/')[-1])"
    if (-not (Test-Path $nginxDest)) {
        Write-Host "  Descargando Nginx (~1.5 MB)..."
        $ok = Get-Binario -URL $CFG_NGINX_URL -Destino $nginxDest
        if ($ok -and (Test-Path $nginxDest) -and (Get-Item $nginxDest).Length -gt 500KB) {
            $hash = Add-Sha256 $nginxDest
            Write-Host "  [OK] $(Split-Path $nginxDest -Leaf)  SHA256: $hash" -ForegroundColor Green
        } else {
            Write-Host "  [ERROR] Nginx no descargado correctamente." -ForegroundColor Red
            Write-Host "          Descarga manual: $CFG_NGINX_URL" -ForegroundColor Yellow
            Write-Host "          Guarda el ZIP en: $CFG_FTP_REPO\http\Windows\Nginx\" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [OK] Nginx ZIP ya existe."
    }

    # ── Marcador IIS ──────────────────────────────────────────
    $iisInfo = "$CFG_FTP_REPO\http\Windows\IIS\IIS-WindowsServer2022.info"
    if (-not (Test-Path $iisInfo)) {
        "IIS se instala como rol de Windows, no como binario descargable.`nUsa main.ps1 opcion 1." |
            Set-Content $iisInfo -Encoding UTF8
    }

    Write-Host "`n  Contenido del repositorio:" -ForegroundColor Cyan
    Get-ChildItem -Path $CFG_FTP_REPO -Recurse -File |
        ForEach-Object {
            Write-Host "    $($_.FullName)  ($([math]::Round($_.Length/1MB,2)) MB)"
        }
}

# ────────────────────────────────────────────────────────────
# MENU / PUNTO DE ENTRADA
# ────────────────────────────────────────────────────────────
function Invoke-FtpServerSetup {
    while ($true) {
        Write-Host "`n======================================================" -ForegroundColor Cyan
        Write-Host "   CONFIGURACION SERVIDOR FTP (IIS FTP)"
        Write-Host "======================================================"
        Write-Host "  1) Setup completo (features + directorios + sitio + usuario repo)"
        Write-Host "  2) Solo instalar features IIS/FTP"
        Write-Host "  3) Solo crear sitio FTP"
        Write-Host "  4) Solo crear usuario 'repo'"
        Write-Host "  5) Poblar repositorio (descargar Apache y Nginx)"
        Write-Host "  6) Estado del servicio FTP"
        Write-Host "  0) Volver"
        Write-Host "------------------------------------------------------"
        $opc = Read-Host "  Opcion"

        switch ($opc) {
            "1" {
                Install-FtpFeatures
                New-FtpDirectories
                New-FtpSite
                New-RepoUser
                Write-Host "`n[OK] Setup FTP completo." -ForegroundColor Green
                Write-Host "     Ejecuta la opcion 5 para descargar los binarios al repositorio." -ForegroundColor Yellow
            }
            "2" { Install-FtpFeatures }
            "3" { New-FtpDirectories; New-FtpSite }
            "4" { New-RepoUser }
            "5" { Invoke-PopularRepositorio }
            "6" {
                foreach ($svc in @("W3SVC", "ftpsvc")) {
                    $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
                    $estado = if ($s) { $s.Status } else { "no instalado" }
                    Write-Host "  $svc : $estado" -ForegroundColor Cyan
                }
                if (Test-Path $CFG_APPCMD) {
                    $sitio = & $CFG_APPCMD list site "/name:$CFG_FTP_SITE" 2>$null
                    Write-Host "  Sitio '$CFG_FTP_SITE': $(if ($sitio) { $sitio } else { 'no encontrado' })" -ForegroundColor Cyan
                }
            }
            "0" { return }
            default { Write-Host "  Opcion invalida." -ForegroundColor Yellow }
        }
    }
}