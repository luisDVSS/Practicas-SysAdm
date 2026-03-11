




$script:ApachePkg = $null
function Set-PuertoNginx {
    param([int]$Puerto)

    $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $proc) {
        Write-Warning "[ADVERTENCIA] nginx no esta corriendo, no se puede detectar la ruta."
        return
    }

    $base    = Split-Path $proc.Path -Parent
    $conf    = "$base\conf\nginx.conf"

    if (-not (Test-Path $conf)) {
        Write-Error "[ERROR] No se encontro nginx.conf en $base\conf\"
        return
    }

    Write-Host "[INFO] Editando $conf para usar puerto $Puerto..."

    $contenido = Get-Content $conf -Raw
    $contenido = $contenido -replace 'listen\s+[\d\.]*:?\d+;', "listen 0.0.0.0:$Puerto;"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($conf, $contenido, $utf8NoBom)

    Write-Host "[OK] Puerto cambiado a $Puerto en nginx.conf."

    
    $proc | Stop-Process -Force
    Start-Sleep -Seconds 1
    Start-Process "$base\nginx.exe" -WorkingDirectory $base
    Write-Host "[OK] Nginx reiniciado en puerto $Puerto."
}
function Read-Puerto {
    param([int]$Default = 80)

    do {
        $input = Read-Host "  ¿En que puerto deseas configurar el servicio? [default: $Default]"
        $input = $input.Trim()
        if ($input -eq "") { $input = "$Default" }

        if ($input -notmatch '^\d+$') {
            Write-Warning "  Solo se permiten numeros."
            continue
        }

        $p = [int]$input
        if ($p -lt 1 -or $p -gt 65535) {
            Write-Warning "  Puerto fuera de rango (1-65535)."
            continue
        }

        $reservados = @(21,22,25,53,110,143,3306,5432,6379,27017,3389,445,139)
        if ($p -in $reservados) {
            Write-Warning "  El puerto $p esta reservado para otro servicio."
            continue
        }

        if ($p -lt 1024) {
            Write-Warning "  El puerto $p es privilegiado (<1024)."
        }

        return $p
    } while ($true)
}

