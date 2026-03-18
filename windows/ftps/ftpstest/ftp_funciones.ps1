# ============================================================
#  ftp_funciones.ps1  -  Practica 7 (Windows Server 2022)
#  Configuracion de servidor FTP con IIS FTP Service
#  Usa appcmd.exe en lugar de WebAdministration (mas estable)
# ============================================================

$FTP_BASE  = "C:\srv\ftp"
$FTP_REPO  = "$FTP_BASE\repo"
$FTP_SITE  = "Practica7-FTP"
$APPCMD    = "$env:windir\system32\inetsrv\appcmd.exe"

# ── Instalar features de Windows necesarios ──────────────────
function Instalar-FTP {
    Write-Host "  Verificando features de IIS y FTP ..."

    # Web-Server debe instalarse ANTES que FTP para que W3SVC exista
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
            Write-Host "  Instalando feature: $f ..."
            Install-WindowsFeature -Name $f | Out-Null
            Write-Host "  [OK] $f instalado." -ForegroundColor Green
        } else {
            Write-Host "  [OK] $f ya instalado."
        }
    }

    # Asegurar que W3SVC y ftpsvc esten corriendo
    Start-Service W3SVC  -ErrorAction SilentlyContinue
    Start-Service ftpsvc -ErrorAction SilentlyContinue
    Write-Host "[OK] Servicios IIS/FTP activos." -ForegroundColor Green
}

# ── Crear estructura de directorios base ─────────────────────
function Crear-EstructuraFTP {
    $dirs = @(
        $FTP_BASE,
        "$FTP_BASE\Anonymous",
        "$FTP_BASE\Anonymous\General",
        "$FTP_BASE\General",
        "$FTP_BASE\Reprobados",
        "$FTP_BASE\Recursadores",
        "$FTP_BASE\LocalUser",
        $FTP_REPO,
        "$FTP_REPO\http\Windows\IIS",
        "$FTP_REPO\http\Windows\Apache",
        "$FTP_REPO\http\Windows\Nginx"
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
            Write-Host "  [OK] Creado: $d"
        }
    }
}

