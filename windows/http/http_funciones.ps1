# ==============================================================================
# http_funciones.ps1  -  Funciones de aprovisionamiento HTTP para Windows Server
# Servicios soportados: IIS (obligatorio), Apache Win64, Nginx para Windows
# ==============================================================================

# -- Verificar ejecucion como Administrador ------------------------------------
function Test-Admin {
    $current = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Error "[ERROR] Este script debe ejecutarse como Administrador."
        exit 1
    }
}

# ==============================================================================
# HELPERS - VERSIONES Y VALIDACIONES
# ==============================================================================

# -- Verificar que Chocolatey este disponible ----------------------------------
function Assert-Chocolatey {
    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"

    # Paso 1: recargar PATH del sistema (por si choco fue instalado en esta sesion)
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    # Paso 2: si el exe existe en la ruta conocida, crear alias y listo
    if (Test-Path $chocoExe) {
        Set-Alias -Name choco -Value $chocoExe -Scope Global -ErrorAction SilentlyContinue
        return $true
    }

    # Paso 3: buscar choco en rutas alternativas del directorio Chocolatey
    $altPaths = @(
        "C:\ProgramData\chocolatey\choco.exe",
        "C:\ProgramData\chocolatey\bin\choco.exe"
    )
    foreach ($alt in $altPaths) {
        if (Test-Path $alt) {
            Set-Alias -Name choco -Value $alt -Scope Global -ErrorAction SilentlyContinue
            Write-Host "[OK] Chocolatey encontrado en: $alt" 
            return $true
        }
    }

    # Paso 4: no existe, instalar desde internet
    Write-Host "[INFO] Chocolatey no encontrado. Instalando..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = `
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    try {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1'))
    } catch {
        Write-Error "[ERROR] No se pudo instalar Chocolatey: $_"
        return $false
    }

    # Recargar PATH tras la instalacion
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (Test-Path $chocoExe) {
        Set-Alias -Name choco -Value $chocoExe -Scope Global -ErrorAction SilentlyContinue
        Write-Host "[OK] Chocolatey instalado correctamente."
        return $true
    }

    Write-Error "[ERROR] No se pudo instalar Chocolatey. Verifica tu conexion."
    return $false
}

# -- Obtener versiones disponibles de un paquete via Chocolatey ---------------
function Get-ChocoVersiones {
    param([string]$Paquete)

    Write-Host "[INFO] Consultando versiones de '$Paquete' en Chocolatey..." 

    # Ejecutar choco directamente por ruta para evitar problemas de PATH
    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
    if (-not (Test-Path $chocoExe)) { $chocoExe = "choco" }

    # choco search --exact --all-versions devuelve: Paquete|version
    $salidaRaw = & $chocoExe search $Paquete --exact --all-versions --limit-output 2>$null

    $versiones = @()
    foreach ($linea in $salidaRaw) {
        $linea = "$linea".Trim()
        if ($linea -match '^\S+\|(\d[\d\.\-]+)') {
            $versiones += $Matches[1]
        }
    }

    # Tomar las 8 mas recientes
    $versiones = $versiones | Select-Object -First 8

    if ($versiones.Count -eq 0) {
        Write-Warning "[ADVERTENCIA] No se encontraron versiones para '$Paquete' en Chocolatey."
        return @()
    }

    return $versiones
}

# -- Mostrar menu de versiones y devolver la elegida --------------------------
function Select-Version {
    param(
        [string]$Paquete,
        [string[]]$Versiones
    )

    $total = $Versiones.Count
    if ($total -eq 0) { return $null }

    $ltsIdx = [math]::Floor($total / 2)

    Write-Host ""
    Write-Host "  Versiones disponibles de $Paquete :" 

    for ($i = 0; $i -lt $total; $i++) {
        $label = ""
        if ($i -eq 0)                        { $label = "  (Latest)" }
        elseif ($i -eq $ltsIdx -and $total -ge 3) { $label = "  (LTS / Estable)" }
        elseif ($i -eq ($total - 1) -and $total -ge 2) { $label = "  (Oldest)" }
        Write-Host ("  {0}) {1}{2}" -f ($i + 1), $Versiones[$i], $label)
    }

    do {
        $eleccion = Read-Host "`n  ?Cual version deseas instalar? [1-$total]"
        $eleccion = $eleccion.Trim()
        if ($eleccion -match '^\d+$' -and [int]$eleccion -ge 1 -and [int]$eleccion -le $total) {
            return $Versiones[[int]$eleccion - 1]
        }
        Write-Warning "  Opcion invalida. Ingresa un numero entre 1 y $total."
    } while ($true)
}

# -- Validar rango de puerto ---------------------------------------------------
function Test-PuertoValido {
    param([string]$Puerto)
    if ($Puerto -match '^\d+$') {
        $p = [int]$Puerto
        return ($p -ge 1 -and $p -le 65535)
    }
    return $false
}

# -- Validar que el puerto no sea reservado para otros servicios ---------------
function Test-PuertoNoReservado {
    param([int]$Puerto)

    # Puertos reservados para servicios que NO son HTTP
    $reservados = @(21, 22, 25, 53, 110, 143, 3306, 5432, 6379, 27017, 3389, 445, 139)
    if ($Puerto -in $reservados) {
        Write-Error "[ERROR] El puerto $Puerto esta reservado (SSH=22, RDP=3389, MySQL=3306, etc.)."
        return $false
    }
    if ($Puerto -lt 1024) {
        Write-Warning "[ADVERTENCIA] El puerto $Puerto es privilegiado (<1024). Requiere permisos elevados."
    }
    return $true
}

# -- Verificar si un puerto esta en uso ---------------------------------------
function Test-PuertoEnUso {
    param([int]$Puerto)
    $resultado = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    return $resultado.TcpTestSucceeded
}

# -- Detectar que proceso ocupa un puerto y a que servicio HTTP pertenece ------
function Get-ServicioEnPuerto {
    param([int]$Puerto)

    $lineas = netstat -ano 2>$null | Select-String ":$Puerto\s"
    foreach ($linea in $lineas) {
        $partes = "$linea".Trim() -split '\s+'
        $pid = $partes[-1]
        if ($pid -match '^\d+$') {
            $proc = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
            if ($proc) {
                $nombre = $proc.Name.ToLower()
                if ($nombre -match 'nginx')          { return "nginx" }
                if ($nombre -match 'httpd|apache')   { return "apache" }
                if ($nombre -match 'w3wp|iisexpress') { return "iis" }
                return $nombre   # proceso desconocido
            }
        }
    }
    return $null
}

# -- Resolver conflicto cuando dos servicios HTTP quieren el mismo puerto ------
# Regla: IIS siempre toma el puerto pedido; Nginx/Apache se mueven a puerto+1
function Resolve-ConflictoPuerto {
    param(
        [string]$ServicioNuevo,   # servicio que se esta instalando/cambiando
        [int]$PuertoDeseado       # puerto que quiere usar
    )

    $ocupadoPor = Get-ServicioEnPuerto -Puerto $PuertoDeseado
    if (-not $ocupadoPor) { return $PuertoDeseado }   # puerto libre, sin conflicto

    if ($ocupadoPor -eq $ServicioNuevo) { return $PuertoDeseado }  # el mismo servicio, OK

    Write-Warning "[CONFLICTO] Puerto $PuertoDeseado esta ocupado por '$ocupadoPor'."

    # --- Estrategia de resolucion ---
    # IIS tiene prioridad sobre Nginx/Apache; Nginx/Apache ceden al siguiente puerto libre
    $moverServicioActual = $false
    $puertoCedido        = $PuertoDeseado

    if ($ServicioNuevo -eq "iis") {
        # IIS quiere el puerto: mover el servicio que lo ocupa
        $moverServicioActual = $true
        $puertoCedido = $PuertoDeseado + 1
        # Buscar el siguiente puerto realmente libre
        while (Get-ServicioEnPuerto -Puerto $puertoCedido) { $puertoCedido++ }
        Write-Host "[INFO] IIS tomara el puerto $PuertoDeseado. '$ocupadoPor' sera movido al puerto $puertoCedido."
        Set-PuertoServicio -Servicio $ocupadoPor -NuevoPuerto $puertoCedido
        Write-Host "[OK] '$ocupadoPor' movido al puerto $puertoCedido."
        return $PuertoDeseado
    } else {
        # Nginx/Apache quieren el puerto ocupado por IIS u otro: ceder
        $puertoCedido = $PuertoDeseado + 1
        while (Get-ServicioEnPuerto -Puerto $puertoCedido) { $puertoCedido++ }
        Write-Host "[INFO] '$ServicioNuevo' no puede usar el puerto $PuertoDeseado (ocupado por '$ocupadoPor')."
        Write-Host "[INFO] '$ServicioNuevo' usara el puerto alternativo: $puertoCedido."
        return $puertoCedido
    }
}