function New-IndexHTML {
    param(
        [string]$Servicio,
        [string]$Version,
        [int]$Puerto
    )

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <title>$Servicio</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: #f0f2f5;
        }
        .card {
            background: white;
            border-radius: 8px;
            padding: 40px 60px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.1);
            text-align: center;
        }
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

    
$webRoot = switch ($Servicio.ToLower()) {
    "apache" {
        $proc = Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc) { "$(Split-Path (Split-Path $proc.Path -Parent) -Parent)\htdocs" }
        else       { "C:\Apache24\htdocs" }
    }
    "nginx" {
        $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc) { "$(Split-Path $proc.Path -Parent)\html" }
        else       { "C:\tools\nginx\html" }
    }
    "iis"   { "C:\inetpub\wwwroot" }
    default { "C:\inetpub\wwwroot" }
}

    if (-not (Test-Path $webRoot)) {
        New-Item -ItemType Directory -Path $webRoot -Force | Out-Null
        Write-Host "[INFO] Carpeta creada: $webRoot"
    }

    $destino = "$webRoot\index.html"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($destino, $html, $utf8NoBom)

    Write-Host "[OK] index.html generado en: $destino"
}
function Assert-Chocolatey {
    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    foreach ($ruta in @($chocoExe, "C:\ProgramData\chocolatey\choco.exe")) {
        if (Test-Path $ruta) {
            Set-Alias -Name choco -Value $ruta -Scope Global -ErrorAction SilentlyContinue
            Write-Host "[OK] Chocolatey encontrado: $ruta"
            return $true
        }
    }

    Write-Host "[INFO] Chocolatey no encontrado. Instalando..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol =
        [System.Net.ServicePointManager]::SecurityProtocol -bor 3072

    try {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1'))
    } catch {
        Write-Error "[ERROR] No se pudo instalar Chocolatey: $_"
        return $false
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    if (Test-Path $chocoExe) {
        Set-Alias -Name choco -Value $chocoExe -Scope Global -ErrorAction SilentlyContinue
        Write-Host "[OK] Chocolatey instalado correctamente."
        return $true
    }

    Write-Error "[ERROR] La instalacion de Chocolatey fallo."
    return $false
}



function Get-VersionesChoco {
    param([string]$Paquete)

    Write-Host "[INFO] Consultando versiones de '$Paquete'..."

    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
    if (-not (Test-Path $chocoExe)) { $chocoExe = "choco" }

    $salidaRaw = & $chocoExe search $Paquete --exact --all-versions --limit-output 2>&1

    $versiones = @()
    foreach ($linea in $salidaRaw) {
        if ("$linea".Trim() -match '^\S+\|(\d[\d\.\-]+)') {
            $versiones += $Matches[1]
        }
    }

    return ($versiones | Select-Object -First 8)
}



function Select-Version {
    param(
        [string]   $Etiqueta,
        [string[]] $Versiones
    )

    $total  = $Versiones.Count
    if ($total -eq 0) { return $null }

    $ltsIdx = [math]::Floor($total / 2)

    Write-Host ""
    Write-Host "  Versiones disponibles de ${Etiqueta}:"

    for ($i = 0; $i -lt $total; $i++) {
        $label = ""
        if ($i -eq 0)                             { $label = "  (Latest)" }
        elseif ($i -eq $ltsIdx -and $total -ge 3) { $label = "  (LTS / Estable)" }
        elseif ($i -eq ($total - 1))              { $label = "  (Oldest)" }
        Write-Host ("  {0}) {1}{2}" -f ($i + 1), $Versiones[$i], $label)
    }

    do {
        $eleccion = Read-Host "`n  ¿Cual version deseas instalar? [1-$total]"
        $eleccion = $eleccion.Trim()
        if ($eleccion -match '^\d+$' -and [int]$eleccion -ge 1 -and [int]$eleccion -le $total) {
            return $Versiones[[int]$eleccion - 1]
        }
        Write-Warning "  Opcion invalida. Ingresa un numero entre 1 y $total."
    } while ($true)
}



function Install-Servicio {
    param(
        [string]$Servicio,
        [string]$Version,
        [string]$Paquete
    )

    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
    if (-not (Test-Path $chocoExe)) { $chocoExe = "choco" }

    
    $puertoPorDefecto = switch ($Servicio.ToLower()) {
        "apache" { 8080 }
        "nginx"  { 80   }
        "iis"    { 80   }
        default  { 80   }
    }
    $puerto = Read-Puerto -Default $puertoPorDefecto

    Write-Host ""
    Write-Host "======================================================"
    Write-Host "  Instalando $Servicio version $Version en puerto $puerto"
    Write-Host "======================================================"

    switch ($Servicio) {

        "iis" {
            $features = @(
                "Web-Server", "Web-Common-Http", "Web-Default-Doc",
                "Web-Static-Content", "Web-Http-Errors", "Web-Http-Logging",
                "Web-Security", "Web-Filtering", "Web-Mgmt-Console"
            )
            foreach ($feat in $features) {
                $state = (Get-WindowsFeature -Name $feat).InstallState
                if ($state -ne "Installed") {
                    Install-WindowsFeature -Name $feat -IncludeManagementTools
                    Write-Host "[OK] Rol instalado: $feat"
                } else {
                    Write-Host "[INFO] Ya instalado: $feat"
                }
            }
        }

        "apache" {
            & $chocoExe install $Paquete --version=$Version `
                --package-parameters="/Port:$puerto" `
                -y --force
        }

        "nginx" {
            & $chocoExe install nginx --version=$Version -y --force
        }
    }

    if ($LASTEXITCODE -eq 0 -or $Servicio -eq "iis") {
        Write-Host ""
        Write-Host "[OK] $Servicio $Version instalado correctamente."
         if ($Servicio -eq "nginx") {
        Start-Sleep -Seconds 2   
        Set-PuertoNginx -Puerto $puerto
    }
        New-IndexHTML -Servicio $Servicio -Version $Version -Puerto $puerto
    } else {
        Write-Error "[ERROR] La instalacion de $Servicio fallo. Revisa el output anterior."
    }
}




function Invoke-MenuHTTP {

    if (-not (Assert-Chocolatey)) { return }

    Write-Host ""
    Write-Host "======================================================"
    Write-Host "   Instalador de servidor HTTP para Windows"
    Write-Host "======================================================"
    Write-Host "  1) IIS     (rol nativo de Windows Server)"
    Write-Host "  2) Apache  (via Chocolatey)"
    Write-Host "  3) Nginx   (via Chocolatey)"
    Write-Host "  0) Salir"
    Write-Host ""

    do {
        $opc = (Read-Host "  Selecciona el servidor a instalar").Trim()
    } while ($opc -notin @("0","1","2","3"))

    switch ($opc) {

        "0" { Write-Host "  Saliendo."; return }

        "1" {
            $osCaption  = (Get-WmiObject Win32_OperatingSystem).Caption
            $majorMinor = ((Get-WmiObject Win32_OperatingSystem).Version -split '\.')[0..1] -join '.'
            $iisMap = @{
                "10.0" = "IIS 10.0 (Windows Server 2016/2019/2022)"
                "6.3"  = "IIS 8.5  (Windows Server 2012 R2)"
                "6.2"  = "IIS 8.0  (Windows Server 2012)"
                "6.1"  = "IIS 7.5  (Windows Server 2008 R2)"
            }
            $iisLabel = if ($iisMap[$majorMinor]) { $iisMap[$majorMinor] } else { "IIS (version segun SO)" }

            Write-Host ""
            Write-Host "  Sistema : $osCaption"
            Write-Host "  Version : $iisLabel"

            do { $ok = (Read-Host "`n  ¿Confirmar instalacion? [S/N]").Trim().ToUpper() } while ($ok -notin @("S","N"))
            if ($ok -eq "N") { Write-Host "  Cancelado."; return }

            Install-Servicio -Servicio "iis" -Version $iisLabel -Paquete ""
        }

        "2" {
            $paquetes = @("apache-httpd","httpd","apache")
            $versiones = @()
            $pkgUsado  = $null

            foreach ($pkg in $paquetes) {
                $versiones = Get-VersionesChoco -Paquete $pkg
                if ($versiones.Count -gt 0) { $pkgUsado = $pkg; break }
            }

            if ($versiones.Count -eq 0) { Write-Error "[ERROR] No se encontraron versiones de Apache."; return }

            $version = Select-Version -Etiqueta "Apache Win64 ($pkgUsado)" -Versiones $versiones
            if (-not $version) { return }

            Install-Servicio -Servicio "apache" -Version $version -Paquete $pkgUsado
        }

        "3" {
            $versiones = Get-VersionesChoco -Paquete "nginx"

            if ($versiones.Count -eq 0) { Write-Error "[ERROR] No se encontraron versiones de Nginx."; return }

            $version = Select-Version -Etiqueta "Nginx Windows" -Versiones $versiones
            if (-not $version) { return }

            Install-Servicio -Servicio "nginx" -Version $version -Paquete "nginx"
        }
    }
}

Invoke-MenuHTTP