# ── Crear sitio FTP via appcmd (sin WebAdministration) ───────
function Set-FtpSitio {
    param([int]$Puerto = 21)

    if (-not (Test-Path $APPCMD)) {
        Write-Host "[ERROR] appcmd.exe no encontrado. Instala IIS primero (opcion 5->2)." -ForegroundColor Red
        return
    }

    # Eliminar sitio previo si existe para empezar limpio
    $existe = & $APPCMD list site "/name:$FTP_SITE" 2>$null
    if ($existe) {
        Write-Host "  Eliminando sitio FTP previo ..."
        & $APPCMD delete site "/site.name:$FTP_SITE" | Out-Null
    }

    # Crear sitio FTP nuevo
    Write-Host "  Creando sitio FTP '$FTP_SITE' en puerto $Puerto ..."
    & $APPCMD add site /name:"$FTP_SITE" /physicalPath:"$FTP_BASE" /bindings:"ftp/*:${Puerto}:"

    # Reiniciar ftpsvc para que cargue el sitio recien creado
    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Configurar autenticacion, aislamiento y log editando applicationHost.config
    # (appcmd set config falla con 800710d8 en algunos WS2022 para nodos FTP)
    $configPath = "$env:windir\system32\inetsrv\config\applicationHost.config"
    $backup     = "$configPath.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $configPath $backup

    [xml]$config = Get-Content $configPath -Raw

    # Buscar el nodo del sitio FTP
    $siteNode = $config.configuration.'system.applicationHost'.sites.site |
        Where-Object { $_.name -eq $FTP_SITE }

    if ($siteNode) {
        # Obtener o crear nodo ftpServer
        $ftpServer = $siteNode.ftpServer
        if (-not $ftpServer) {
            $ftpServer = $config.CreateElement("ftpServer")
            $siteNode.AppendChild($ftpServer) | Out-Null
        }

        # security
        $security = $ftpServer.security
        if (-not $security) {
            $security = $config.CreateElement("security")
            $ftpServer.AppendChild($security) | Out-Null
        }

        # authentication
        $auth = $security.authentication
        if (-not $auth) {
            $auth = $config.CreateElement("authentication")
            $security.AppendChild($auth) | Out-Null
        }

        # basicAuthentication enabled="true"
        $basic = $auth.basicAuthentication
        if (-not $basic) {
            $basic = $config.CreateElement("basicAuthentication")
            $auth.AppendChild($basic) | Out-Null
        }
        $basic.SetAttribute("enabled", "true")

        # anonymousAuthentication enabled="false"
        $anon = $auth.anonymousAuthentication
        if (-not $anon) {
            $anon = $config.CreateElement("anonymousAuthentication")
            $auth.AppendChild($anon) | Out-Null
        }
        $anon.SetAttribute("enabled", "false")

        # userIsolation mode="IsolateAllDirectories"
        $isolation = $ftpServer.userIsolation
        if (-not $isolation) {
            $isolation = $config.CreateElement("userIsolation")
            $ftpServer.AppendChild($isolation) | Out-Null
        }
        $isolation.SetAttribute("mode", "IsolateAllDirectories")

        # logFile enabled="true"
        $logFile = $ftpServer.logFile
        if (-not $logFile) {
            $logFile = $config.CreateElement("logFile")
            $ftpServer.AppendChild($logFile) | Out-Null
        }
        $logFile.SetAttribute("enabled", "true")

        $config.Save($configPath)
        Write-Host "  [OK] applicationHost.config actualizado." -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] No se encontro el sitio '$FTP_SITE' en applicationHost.config." -ForegroundColor Red
    }

    # Reiniciar para aplicar cambios
    Restart-Service ftpsvc -ErrorAction SilentlyContinue

    # Agregar regla de autorizacion FTP global (seccion correcta, no dentro del sitio)
    # Permite a todos los usuarios autenticados leer y escribir
    & $APPCMD set config /section:system.ftpServer/security/authorization `
        "/+[accessType='Allow',roles='',permissions='Read,Write',users='*']" 2>$null

    # Firewall: puerto control y rango pasivo
    foreach ($r in @(
        @{Nombre="FTP-Control-Practica7"; Puerto="21"},
        @{Nombre="FTP-Pasivo-Practica7";  Puerto="49152-65535"}
    )) {
        if (-not (Get-NetFirewallRule -DisplayName $r.Nombre -ErrorAction SilentlyContinue)) {
            New-NetFirewallRule -DisplayName $r.Nombre -Direction Inbound `
                -Protocol TCP -LocalPort $r.Puerto -Action Allow | Out-Null
        }
    }

    Write-Host "[OK] Sitio FTP '$FTP_SITE' configurado en puerto $Puerto." -ForegroundColor Green
}

# ── Aplicar certificado SSL al sitio FTP via XML directo ─────
function Set-FtpSSL {
    param([string]$Thumbprint)

    $configPath = "$env:windir\system32\inetsrv\config\applicationHost.config"
    [xml]$config = Get-Content $configPath -Raw

    $siteNode = $config.configuration.'system.applicationHost'.sites.site |
        Where-Object { $_.name -eq $FTP_SITE }

    if (-not $siteNode) {
        Write-Host "[ERROR] Sitio '$FTP_SITE' no encontrado en applicationHost.config" -ForegroundColor Red
        return
    }

    $ftpServer = $siteNode.ftpServer
    if (-not $ftpServer) {
        $ftpServer = $config.CreateElement("ftpServer")
        $siteNode.AppendChild($ftpServer) | Out-Null
    }

    $security = $ftpServer.security
    if (-not $security) {
        $security = $config.CreateElement("security")
        $ftpServer.AppendChild($security) | Out-Null
    }

    $ssl = $security.ssl
    if (-not $ssl) {
        $ssl = $config.CreateElement("ssl")
        $security.AppendChild($ssl) | Out-Null
    }

    $ssl.SetAttribute("serverCertHash",        $Thumbprint)
    $ssl.SetAttribute("controlChannelPolicy",  "SslAllow")
    $ssl.SetAttribute("dataChannelPolicy",     "SslAllow")

    $config.Save($configPath)

    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Host "[OK] Certificado SSL aplicado al sitio FTP." -ForegroundColor Green
}

# ── Crear grupos locales ──────────────────────────────────────
function Set-Grupos {
    foreach ($grupo in @("Reprobados", "Recursadores")) {
        if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grupo -Description "Grupo FTP Practica 7" | Out-Null
            Write-Host "  [OK] Grupo '$grupo' creado." -ForegroundColor Green
        } else {
            Write-Host "  [OK] Grupo '$grupo' ya existe."
        }
    }
}