# -- Detectar dinamicamente la ruta de instalacion de Apache via Chocolatey ----
function Find-ApacheBase {
    # Rutas fijas conocidas
    $candidatos = @(
        "C:\Apache24",
        "C:\tools\Apache24",
        "$env:APPDATA\Apache24",
        "$env:SystemDrive\Apache24",
        "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24",
        "C:\Program Files\Apache Group\Apache2",
        "C:\Program Files (x86)\Apache Group\Apache2"
    )

    # Busqueda dinamica en lib de Chocolatey (subdirectorios de apache*)
    $chocoLib = "C:\ProgramData\chocolatey\lib"
    if (Test-Path $chocoLib) {
        Get-ChildItem $chocoLib -Directory -Filter "apache*" | ForEach-Object {
            foreach ($sub in @("tools\Apache24", "tools", "Apache24")) {
                $ruta = Join-Path $_.FullName $sub
                if (Test-Path "$ruta\conf\httpd.conf") {
                    $candidatos = @($ruta) + $candidatos
                }
            }
        }
    }

    # Busqueda en APPDATA por si Chocolatey extrajo ahi
    if (Test-Path $env:APPDATA) {
        Get-ChildItem $env:APPDATA -Directory -Filter "Apache*" -ErrorAction SilentlyContinue |
            ForEach-Object {
                if (Test-Path "$($_.FullName)\conf\httpd.conf") {
                    $candidatos = @($_.FullName) + $candidatos
                }
            }
    }

    foreach ($base in $candidatos) {
        if (Test-Path "$base\conf\httpd.conf") {
            return $base
        }
    }
    return $null
}

# -- Devolver directorio web raiz segun servicio -------------------------------
function Get-WebRoot {
    param([string]$Servicio)
    switch ($Servicio) {
        "iis"    { return "C:\inetpub\wwwroot" }
        "apache" {
            if ($script:ApacheBase -and (Test-Path $script:ApacheBase)) {
                return "$script:ApacheBase\htdocs"
            }
            $base = Find-ApacheBase
            if ($base) { return "$base\htdocs" }
            return "C:\Apache24\htdocs"   # fallback
        }
        "nginx"  { return "C:\nginx\html" }
        default  { return "C:\inetpub\wwwroot" }
    }
}

# -- Devolver usuario dedicado segun servicio ----------------------------------
function Get-ServiceUser {
    param([string]$Servicio)
    switch ($Servicio) {
        "iis"    { return "IIS_IUSRS" }
        "apache" { return "ApacheSvc" }
        "nginx"  { return "NginxSvc" }
        default  { return "IIS_IUSRS" }
    }
}

# ==============================================================================
# 1. CONSULTA DE VERSIONES DINAMICA
# ==============================================================================

# -- Versiones de IIS (roles disponibles en el sistema operativo) --------------
function Get-VersionesIIS {
    # IIS se instala como rol del SO; la version depende de Windows Server
    $osCaption = (Get-WmiObject Win32_OperatingSystem).Caption
    $osVersion = (Get-WmiObject Win32_OperatingSystem).Version

    Write-Host "[INFO] Sistema operativo detectado: $osCaption ($osVersion)" 

    # Mapeo de build de Windows Server -> version IIS
    $iisVersionMap = @{
        "10.0" = "IIS 10.0 (Windows Server 2016/2019/2022)"
        "6.3"  = "IIS 8.5 (Windows Server 2012 R2)"
        "6.2"  = "IIS 8.0 (Windows Server 2012)"
        "6.1"  = "IIS 7.5 (Windows Server 2008 R2)"
    }

    $majorMinor = ($osVersion -split '\.')[0..1] -join '.'
    $iisLabel = if ($iisVersionMap.ContainsKey($majorMinor)) { $iisVersionMap[$majorMinor] } else { "IIS (version segun SO)" }

    Write-Host ""
    Write-Host "  Versiones de IIS disponibles para instalacion:" 
    Write-Host "  1) $iisLabel  (instalacion obligatoria segun practica)"
    Write-Host ""

    # IIS solo tiene una opcion (la del SO actual), confirmar instalacion
    do {
        $confirm = Read-Host "  ?Confirmar instalacion de IIS? [S/N]"
        $confirm = $confirm.Trim().ToUpper()
    } while ($confirm -notin @("S", "N"))

    if ($confirm -eq "N") { return $null }
    return $iisLabel
}

# -- Versiones de Apache Win64 via Chocolatey ----------------------------------
# Nombre real del paquete en Chocolatey community: "apache-httpd"
# Si no existe, intentar "httpd" como segundo nombre conocido
$script:ApachePkg = $null   # se fija en Get-VersionesApache y se reutiliza en Install-Apache

function Get-VersionesApache {
    if (-not (Assert-Chocolatey)) { return $null }

    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
    if (-not (Test-Path $chocoExe)) { $chocoExe = "choco" }

    # Buscar el paquete exacto disponible en el repositorio
    $candidatos = @("apache-httpd", "httpd", "apache")
    foreach ($pkg in $candidatos) {
        Write-Host "[INFO] Buscando paquete '$pkg' en Chocolatey..." 
        $versiones = Get-ChocoVersiones -Paquete $pkg
        if ($versiones.Count -gt 0) {
            $script:ApachePkg = $pkg
            Write-Host "[OK] Paquete encontrado: $pkg" 
            return $versiones
        }
    }

    # Si ninguno tiene versiones exactas, buscar por termino libre
    Write-Host "[INFO] Buscando por termino libre 'apache'..." 
    $busqueda = & $chocoExe search apache --limit-output 2>$null |
        Select-Object -First 5
    if ($busqueda) {
        Write-Host "[INFO] Paquetes disponibles relacionados con Apache:"
        $busqueda | ForEach-Object { Write-Host "  $_" }
        Write-Host ""
        # Extraer el primer nombre de paquete de la busqueda
        $primerPkg = ("$($busqueda[0])" -split '\|')[0].Trim()
        if ($primerPkg) {
            $versiones = Get-ChocoVersiones -Paquete $primerPkg
            if ($versiones.Count -gt 0) {
                $script:ApachePkg = $primerPkg
                return $versiones
            }
        }
    }

    Write-Warning "[ADVERTENCIA] No se encontro ningun paquete Apache en Chocolatey."
    return @()
}

# -- Versiones de Nginx para Windows via Chocolatey ---------------------------
function Get-VersionesNginx {
    if (-not (Assert-Chocolatey)) { return $null }
    $versiones = Get-ChocoVersiones -Paquete "nginx"
    return $versiones
}

# ==============================================================================
# 2. INSTALACION SILENCIOSA
# ==============================================================================

