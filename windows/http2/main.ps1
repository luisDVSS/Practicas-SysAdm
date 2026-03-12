. "$PSScriptRoot\http_funciones.ps1"
function Invoke-MenuHTTP {

    if (-not (Assert-Chocolatey)) { return }

    Write-Host ""
    Write-Host "======================================================"
    Write-Host "   Instalador de servidor HTTP para Windows"
    Write-Host "======================================================"
    Write-Host "  1) IIS     (rol nativo de Windows Server)"
    Write-Host "  2) Apache  (via Chocolatey)"
    Write-Host "  3) Nginx   (via Chocolatey)"
    Write-Host "  4) Cambiar puerto"
    Write-Host "  0) Salir"
    Write-Host ""

    do {
        $opc = (Read-Host "  Selecciona la opcion").Trim()
    } while ($opc -notin @("0","1","2","3","4"))

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
        "4"{
            Invoke-CambiarPuerto
        }
    }
}

Invoke-MenuHTTP