# ── Permisos NTFS ─────────────────────────────────────────────
function Set-PermisoNTFS {
    param([string]$Ruta, [string]$Usuario, [string]$Permiso = "Modify")
    try {
        $acl  = Get-Acl $Ruta
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Usuario, $Permiso, "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($rule)
        Set-Acl -Path $Ruta -AclObject $acl
    } catch {
        Write-Host "  [ADVERTENCIA] Permiso NTFS en ${Ruta}: $_" -ForegroundColor Yellow
    }
}

# ── Crear usuario FTP local ───────────────────────────────────
function Crear-Usuario {
    param([string]$User, [string]$Grupo)

    if (Get-LocalUser -Name $User -ErrorAction SilentlyContinue) {
        Write-Host "  [OK] Usuario '$User' ya existe."
        return
    }

    $pass = Read-Host "  Contrasena para $User" -AsSecureString
    New-LocalUser -Name $User -Password $pass -FullName $User `
        -Description "Usuario FTP Practica 7" -PasswordNeverExpires | Out-Null
    Add-LocalGroupMember -Group $Grupo -Member $User | Out-Null

    # Estructura IIS FTP User Isolation:
    #   C:\srv\ftp\LocalUser\<usuario>\          <- raiz del usuario
    #   C:\srv\ftp\LocalUser\<usuario>\<usuario> <- carpeta privada
    #   C:\srv\ftp\LocalUser\<usuario>\General   <- junction a General compartido
    #   C:\srv\ftp\LocalUser\<usuario>\<Grupo>   <- junction al directorio de grupo
    $userDir  = "$FTP_BASE\LocalUser\$User"
    $privDir  = "$userDir\$User"
    $genDir   = "$userDir\General"
    $grupoDir = "$userDir\$Grupo"

    New-Item -ItemType Directory -Path $userDir -Force | Out-Null
    New-Item -ItemType Directory -Path $privDir -Force | Out-Null

    if (-not (Test-Path $genDir))   { cmd /c "mklink /J `"$genDir`"   `"$FTP_BASE\General`"" | Out-Null }
    if (-not (Test-Path $grupoDir)) { cmd /c "mklink /J `"$grupoDir`" `"$FTP_BASE\$Grupo`""  | Out-Null }

    Set-PermisoNTFS -Ruta $privDir  -Usuario $User      -Permiso "Modify"
    Set-PermisoNTFS -Ruta $genDir   -Usuario "Everyone"  -Permiso "Modify"
    Set-PermisoNTFS -Ruta $grupoDir -Usuario $Grupo      -Permiso "Modify"

    Write-Host "  [OK] Usuario '$User' creado en grupo '$Grupo'." -ForegroundColor Green
}

# ── Eliminar usuario FTP ──────────────────────────────────────
function Eliminar-Usuario {
    param([string]$User)

    if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
        Write-Host "  [ERROR] El usuario '$User' no existe." -ForegroundColor Red
        return
    }
    $userDir = "$FTP_BASE\LocalUser\$User"
    if (Test-Path $userDir) { Remove-Item $userDir -Recurse -Force }
    Remove-LocalUser -Name $User | Out-Null
    Write-Host "  [OK] Usuario '$User' eliminado." -ForegroundColor Green
}

# ── Cambiar de grupo un usuario ───────────────────────────────
function Cambiar-Grupo {
    param([string]$User)

    if (-not (Get-LocalUser -Name $User -ErrorAction SilentlyContinue)) {
        Write-Host "  [ERROR] El usuario '$User' no existe." -ForegroundColor Red
        return
    }

    $grupoActual = $null
    foreach ($g in @("Reprobados", "Recursadores")) {
        $miembros = Get-LocalGroupMember -Group $g -ErrorAction SilentlyContinue
        if ($miembros | Where-Object { $_.Name -like "*\$User" }) {
            $grupoActual = $g; break
        }
    }

    if (-not $grupoActual) {
        Write-Host "  [ERROR] '$User' no pertenece a Reprobados ni Recursadores." -ForegroundColor Red
        return
    }

    $nuevoGrupo  = if ($grupoActual -eq "Reprobados") { "Recursadores" } else { "Reprobados" }
    $userDir     = "$FTP_BASE\LocalUser\$User"
    $antiguoJunc = "$userDir\$grupoActual"
    $nuevoJunc   = "$userDir\$nuevoGrupo"

    Remove-LocalGroupMember -Group $grupoActual -Member $User -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $nuevoGrupo  -Member $User | Out-Null

    if (Test-Path $antiguoJunc) { cmd /c "rmdir `"$antiguoJunc`"" | Out-Null }
    if (-not (Test-Path $nuevoJunc)) {
        cmd /c "mklink /J `"$nuevoJunc`" `"$FTP_BASE\$nuevoGrupo`"" | Out-Null
    }

    Set-PermisoNTFS -Ruta $nuevoJunc -Usuario $nuevoGrupo -Permiso "Modify"
    Write-Host "  [OK] '$User' movido de '$grupoActual' a '$nuevoGrupo'." -ForegroundColor Green
}