function Install-IIS {
    param([int]$Puerto)

    Write-Host ""
    Write-Host "===================================================" 
    Write-Host "  Instalando IIS (Windows Server Role)..." 
    Write-Host "===================================================" 

    # Instalar IIS con caracteristicas basicas y modulos de seguridad
    $features = @(
        "Web-Server",
        "Web-Common-Http",
        "Web-Default-Doc",
        "Web-Static-Content",
        "Web-Http-Errors",
        "Web-Http-Logging",
        "Web-Request-Monitor",
        "Web-Security",
        "Web-Filtering",
        "Web-Mgmt-Tools",
        "Web-Mgmt-Console",
        "Web-Http-Redirect"
    )

    foreach ($feat in $features) {
        $state = (Get-WindowsFeature -Name $feat).InstallState
        if ($state -ne "Installed") {
            Install-WindowsFeature -Name $feat -IncludeManagementTools -WarningAction SilentlyContinue | Out-Null
            Write-Host "[OK] Rol instalado: $feat"
        } else {
            Write-Host "[INFO] Ya instalado: $feat"
        }
    }

    # Importar modulo WebAdministration para gestionar IIS
    Import-Module WebAdministration -ErrorAction Stop

    Write-Host "[OK] IIS instalado correctamente."
    return $true
}

function Install-Apache {
    param([string]$Version, [int]$Puerto)

    Write-Host ""
    Write-Host "===================================================" 
    Write-Host "  Instalando Apache Win64 version $Version..." 
    Write-Host "===================================================" 

    if (-not (Assert-Chocolatey)) { return $false }

    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
    if (-not (Test-Path $chocoExe)) { $chocoExe = "choco" }

    # El paquete apache-httpd de Chocolatey extrae el zip a $env:APPDATA por defecto.
    # Pasamos /installLocation para forzar extraccion en C:\Apache24
    $destino = "C:\Apache24"
    Write-Host "[INFO] Destino de instalacion: $destino" 

    $pkg = if ($script:ApachePkg) { $script:ApachePkg } else { "apache-httpd" }

    Write-Host "[INFO] Ejecutando: choco install $pkg --version=$Version /installLocation=$destino ..." 
    & $chocoExe install $pkg `
        --version=$Version `
        --package-parameters="/installLocation:$destino /Port:$Puerto" `
        -y --no-progress --force 2>&1 | Tee-Object -Variable salidaChoco

    # Verificar si la instalacion extrajo los archivos correctamente
    if (Test-Path "$destino\conf\httpd.conf") {
        Write-Host "[OK] Apache $Version instalado correctamente en $destino." 
        $script:ApacheBase = $destino
        $script:ApachePkg  = $pkg
        return $true
    }

    # Si Chocolatey igualmente extrajo en APPDATA, mover a C:\Apache24
    $appdataApache = "$env:APPDATA\Apache24"
    if (Test-Path "$appdataApache\conf\httpd.conf") {
        Write-Host "[INFO] Apache extraido en $appdataApache. Moviendo a $destino..." 
        if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
        Move-Item $appdataApache $destino
        if (Test-Path "$destino\conf\httpd.conf") {
            Write-Host "[OK] Apache movido a $destino correctamente." 
            $script:ApacheBase = $destino
            $script:ApachePkg  = $pkg
            return $true
        }
    }

    # Ultimo recurso: extraer el zip manualmente desde el cache de Chocolatey
    Write-Host "[INFO] Intentando extraccion manual del zip..." 
    $zipDir  = "C:\ProgramData\chocolatey\lib\$pkg\tools"
    $zipFile = Get-ChildItem $zipDir -Filter "*x64*.zip" -ErrorAction SilentlyContinue |
               Select-Object -First 1
    if (-not $zipFile) {
        $zipFile = Get-ChildItem $zipDir -Filter "*.zip" -ErrorAction SilentlyContinue |
                   Select-Object -First 1
    }

    if ($zipFile) {
        Write-Host "[INFO] Extrayendo $($zipFile.Name) ..." 

        # Detener servicio Apache si esta corriendo para liberar archivos bloqueados
        $svcApache = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($svcApache) {
            Stop-Service $svcApache.Name -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            # Matar cualquier proceso httpd residual
            Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }

        # Usar robocopy + rd para eliminar el directorio con archivos bloqueados
        # (mas robusto que Remove-Item en Windows)
        if (Test-Path $destino) {
            Write-Host "[INFO] Eliminando instalacion anterior en $destino..." 
            & cmd /c "rd /s /q `"$destino`"" 2>$null
            Start-Sleep -Seconds 1
        }

        # Extraer a una carpeta temporal primero para evitar la doble carpeta
        $tempDir = "C:\Apache24_temp_extract"
        if (Test-Path $tempDir) { & cmd /c "rd /s /q `"$tempDir`"" 2>$null }
        Expand-Archive -Path $zipFile.FullName -DestinationPath $tempDir -Force

        # El zip del paquete apache-httpd extrae como: tempDir\Apache24\conf\httpd.conf
        # Detectar la subcarpeta real donde quedo httpd.conf
        $subConf = Get-ChildItem $tempDir -Recurse -Filter "httpd.conf" -ErrorAction SilentlyContinue |
                   Select-Object -First 1

        if ($subConf) {
            # $subConf.DirectoryName es la carpeta "conf" donde esta httpd.conf
            # Su padre (.Parent.FullName) es la carpeta base de Apache (Apache24)
            $baseReal = (Get-Item $subConf.DirectoryName).Parent.FullName
            Write-Host "[INFO] Carpeta base detectada: $baseReal" 

            # Mover la carpeta base detectada al destino final C:\Apache24
            if ($baseReal -ne $destino) {
                if (Test-Path $destino) { & cmd /c "rd /s /q `"$destino`"" 2>$null; Start-Sleep 1 }
                Move-Item $baseReal $destino -Force
                Start-Sleep -Seconds 1
            }
            # Limpiar carpeta temporal
            if (Test-Path $tempDir) { & cmd /c "rd /s /q `"$tempDir`"" 2>$null }

            if (Test-Path "$destino\conf\httpd.conf") {
                Write-Host "[OK] Apache $Version extraido correctamente en $destino." 

                # Registrar Apache como servicio de Windows si no existe
                Invoke-RegistrarApacheServicio -ApacheBase $destino -Puerto $Puerto

                $script:ApacheBase = $destino
                $script:ApachePkg  = $pkg
                return $true
            } else {
                Write-Warning "[ADVERTENCIA] Move-Item completo pero no se encuentra httpd.conf en $destino"
                # Buscar de nuevo por si quedo en subcarpeta
                $recheck = Get-ChildItem $destino -Recurse -Filter "httpd.conf" -ErrorAction SilentlyContinue |
                           Select-Object -First 1
                if ($recheck) {
                    $realBase2 = (Get-Item $recheck.DirectoryName).Parent.FullName
                    Write-Host "[INFO] httpd.conf encontrado en: $realBase2" 
                    $script:ApacheBase = $realBase2
                    $script:ApachePkg  = $pkg
                    Invoke-RegistrarApacheServicio -ApacheBase $realBase2 -Puerto $Puerto
                    return $true
                }
            }
        }
        # Limpiar si algo fallo
        if (Test-Path $tempDir) { & cmd /c "rd /s /q `"$tempDir`"" 2>$null }
    }

    Write-Error "[ERROR] No se encontro httpd.conf tras la instalacion. Revisa el paquete Chocolatey."
    return $false
}