# ── Crear usuario 'repo' para el repositorio privado ─────────
function Crear-UsuarioRepo {
    $repoIsolated = "$FTP_BASE\LocalUser\repo"
    $juncRepo     = "$repoIsolated\repo"

    if (-not (Get-LocalUser -Name "repo" -ErrorAction SilentlyContinue)) {
        $pass = Read-Host "  Contrasena para el usuario 'repo'" -AsSecureString
        New-LocalUser -Name "repo" -Password $pass -FullName "Repositorio FTP" `
            -Description "Usuario repositorio Practica 7" -PasswordNeverExpires | Out-Null
        Write-Host "  [OK] Usuario 'repo' creado." -ForegroundColor Green
    } else {
        Write-Host "  [OK] Usuario 'repo' ya existe."
    }

    # Carpeta de aislamiento
    if (-not (Test-Path $repoIsolated)) {
        New-Item -ItemType Directory -Path $repoIsolated -Force | Out-Null
        Write-Host "  [OK] Carpeta de aislamiento creada: $repoIsolated"
    }

    # Verificar que el repositorio destino existe
    if (-not (Test-Path $FTP_REPO)) {
        Write-Host "  [ERROR] El directorio repositorio '$FTP_REPO' no existe." -ForegroundColor Red
        Write-Host "          Ejecuta prep_repo.ps1 primero para crear y poblar el repositorio." -ForegroundColor Yellow
        return
    }

    # Junction: siempre recrear para asegurar que apunta correcto
    if (Test-Path $juncRepo) {
        cmd /c "rmdir `"$juncRepo`"" | Out-Null
        Write-Host "  [OK] Junction anterior eliminada."
    }
    $resultado = cmd /c "mklink /J `"$juncRepo`" `"$FTP_REPO`"" 2>&1
    Write-Host "  [mklink] $resultado"

    # Verificar que la junction funciona
    if (Test-Path "$juncRepo\http\Windows") {
        Write-Host "  [OK] Junction verificada: $juncRepo -> $FTP_REPO" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] La junction se creo pero la ruta '$juncRepo\http\Windows' no es accesible." -ForegroundColor Red
        Write-Host "          Ejecuta prep_repo.ps1 para poblar el repositorio." -ForegroundColor Yellow
    }

    Set-PermisoNTFS -Ruta $FTP_REPO     -Usuario "repo" -Permiso "ReadAndExecute"
    Set-PermisoNTFS -Ruta $repoIsolated -Usuario "repo" -Permiso "ReadAndExecute"

    Write-Host "[OK] Usuario 'repo' listo. Repositorio en: $FTP_REPO" -ForegroundColor Green
    Write-Host "     Ruta FTP del usuario: /repo/http/Windows" -ForegroundColor Cyan
}

# ── Configuracion base completa FTP ──────────────────────────
function Set-FtpConf {
    Write-Host ""
    Write-Host "  Configurando servidor FTP completo ..."
    Instalar-FTP
    Crear-EstructuraFTP
    Set-FtpSitio
    Set-Grupos
    Write-Host "[OK] Configuracion base FTP completada." -ForegroundColor Green
}

# ── Estado del servicio FTP ───────────────────────────────────
function Get-EstadoFTP {
    foreach ($svc in @("W3SVC", "ftpsvc")) {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        $estado = if ($s) { $s.Status } else { "no instalado" }
        Write-Host "  Servicio '$svc': $estado" -ForegroundColor Cyan
    }
    if (Test-Path $APPCMD) {
        $sitio = & $APPCMD list site "/name:$FTP_SITE" 2>$null
        $estado = if ($sitio) { $sitio } else { "no encontrado" }
        Write-Host "  Sitio '$FTP_SITE': $estado" -ForegroundColor Cyan
    }
}

# ── Diagnostico completo para el usuario 'repo' ───────────────
# Verifica toda la cadena necesaria para que el cliente FTP funcione:
#   servicio FTP activo -> usuario repo existe -> carpeta aislamiento ->
#   junction repo -> contenido del repositorio -> permisos NTFS
function Diagnostico-Repo {
    Write-Host ""
    Write-Host "=== Diagnostico usuario repositorio 'repo' ===" -ForegroundColor Cyan

    # 1. Servicio FTP
    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "  [OK] Servicio ftpsvc: Running" -ForegroundColor Green
    } else {
        $st = if ($svc) { $svc.Status } else { "no instalado" }
        Write-Host "  [FAIL] Servicio ftpsvc: $st  -> Ejecuta opcion 2 (Instalar y configurar IIS FTP)" -ForegroundColor Red
    }

    # 2. Usuario repo
    $usr = Get-LocalUser -Name "repo" -ErrorAction SilentlyContinue
    if ($usr) {
        Write-Host "  [OK] Usuario 'repo' existe" -ForegroundColor Green
        if (-not $usr.Enabled) {
            Write-Host "  [WARN] Usuario 'repo' esta DESHABILITADO" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [FAIL] Usuario 'repo' NO existe -> Ejecuta opcion 6 (Crear usuario repositorio)" -ForegroundColor Red
    }

    # 3. Carpeta de aislamiento
    $isolated = "$FTP_BASE\LocalUser\repo"
    if (Test-Path $isolated) {
        Write-Host "  [OK] Carpeta aislamiento: $isolated" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Falta carpeta: $isolated" -ForegroundColor Red
    }

    # 4. Junction
    $junc = "$isolated\repo"
    if (Test-Path $junc) {
        $item = Get-Item $junc -ErrorAction SilentlyContinue
        $tipo = if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { "Junction" } else { "Directorio normal" }
        Write-Host "  [OK] $junc ($tipo)" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] Falta junction: $junc -> Re-ejecuta opcion 6" -ForegroundColor Red
    }

    # 5. Contenido del repo
    $httpDir = "$FTP_REPO\http\Windows"
    if (Test-Path $httpDir) {
        $subs = Get-ChildItem $httpDir -Directory -ErrorAction SilentlyContinue
        if ($subs) {
            Write-Host "  [OK] Contenido en $httpDir :" -ForegroundColor Green
            foreach ($s in $subs) {
                $archivos = (Get-ChildItem $s.FullName -File -ErrorAction SilentlyContinue).Count
                Write-Host "       $($s.Name) ($archivos archivo(s))"
            }
        } else {
            Write-Host "  [WARN] $httpDir existe pero esta VACIO -> Ejecuta prep_repo.ps1" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [FAIL] No existe: $httpDir -> Ejecuta prep_repo.ps1" -ForegroundColor Red
    }

    # 6. Permisos: repo puede leer FTP_REPO
    $acl = Get-Acl $FTP_REPO -ErrorAction SilentlyContinue
    if ($acl) {
        $tienePermiso = $acl.Access | Where-Object {
            $_.IdentityReference -like "*repo*" -and
            $_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadData
        }
        if ($tienePermiso) {
            Write-Host "  [OK] 'repo' tiene permisos de lectura en $FTP_REPO" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] 'repo' puede no tener permisos de lectura en $FTP_REPO" -ForegroundColor Yellow
            Write-Host "         Re-ejecuta opcion 6 para reasignar permisos." -ForegroundColor Yellow
        }
    }

    # 7. Puerto 21 abierto localmente
    $listener = Get-NetTCPConnection -LocalPort 21 -State Listen -ErrorAction SilentlyContinue
    if ($listener) {
        Write-Host "  [OK] Puerto 21 escuchando (PID $($listener[0].OwningProcess))" -ForegroundColor Green
    } else {
        Write-Host "  [WARN] Puerto 21 NO esta en estado Listen. El sitio FTP puede no estar iniciado." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "  Ruta que vera el cliente FTP al conectar como 'repo':"
    Write-Host "    /             -> $isolated" -ForegroundColor Cyan
    Write-Host "    /repo/        -> $FTP_REPO" -ForegroundColor Cyan
    Write-Host "    /repo/http/Windows -> $httpDir" -ForegroundColor Cyan
}