# -- Registrar Apache como servicio de Windows --------------------------------
function Invoke-RegistrarApacheServicio {
    param([string]$ApacheBase, [int]$Puerto)

    $httpdExe = "$ApacheBase\bin\httpd.exe"
    if (-not (Test-Path $httpdExe)) {
        Write-Warning "[ADVERTENCIA] No se encontro httpd.exe en $ApacheBase\bin"
        return
    }

    # Crear carpeta logs si no existe (Apache falla al iniciar si no existe)
    $logsDir = "$ApacheBase\logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        Write-Host "[OK] Carpeta logs creada: $logsDir"
    }

    # Verificar si ya existe el servicio
    $svcExiste = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svcExiste) {
        # El servicio existe pero puede apuntar a la ruta ANTERIOR (antes de mover archivos)
        # Siempre actualizar la ruta binaria para que apunte a $ApacheBase correcto
        $rutaActual = (& sc.exe qc $svcExiste.Name | Select-String "NOMBRE_RUTA_BINARIO|BINARY_PATH_NAME") -replace ".*:\s*", "" -replace '"', '' -replace '\s*-k.*', ''
        $rutaActual = $rutaActual.Trim()
        Write-Host "[INFO] Servicio '$($svcExiste.Name)' encontrado. Ruta actual: $rutaActual" 

        if ($rutaActual -ne $httpdExe) {
            Write-Host "[INFO] Actualizando ruta del servicio a: $httpdExe" 
            & sc.exe config $svcExiste.Name binPath= "`"$httpdExe`" -k runservice" | Out-Null
            Write-Host "[OK] Ruta del servicio actualizada." 
        } else {
            Write-Host "[INFO] Ruta del servicio ya es correcta."
        }
        return
    }

    Write-Host "[INFO] Registrando Apache como servicio de Windows..." 

    # httpd.exe -k install registra el servicio usando la config en conf\httpd.conf
    $proc = Start-Process -FilePath $httpdExe `
                          -ArgumentList "-k", "install", "-n", "Apache" `
                          -Wait -PassThru -NoNewWindow `
                          -RedirectStandardError "$env:TEMP\apache_install.log"
    $logContent = if (Test-Path "$env:TEMP\apache_install.log") {
        Get-Content "$env:TEMP\apache_install.log" -Raw
    } else { "" }

    if ($proc.ExitCode -eq 0) {
        Write-Host "[OK] Servicio Apache registrado correctamente." 
    } else {
        Write-Warning "[ADVERTENCIA] httpd.exe -k install retorno: $logContent"
        # Registrar via sc.exe como fallback
        & sc.exe create Apache binPath= "`"$httpdExe`" -k runservice" start= auto | Out-Null
        Write-Host "[INFO] Servicio registrado via sc.exe."
    }
}

function Install-Nginx {
    param([string]$Version, [int]$Puerto)

    Write-Host ""
    Write-Host "===================================================" 
    Write-Host "  Instalando Nginx para Windows version $Version..." 
    Write-Host "===================================================" 

    if (-not (Assert-Chocolatey)) { return $false }

    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
    if (-not (Test-Path $chocoExe)) { $chocoExe = "choco" }

    & $chocoExe install nginx --version=$Version -y --no-progress 2>&1 | Out-Null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Nginx $Version instalado." 
        return $true
    } else {
        Write-Error "[ERROR] Fallo la instalacion de Nginx $Version."
        return $false
    }
}


# -- Encontrar httpd.conf de Apache dinamicamente ------------------------------
function Find-ApacheConf {
    # Si la instalacion ya fijo la base, usarla directamente
    if ($script:ApacheBase -and (Test-Path "$script:ApacheBase\conf\httpd.conf")) {
        return "$script:ApacheBase\conf\httpd.conf"
    }
    $base = Find-ApacheBase
    if ($base -and (Test-Path "$base\conf\httpd.conf")) {
        $script:ApacheBase = $base   # cachear para proximas llamadas
        return "$base\conf\httpd.conf"
    }
    return $null
}

# ==============================================================================
# 3. CAMBIO DE PUERTO
# ==============================================================================

function Set-PuertoIIS {
    param([int]$NuevoPuerto)

    Write-Host ""
    Write-Host "=== Cambiando puerto de IIS a $NuevoPuerto ===" 

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Obtener binding actual del Default Web Site
    $site    = "Default Web Site"
    $binding = Get-WebBinding -Name $site -Protocol "http" -ErrorAction SilentlyContinue

    if ($binding) {
        # Eliminar binding anterior
        Remove-WebBinding -Name $site -Protocol "http" -ErrorAction SilentlyContinue
        Write-Host "[INFO] Binding anterior eliminado."
    }

    # Crear nuevo binding con el puerto elegido
    New-WebBinding -Name $site -Protocol "http" -Port $NuevoPuerto -IPAddress "*"
    Write-Host "[OK] IIS ahora escucha en el puerto $NuevoPuerto."

    # Reiniciar IIS
    Restart-Service W3SVC -Force
    Write-Host "[OK] IIS reiniciado."
}

function Set-PuertoApache {
    param([int]$NuevoPuerto)

    Write-Host ""
    Write-Host "=== Cambiando puerto de Apache a $NuevoPuerto ===" 

    # Rutas posibles de httpd.conf en instalacion Chocolatey
    $confFile = Find-ApacheConf
    if (-not $confFile) {
        Write-Error "[ERROR] No se encontro httpd.conf de Apache. Verifica la instalacion."
        return $false
    }

    $backup = "${confFile}.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $confFile $backup
    Write-Host "[INFO] Backup creado: $backup"

    # Detener Apache antes de editar conf (evita bloqueos de archivo)
    $svc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($svc) {
        Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
        Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Host "[INFO] Servicio Apache detenido." 
    }

    # Editar httpd.conf con el servicio detenido (sin bloqueos de archivo)
    (Get-Content $confFile) -replace '^Listen \d+', "Listen $NuevoPuerto" |
        Set-Content $confFile -Encoding UTF8
    Write-Host "[OK] Puerto cambiado a $NuevoPuerto en httpd.conf."

    # Crear logs/ si no existe (Apache no arranca sin ella)
    $logsDir = (Split-Path $confFile -Parent | Split-Path -Parent) + "\logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
        Write-Host "[OK] Carpeta logs creada."
    }

    # Iniciar el servicio
    if ($svc) {
        Start-Service $svc.Name -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        $svc.Refresh()
        if ($svc.Status -eq "Running") {
            Write-Host "[OK] Apache iniciado en puerto $NuevoPuerto." 
        } else {
            # Fallback: arrancar con httpd.exe directamente
            $base = if ($script:ApacheBase) { $script:ApacheBase } else { Find-ApacheBase }
            if ($base) {
                Start-Process "$base\bin\httpd.exe" -ArgumentList "-k","start" -NoNewWindow
                Start-Sleep -Seconds 2
                Write-Host "[OK] Apache arrancado via httpd.exe en puerto $NuevoPuerto." 
            } else {
                Write-Warning "[ADVERTENCIA] No se pudo iniciar Apache. Revisa logs\error.log"
            }
        }
    }
    return $true
}

function Find-NginxExeDir {
    $posibles = @(
        "C:\tools\nginx-1.29.1",
        "C:\tools\nginx-1.29.5",
        "C:\tools\nginx-1.29.4",
        "C:\tools\nginx-1.29.3",
        "C:\tools\nginx-1.29.2",
        "C:\tools\nginx-1.29.0",
        "C:\tools\nginx-1.27.5",
        "C:\tools\nginx",
        "C:\nginx"
    )
    foreach ($ruta in $posibles) {
        if (Test-Path "$ruta\nginx.exe") { return $ruta }
    }
    # Busqueda dinamica por si la version no esta en la lista
    $encontrado = Get-ChildItem "C:\tools" -Filter "nginx.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($encontrado) { return $encontrado.DirectoryName }
    return $null
}

function Set-PuertoNginx {
    param([int]$NuevoPuerto)

    Write-Host ""
    Write-Host "=== Cambiando puerto de Nginx a $NuevoPuerto ===" 

    $posibles = @(
        "C:\nginx\conf\nginx.conf",
        "C:\tools\nginx\conf\nginx.conf",
        "C:\tools\nginx-1.29.1\conf\nginx.conf",
        "C:\ProgramData\chocolatey\lib\nginx\tools\nginx\conf\nginx.conf"
    )
    # Busqueda dinamica por si la version cambia
    if (-not ($posibles | Where-Object { Test-Path $_ })) {
        $found = Get-ChildItem "C:\tools" -Filter "nginx.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
        if ($found) { $posibles += $found }
    }

    $confFile = $null
    foreach ($ruta in $posibles) {
        if (Test-Path $ruta) { $confFile = $ruta; break }
    }

    if (-not $confFile) {
        Write-Error "[ERROR] No se encontro nginx.conf."
        return $false
    }

    $backup = "${confFile}.bak_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $confFile $backup
    Write-Host "[INFO] Backup creado: $backup"

    # Reemplazar directiva listen - escuchar en todas las interfaces
    $contenido = Get-Content $confFile -Raw
    $contenido = $contenido -replace 'listen\s+[\d\.]*:?\d+;', "listen 0.0.0.0:$NuevoPuerto;"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($confFile, $contenido, $utf8NoBom)

    Write-Host "[OK] Nginx ahora escucha en el puerto $NuevoPuerto (todas las interfaces)."

    # Reiniciar nginx - buscar exe dinamicamente sin depender del proceso
    $nginxExe = Find-NginxExeDir
    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($proc) { $proc | Stop-Process -Force; Start-Sleep -Seconds 1 }
    if ($nginxExe) {
        Start-Process "$nginxExe\nginx.exe" -WorkingDirectory $nginxExe
        Write-Host "[OK] Nginx reiniciado desde: $nginxExe"
    } else {
        Write-Warning "[ADVERTENCIA] No se pudo localizar nginx.exe. Reinicia manualmente."
    }
    return $true
}

# -- Dispatcher de cambio de puerto -------------------------------------------
function Set-PuertoServicio {
    param([string]$Servicio, [int]$NuevoPuerto)

    if (-not (Test-PuertoValido -Puerto $NuevoPuerto)) {
        Write-Error "[ERROR] Puerto invalido: $NuevoPuerto."
        return
    }
    if (-not (Test-PuertoNoReservado -Puerto $NuevoPuerto)) { return }

    if (Test-PuertoEnUso -Puerto $NuevoPuerto) {
        # Verificar si lo usa el propio Apache/Nginx que estamos configurando
        $netstat = netstat -ano | Select-String ":$NuevoPuerto " | Out-String
        $pidEnUso = ($netstat -split '\s+' | Where-Object { $_ -match '^\d+$' } | Select-Object -Last 1)
        $procEnUso = if ($pidEnUso) { Get-Process -Id $pidEnUso -ErrorAction SilentlyContinue } else { $null }
        $esPropio  = $procEnUso -and ($procEnUso.Name -match 'httpd|nginx|w3wp')
        if (-not $esPropio) {
            Write-Error "[ERROR] Puerto $NuevoPuerto ya esta en uso por otro proceso: $($procEnUso.Name)"
            return
        }
        Write-Warning "[ADVERTENCIA] Puerto $NuevoPuerto en uso por el propio servicio HTTP. Se procedera al cambio."
    }

    Write-Host "[OK] Puerto $NuevoPuerto disponible."

    switch ($Servicio) {
        "iis"    { Set-PuertoIIS    -NuevoPuerto $NuevoPuerto }
        "apache" { Set-PuertoApache -NuevoPuerto $NuevoPuerto }
        "nginx"  { Set-PuertoNginx  -NuevoPuerto $NuevoPuerto }
        default  { Write-Error "[ERROR] Servicio no reconocido: $Servicio" }
    }

    # Configurar firewall con el nuevo puerto
    Set-FirewallPuerto -NuevoPuerto $NuevoPuerto
}

# ==============================================================================
# 4. USUARIO DEDICADO Y PERMISOS NTFS
# ==============================================================================

function Set-UsuarioDedicado {
    param([string]$Servicio)

    $svcUser = Get-ServiceUser -Servicio $Servicio
    $webRoot = Get-WebRoot -Servicio $Servicio

    Write-Host ""
    Write-Host "=== Validando usuario dedicado y permisos NTFS ===" 

    # IIS_IUSRS es un grupo built-in; para Apache/Nginx creamos usuario local
    if ($Servicio -ne "iis") {
        $existeUser = Get-LocalUser -Name $svcUser -ErrorAction SilentlyContinue
        if (-not $existeUser) {
            Write-Host "[INFO] Creando usuario local dedicado '$svcUser'..."
            $secPwd = ConvertTo-SecureString (
                -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 20 | ForEach-Object {[char]$_})
            ) -AsPlainText -Force
            New-LocalUser -Name $svcUser `
                          -Password $secPwd `
                          -FullName "$Servicio Service Account" `
                          -Description "Cuenta de servicio dedicada para $Servicio" `
                          -PasswordNeverExpires `
                          -UserMayNotChangePassword | Out-Null
            # Deshabilitar inicio de sesion interactivo
            # No anadir al grupo Users para limitar acceso
            Write-Host "[OK] Usuario '$svcUser' creado sin privilegios de sesion."
        } else {
            Write-Host "[OK] Usuario '$svcUser' ya existe."
        }
    }

    # Crear directorio web si no existe
    if (-not (Test-Path $webRoot)) {
        New-Item -ItemType Directory -Path $webRoot -Force | Out-Null
        Write-Host "[OK] Directorio web creado: $webRoot"
    }

    # Asignar permisos NTFS usando SIDs para evitar IdentityNotMappedException
    # en Windows en espanol (Administrators = S-1-5-32-544, SYSTEM = S-1-5-18)
    Write-Host "[INFO] Configurando permisos NTFS en $webRoot..."

    $sidAdmin  = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $sidSystem = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")

    $acl = Get-Acl $webRoot
    $acl.SetAccessRuleProtection($true, $false)

    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidAdmin, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($adminRule)

    $systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $sidSystem, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.AddAccessRule($systemRule)

    try {
        $svcRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $svcUser, "ReadAndExecute,Write", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($svcRule)
    } catch {
        Write-Warning "[ADVERTENCIA] No se pudo agregar regla para '${svcUser}': $_"
    }

    Set-Acl -Path $webRoot -AclObject $acl
    Write-Host "[OK] Permisos NTFS aplicados. Solo '$svcUser' y Administradores tienen acceso a $webRoot."

    # Verificar que directorios sensibles no sean accesibles
    $dirsSensibles = @("C:\Windows\System32", "C:\Users\Administrator", "C:\Windows\System32\config")
    foreach ($d in $dirsSensibles) {
        if (Test-Path $d) {
            $aclCheck = Get-Acl $d
            $everyoneRule = $aclCheck.Access | Where-Object { $_.IdentityReference -like "*Everyone*" -and $_.FileSystemRights -like "*Write*" }
            if ($everyoneRule) {
                Write-Warning "[ADVERTENCIA] $d tiene permisos de escritura para 'Everyone'."
            } else {
                Write-Host "[OK] $d esta correctamente restringido."
            }
        }
    }
}

# ==============================================================================
# 5. OCULTAR BANNER DEL SERVIDOR
# ==============================================================================

function Hide-BannerIIS {
    Write-Host ""
    Write-Host "=== Ocultando banner: IIS ===" 

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # 1. Eliminar encabezado X-Powered-By
    try {
        Remove-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." `
            -AtElement @{name = "X-Powered-By"} -ErrorAction SilentlyContinue
        Write-Host "[OK] Encabezado X-Powered-By eliminado."
    } catch {
        Write-Warning "[ADVERTENCIA] No se pudo eliminar X-Powered-By: $_"
    }

    # 2. Ocultar version del servidor usando Request Filtering
    try {
        Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
            -Filter "system.webServer/security/requestFiltering" `
            -Name "removeServerHeader" `
            -Value $true
        Write-Host "[OK] Encabezado Server ocultado via Request Filtering."
    } catch {
        Write-Warning "[ADVERTENCIA] Puede requerir IIS 10+. Error: $_"
    }

    # 3. Deshabilitar Server Tokens completamente via appcmd (alternativa)
    $appcmd = "$env:SystemRoot\System32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        & $appcmd set config /section:requestFiltering /removeServerHeader:true 2>&1 | Out-Null
        Write-Host "[OK] Server header deshabilitado via appcmd."
    }
}

function Hide-BannerApache {
    Write-Host ""
    Write-Host "=== Ocultando banner: Apache ===" 

    $confFile = Find-ApacheConf
    if (-not $confFile) {
        Write-Error "[ERROR] No se encontro httpd.conf de Apache. Verifica la instalacion."
        return
    }

    $contenido = Get-Content $confFile

    # ServerTokens
    if ($contenido -match '^ServerTokens') {
        $contenido = $contenido -replace '^ServerTokens.*', 'ServerTokens Prod'
    } elseif ($contenido -match '^#.*ServerTokens') {
        $contenido = $contenido -replace '^#.*ServerTokens.*', 'ServerTokens Prod'
    } else {
        $contenido += "`nServerTokens Prod"
    }
    Write-Host "[OK] ServerTokens -> Prod"

    # ServerSignature
    if ($contenido -match '^ServerSignature') {
        $contenido = $contenido -replace '^ServerSignature.*', 'ServerSignature Off'
    } elseif ($contenido -match '^#.*ServerSignature') {
        $contenido = $contenido -replace '^#.*ServerSignature.*', 'ServerSignature Off'
    } else {
        $contenido += "`nServerSignature Off"
    }
    Write-Host "[OK] ServerSignature -> Off"

    $contenido | Set-Content $confFile -Encoding UTF8
}

function Hide-BannerNginx {
    Write-Host ""
    Write-Host "=== Ocultando banner: Nginx ===" 

    $confPaths = @("C:\nginx\conf\nginx.conf", "C:\tools\nginx\conf\nginx.conf", "C:\tools\nginx-1.29.1\conf\nginx.conf")
    $confFile = $null
    foreach ($p in $confPaths) { if (Test-Path $p) { $confFile = $p; break } }
    if (-not $confFile) {
        $confFile = Get-ChildItem "C:\tools" -Filter "nginx.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $confFile) {
        Write-Error "[ERROR] No se encontro nginx.conf."
        return
    }

    $contenido = Get-Content $confFile -Raw

    if ($contenido -match 'server_tokens') {
        $contenido = $contenido -replace 'server_tokens\s+\w+;', 'server_tokens off;'
    } else {
        $contenido = $contenido -replace '(http\s*\{)', "`$1`n    server_tokens off;"
    }
    Write-Host "[OK] server_tokens -> off"

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($confFile, $contenido, $utf8NoBom)
}

function Hide-BannerServicio {
    param([string]$Servicio)
    switch ($Servicio) {
        "iis"    { Hide-BannerIIS    }
        "apache" { Hide-BannerApache }
        "nginx"  { Hide-BannerNginx  }
    }
}

# ==============================================================================
# 6. FIREWALL DE WINDOWS
# ==============================================================================

function Set-FirewallPuerto {
    param([int]$NuevoPuerto)

    Write-Host ""
    Write-Host "=== Configurando Windows Firewall ===" 

    # Abrir el puerto elegido
    $ruleName = "HTTP-Custom-$NuevoPuerto"
    $existeRegla = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if (-not $existeRegla) {
        New-NetFirewallRule `
            -DisplayName $ruleName `
            -Direction Inbound `
            -Protocol TCP `
            -LocalPort $NuevoPuerto `
            -Action Allow `
            -Profile Any | Out-Null
        Write-Host "[OK] Regla de firewall creada: $ruleName (puerto $NuevoPuerto/TCP permitido)."
    } else {
        Write-Host "[INFO] Regla '$ruleName' ya existe."
    }

    # Cerrar puertos HTTP default si no estan en uso
    $puertosDefault = @(80, 443, 8080, 8443)
    foreach ($p in $puertosDefault) {
        if ($p -ne $NuevoPuerto) {
            if (-not (Test-PuertoEnUso -Puerto $p)) {
                $nombreBloqueo = "HTTP-Block-$p"
                $existeBloqueo = Get-NetFirewallRule -DisplayName $nombreBloqueo -ErrorAction SilentlyContinue
                if (-not $existeBloqueo) {
                    New-NetFirewallRule `
                        -DisplayName $nombreBloqueo `
                        -Direction Inbound `
                        -Protocol TCP `
                        -LocalPort $p `
                        -Action Block `
                        -Profile Any | Out-Null
                    Write-Host "[OK] Puerto $p bloqueado en el firewall (no esta en uso)."
                }
            } else {
                Write-Host "[INFO] Puerto $p en uso por otro servicio, no se bloqueo."
            }
        }
    }
}

# ==============================================================================
# 7. CONTROL DE METODOS HTTP + SECURITY HEADERS
# ==============================================================================

function Set-SeguridadIIS {
    Write-Host ""
    Write-Host "=== Metodos HTTP y Security Headers: IIS ===" 

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Deshabilitar metodos peligrosos: TRACE, TRACK via Request Filtering
    $metodosBloquear = @("TRACE", "TRACK", "DELETE", "PUT", "OPTIONS")
    foreach ($metodo in $metodosBloquear) {
        try {
            Add-WebConfigurationProperty `
                -PSPath "MACHINE/WEBROOT/APPHOST" `
                -Filter "system.webServer/security/requestFiltering/verbs" `
                -Name "." `
                -Value @{verb = $metodo; allowed = "false"} -ErrorAction SilentlyContinue
            Write-Host "[OK] Metodo $metodo bloqueado."
        } catch {
            Write-Warning "[ADVERTENCIA] No se pudo bloquear $metodo`: $_"
        }
    }

    # Security Headers via customHeaders
    $headers = @{
        "X-Frame-Options"        = "SAMEORIGIN"
        "X-Content-Type-Options" = "nosniff"
        "X-XSS-Protection"       = "1; mode=block"
        "Referrer-Policy"        = "strict-origin-when-cross-origin"
    }

    foreach ($h in $headers.GetEnumerator()) {
        try {
            # Eliminar si existe para evitar duplicados
            Remove-WebConfigurationProperty `
                -PSPath "MACHINE/WEBROOT/APPHOST" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." -AtElement @{name = $h.Key} -ErrorAction SilentlyContinue

            Add-WebConfigurationProperty `
                -PSPath "MACHINE/WEBROOT/APPHOST" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." `
                -Value @{name = $h.Key; value = $h.Value}
            Write-Host "[OK] Header '$($h.Key): $($h.Value)' configurado."
        } catch {
            Write-Warning "[ADVERTENCIA] Error configurando header $($h.Key): $_"
        }
    }
}

function Set-SeguridadApache {
    Write-Host ""
    Write-Host "=== Metodos HTTP y Security Headers: Apache ===" 

    $confFile = Find-ApacheConf
    if (-not $confFile) {
        Write-Error "[ERROR] No se encontro httpd.conf de Apache. Verifica la instalacion."
        return
    }

    # Bloque de seguridad a agregar al final de httpd.conf
    $secBlock = @"

# === Bloque de Seguridad HTTP (generado automaticamente) ===
LoadModule headers_module modules/mod_headers.so

TraceEnable Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header always set Referrer-Policy "strict-origin-when-cross-origin"
</IfModule>

<Directory "/">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>
"@

    $contenido = Get-Content $confFile -Raw
    if ($contenido -notmatch "X-Frame-Options") {
        Add-Content $confFile $secBlock -Encoding UTF8
        Write-Host "[OK] Security headers y bloqueo de metodos peligrosos agregados."
    } else {
        Write-Host "[INFO] Security headers ya presentes en $confFile."
    }
}

function Set-SeguridadNginx {
    Write-Host ""
    Write-Host "=== Metodos HTTP y Security Headers: Nginx ===" 

    $confPaths = @("C:\nginx\conf\nginx.conf", "C:\tools\nginx\conf\nginx.conf", "C:\tools\nginx-1.29.1\conf\nginx.conf")
    $confFile = $null
    foreach ($p in $confPaths) { if (Test-Path $p) { $confFile = $p; break } }
    if (-not $confFile) {
        $confFile = Get-ChildItem "C:\tools" -Filter "nginx.conf" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    }

    if (-not $confFile) {
        Write-Error "[ERROR] No se encontro nginx.conf."
        return
    }

    # Obtener puerto actual del conf
    $contenido = Get-Content $confFile -Raw
    $puerto = 80
    if ($contenido -match 'listen\s+[\d\.]*:?(\d+);') { $puerto = $Matches[1] }

    if ($contenido -match "X-Frame-Options") {
        Write-Host "[INFO] Security headers ya presentes en nginx.conf."
        return
    }

    # Escribir conf limpio con headers correctamente dentro de server {}
    $nuevoConf = @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    server_tokens off;
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;

    server {
        listen 0.0.0.0:$puerto;
        server_name  localhost;

        # === Security Headers ===
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;

        # === Bloqueo de metodos HTTP no permitidos ===
        if (`$request_method !~ ^(GET|POST|HEAD)`$) {
            return 405;
        }

        location / {
            root   html;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
}
"@

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($confFile, $nuevoConf, $utf8NoBom)
    Write-Host "[OK] Security headers y bloqueo de metodos agregados en nginx.conf."
}

function Set-SeguridadServicio {
    param([string]$Servicio)
    switch ($Servicio) {
        "iis"    { Set-SeguridadIIS    }
        "apache" { Set-SeguridadApache }
        "nginx"  { Set-SeguridadNginx  }
    }
}

# ==============================================================================
# 8. CREAR PAGINA INDEX PERSONALIZADA
# ==============================================================================

function New-IndexHTML {
    param([string]$Servicio, [string]$Version, [int]$Puerto)

    $webRoot = Get-WebRoot -Servicio $Servicio
    $svcUser = Get-ServiceUser -Servicio $Servicio

    Write-Host ""
    Write-Host "=== Creando index.html personalizado ===" 

    if (-not (Test-Path $webRoot)) {
        New-Item -ItemType Directory -Path $webRoot -Force | Out-Null
    }

    $indexPath = Join-Path $webRoot "index.html"

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>Servidor HTTP</title>
    <style>
        body { font-family: Arial, sans-serif; background:#1e1e2e; color:#cdd6f4;
               display:flex; justify-content:center; align-items:center;
               height:100vh; margin:0; }
        .card { background:#313244; border-radius:12px; padding:40px 60px;
                text-align:center; box-shadow:0 4px 20px rgba(0,0,0,0.4); }
        h1 { color:#89b4fa; margin-bottom:20px; }
        .info { font-size:1.2rem; margin:8px 0; }
        .badge { display:inline-block; background:#45475a; border-radius:6px;
                 padding:4px 12px; margin-top:16px; color:#a6e3a1; font-size:0.9rem; }
        .os { color:#f38ba8; font-size:0.85rem; margin-top:12px; }
    </style>
</head>
<body>
    <div class="card">
        <h1>Servidor HTTP Activo</h1>
        <p class="info"><strong>Servidor:</strong> $($Servicio.ToUpper())</p>
        <p class="info"><strong>Version:</strong> $Version</p>
        <p class="info"><strong>Puerto:</strong> $Puerto</p>
        <p class="info"><strong>Usuario de servicio:</strong> $svcUser</p>
        <span class="badge">:D Instalado y configurado correctamente</span>
        <p class="os">Windows Server - Aprovisionamiento automatico</p>
    </div>
</body>
</html>
"@

    # Escribir el archivo con privilegios de Administrador (heredados del proceso actual)
    # Para poder escribir en el webRoot que ya tiene ACL restrictiva, usar takeown momentaneo
    try {
        # Dar control total temporalmente al proceso actual (Administrador)
        & icacls $webRoot /grant "Administrators:(OI)(CI)F" /T /Q 2>$null | Out-Null
        $html | Set-Content $indexPath -Encoding UTF8
        Write-Host "[OK] index.html creado en: $indexPath"
    } catch {
        Write-Warning "[ADVERTENCIA] No se pudo crear index.html: $_"
        return
    }

    # Asignar permisos de lectura al usuario del servicio
    if (Test-Path $indexPath) {
        try {
            $sidAdmin  = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
            $aclFile   = Get-Acl $indexPath
            $ruleRead  = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $svcUser, "ReadAndExecute", "Allow"
            )
            $ruleAdmin = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $sidAdmin, "FullControl", "Allow"
            )
            $aclFile.AddAccessRule($ruleRead)
            $aclFile.AddAccessRule($ruleAdmin)
            Set-Acl -Path $indexPath -AclObject $aclFile
            Write-Host "[OK] Permisos asignados a '$svcUser' y Administradores en index.html."
        } catch {
            Write-Warning "[ADVERTENCIA] No se pudieron asignar permisos en index.html: $_"
        }
    }
}

# ==============================================================================
# 9. ESTADO DE SERVICIOS HTTP INSTALADOS
# ==============================================================================

function Get-EstadoHTTP {
    Write-Host ""
    Write-Host "=== Estado de Servicios HTTP ===" 

    # IIS
    $iisState = (Get-WindowsFeature -Name "Web-Server").InstallState
    $w3svc    = Get-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    $iisStatus = if ($iisState -eq "Installed") {
        if ($w3svc) { $w3svc.Status } else { "Instalado (servicio no encontrado)" }
    } else { "No instalado" }
    Write-Host "  [IIS]    $iisStatus"

    # Apache
    $apacheSvc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($apacheSvc) {
        Write-Host "  [Apache] $($apacheSvc.Status)"
    } else {
        $apacheExe = Test-Path "C:\Apache24\bin\httpd.exe"
        Write-Host "  [Apache] $(if ($apacheExe) { 'Instalado (sin servicio registrado)' } else { 'No instalado' })"
    }

    # Nginx
    $nginxProc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    $nginxExe  = Test-Path "C:\nginx\nginx.exe"
    if ($nginxProc) {
        Write-Host "  [Nginx]  Running (PID: $($nginxProc.Id))"
    } else {
        Write-Host "  [Nginx]  $(if ($nginxExe) { 'Instalado (no ejecutandose)' } else { 'No instalado' })"
    }
}

# ==============================================================================
# 10. MENU DE CAMBIO DE PUERTO
# ==============================================================================

function Invoke-CambiarPuertoMenu {
    Write-Host ""
    Write-Host "  Cambiar puerto de un servicio HTTP" 
    Write-Host "  ---------------------------------"
    Write-Host "  1) IIS"
    Write-Host "  2) Apache"
    Write-Host "  3) Nginx"
    Write-Host "  0) Salir"

    do {
        $opc = Read-Host "`n  Selecciona el servicio"
        $opc = $opc.Trim()
    } while ($opc -notin @("0","1","2","3"))

    if ($opc -eq "0") { return }

    $servicio = switch ($opc) {
        "1" { "iis" }
        "2" { "apache" }
        "3" { "nginx" }
    }

    do {
        $puertoStr = Read-Host "  Ingresa el nuevo puerto para $servicio"
        $puertoStr = $puertoStr.Trim()
        if ($puertoStr -notmatch '^\d+$') {
            Write-Warning "  Ingresa solo digitos."
            $puertoStr = ""
        }
    } while (-not $puertoStr)

    $puertoPedido  = [int]$puertoStr
    $puertoFinal   = Resolve-ConflictoPuerto -ServicioNuevo $servicio -PuertoDeseado $puertoPedido
    Set-PuertoServicio -Servicio $servicio -NuevoPuerto $puertoFinal
}

# ==============================================================================
# 11. INSTALACION COMPLETA CON TODOS LOS PASOS DE SEGURIDAD
# ==============================================================================

function Invoke-InstalarYAsegurar {
    param([string]$Servicio, [string]$Version)

    # Puerto por defecto segun servicio
    $puertoPorDefecto = switch ($Servicio) {
        "iis"    { 80 }
        "apache" { 80 }
        "nginx"  { 80 }
        default  { 8080 }
    }

    # Solicitar puerto
    Write-Host ""
    do {
        $puertoStr = Read-Host "  ?En que puerto deseas instalar $Servicio? [default: $puertoPorDefecto]"
        $puertoStr = $puertoStr.Trim()
        if ($puertoStr -eq "") { $puertoStr = "$puertoPorDefecto" }
        if ($puertoStr -notmatch '^\d+$') {
            Write-Warning "  Solo digitos permitidos."
            $puertoStr = ""
        }
    } while (-not $puertoStr)

    $puerto = [int]$puertoStr

    if (-not (Test-PuertoValido -Puerto $puerto)) {
        Write-Error "[ERROR] Puerto invalido: $puerto"
        return
    }
    if (-not (Test-PuertoNoReservado -Puerto $puerto)) { return }

    # -- Resolver conflicto de puerto antes de instalar -----------------------
    # Si otro servicio HTTP ya ocupa el puerto, reasignar automaticamente
    $puerto = Resolve-ConflictoPuerto -ServicioNuevo $Servicio -PuertoDeseado $puerto
    Write-Host "[INFO] Puerto final asignado a ${Servicio}: $puerto"

    Write-Host ""
    Write-Host "======================================================" 
    Write-Host "  Instalando $Servicio  version: $Version  puerto: $puerto" 
    Write-Host "======================================================" 

    # Paso 1 - Instalar servicio
    $ok = $false
    switch ($Servicio) {
        "iis"    { $ok = Install-IIS    -Puerto $puerto }
        "apache" { $ok = Install-Apache -Version $Version -Puerto $puerto }
        "nginx"  { $ok = Install-Nginx  -Version $Version -Puerto $puerto }
    }
    if (-not $ok) { Write-Error "[ERROR] Instalacion fallida. Abortando."; return }

    # Paso 2 - Cambiar puerto
    # Para Apache: Chocolatey SIEMPRE instala en 8080 (hardcodeado en su chocolateyInstall.ps1),
    # por lo que hay que forzar el cambio al puerto elegido sin importar cual sea.
    # Para IIS y Nginx se cambia solo si difiere del default.
    $forzarCambio = ($Servicio -eq "apache")
    if ($forzarCambio -or ($puerto -ne $puertoPorDefecto)) {
        # Detener el servicio antes de editar el conf para evitar bloqueos de archivo
        if ($Servicio -eq "apache") {
            $svcApache = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($svcApache -and $svcApache.Status -eq "Running") {
                Stop-Service $svcApache.Name -Force -ErrorAction SilentlyContinue
                Write-Host "[INFO] Servicio Apache detenido para cambiar puerto." 
                Start-Sleep -Seconds 2
            }
        }
        Set-PuertoServicio -Servicio $Servicio -NuevoPuerto $puerto
    } else {
        Set-FirewallPuerto -NuevoPuerto $puerto
    }

    # Paso 3 - Usuario dedicado + permisos NTFS
    Set-UsuarioDedicado -Servicio $Servicio

    # Paso 4 - Ocultar banner
    Hide-BannerServicio -Servicio $Servicio

    # Paso 5 - Security Headers + bloqueo de metodos peligrosos
    Set-SeguridadServicio -Servicio $Servicio

    # Paso 6 - Crear index.html personalizado
    New-IndexHTML -Servicio $Servicio -Version $Version -Puerto $puerto

    # Paso 7 - Reiniciar servicio para aplicar todo
    Write-Host ""
    Write-Host "=== Aplicando configuracion final ===" 
    switch ($Servicio) {
        "iis" {
            Restart-Service W3SVC -Force -ErrorAction SilentlyContinue
            Write-Host "[OK] IIS reiniciado."
        }
        "apache" {
            # El cambio de puerto ya reinicio Apache en Set-PuertoApache.
            # Solo verificar que este corriendo; si no, intentar arrancar.
            $svc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($svc) { $svc.Refresh() }
            $corriendo = $svc -and $svc.Status -eq "Running"
            if (-not $corriendo) {
                $base = if ($script:ApacheBase) { $script:ApacheBase } else { Find-ApacheBase }
                if ($base -and (Test-Path "$base\bin\httpd.exe")) {
                    Start-Process "$base\bin\httpd.exe" -ArgumentList "-k","start" -NoNewWindow
                    Start-Sleep -Seconds 2
                }
            }
            $svc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($svc) { $svc.Refresh() }
            if ($svc -and $svc.Status -eq "Running") {
                Write-Host "[OK] Apache corriendo en puerto $puerto." 
            } else {
                $base = if ($script:ApacheBase) { $script:ApacheBase } else { "C:\Apache24" }
                Write-Warning "[ADVERTENCIA] Apache no responde. Revisa: $base\logs\error.log"
            }
        }
        "nginx" {
            $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
            if ($proc) { $proc | Stop-Process -Force; Start-Sleep 1 }
            $nginxExe = Find-NginxExeDir
            if ($nginxExe) {
                Start-Process "$nginxExe\nginx.exe" -WorkingDirectory $nginxExe
            } else {
                Write-Warning "[ADVERTENCIA] No se encontro nginx.exe. Reinicia manualmente."
            }
            Write-Host "[OK] Nginx reiniciado."
        }
    }

    Write-Host ""
    Write-Host "======================================================" 
    Write-Host "  $Servicio instalado y asegurado correctamente" 
    Write-Host "  Puerto  : $puerto"
    Write-Host "  Usuario : $(Get-ServiceUser -Servicio $Servicio)"
    Write-Host "  Web dir : $(Get-WebRoot -Servicio $Servicio)"
    Write-Host "======================================================" 
}

# ==============================================================================
# 12. MENU DE SELECCION DE VERSION E INSTALACION
# ==============================================================================

function Invoke-GetVersionesHTTP {
    Write-Host ""
    Write-Host "  Versiones de HTTP disponibles:" 
    Write-Host "  1) IIS (obligatorio en Windows Server)"
    Write-Host "  2) Apache Win64  (via Chocolatey)"
    Write-Host "  3) Nginx para Windows  (via Chocolatey)"
    Write-Host "  0) Salir"

    do {
        $opc = Read-Host "`n  Selecciona el servidor que deseas instalar"
        $opc = $opc.Trim()
    } while ($opc -notin @("0","1","2","3"))

    switch ($opc) {
        "0" { return }

        "1" {
            # IIS: version determinada por el SO
            $version = Get-VersionesIIS
            if (-not $version) { Write-Host "Instalacion cancelada."; return }
            Invoke-InstalarYAsegurar -Servicio "iis" -Version $version
        }

        "2" {
            # Apache Win64
            Write-Host ""
            Write-Host "  Consultando versiones de Apache Win64..." 
            $versiones = Get-VersionesApache
            if (-not $versiones -or $versiones.Count -eq 0) {
                Write-Error "[ERROR] No se encontraron versiones de Apache en Chocolatey."
                return
            }
            $versionElegida = Select-Version -Paquete "Apache Win64" -Versiones $versiones
            if (-not $versionElegida) { return }
            Invoke-InstalarYAsegurar -Servicio "apache" -Version $versionElegida
        }

        "3" {
            # Nginx para Windows
            Write-Host ""
            Write-Host "  Consultando versiones de Nginx para Windows..." 
            $versiones = Get-VersionesNginx
            if (-not $versiones -or $versiones.Count -eq 0) {
                Write-Error "[ERROR] No se encontraron versiones de Nginx en Chocolatey."
                return
            }
            $versionElegida = Select-Version -Paquete "Nginx Windows" -Versiones $versiones
            if (-not $versionElegida) { return }
            Invoke-InstalarYAsegurar -Servicio "nginx" -Version $versionElegida
        }
    }
}