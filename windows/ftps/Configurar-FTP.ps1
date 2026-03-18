function Registrar-Grupo-FTP {
    Clear-Host
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "   GESTOR DE GRUPOS Y CARPETAS FTP" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "Que entorno desea inicializar en el servidor?" -ForegroundColor Yellow
    
    Write-Host "2) Entorno Practica 7 (Boveda Segura + Autodescarga)"
  
    $opcion = Read-Host "Elija una opcion (1, 2 o 3)"

    if (-not $global:ADSI) { $global:ADSI = [ADSI]"WinNT://$env:ComputerName" }

    if ($opcion -eq "1" -or $opcion -eq "3") {
        Write-Host "`n> Inicializando Grupos Base (Reprobados / Recursadores)..." -ForegroundColor Cyan

        if(-not($global:ADSI.Children | Where-Object { $_.SchemaClassName -eq "Group" -and $_.Name -eq "Reprobados"})){
            if(-not (Test-Path "C:\FTP\Reprobados")) { New-Item -Path "C:\FTP\Reprobados" -ItemType Directory -Force | Out-Null }
            $FTPUserGroup = $global:ADSI.Create("Group", "Reprobados")
            $FTPUserGroup.SetInfo()
            $FTPUserGroup.Description = "Team de reprobados"
            $FTPUserGroup.SetInfo()
            Write-Host "  + Grupo y carpeta Reprobados creados." -ForegroundColor Green
        } else { Write-Host "  - El grupo Reprobados ya existe." -ForegroundColor DarkGray }
        
        if(-not($global:ADSI.Children | Where-Object { $_.SchemaClassName -eq "Group" -and $_.Name -eq "Recursadores"})){
            if(-not (Test-Path "C:\FTP\Recursadores")) { New-Item -Path "C:\FTP\Recursadores" -ItemType Directory -Force | Out-Null }
            $FTPUserGroup = $global:ADSI.Create("Group", "Recursadores")
            $FTPUserGroup.SetInfo()
            $FTPUserGroup.Description = "Este grupo son los q valieron queso en ASM y SysADM"
            $FTPUserGroup.SetInfo()
            Write-Host "  + Grupo y carpeta Recursadores creados." -ForegroundColor Green
        } else { Write-Host "  - El grupo Recursadores ya existe." -ForegroundColor DarkGray }
    }

    if ($opcion -eq "2" -or $opcion -eq "3") {
        Write-Host "`n> Inicializando Boveda Segura para Instaladores..." -ForegroundColor Cyan
        
        $rutaBase = "C:\FTP\Practica7\http\Windows"
        $rutaApache = "$rutaBase\Apache"
        $rutaNginx = "$rutaBase\Nginx"

        if (-not (Test-Path $rutaApache)) { New-Item -Path $rutaApache -ItemType Directory -Force | Out-Null }
        if (-not (Test-Path $rutaNginx)) { New-Item -Path $rutaNginx -ItemType Directory -Force | Out-Null }

        Write-Host "  + Rutas base creadas en C:\FTP\Practica7" -ForegroundColor Green

        Import-Module WebAdministration
        New-WebVirtualDirectory -Site "FTP" -Name "Instaladores" -PhysicalPath "C:\FTP\Practica7" -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host "  + Tunel virtual /Instaladores activado en IIS FTP." -ForegroundColor Green

        Write-Host "`n> Desea descargar automaticamente los instaladores desde Internet y generar sus Hashes?" -ForegroundColor Yellow
        $descargar = Read-Host "Presione S para Si, o cualquier otra tecla para omitir"

        if ($descargar -eq 'S' -or $descargar -eq 's') {
            try {
                # Evitar errores de protocolo SSL viejo en Windows Server
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

                Write-Host "  ~ Descargando Nginx Oficial..." -ForegroundColor Cyan
                $urlNginx = "https://nginx.org/download/nginx-1.24.0.zip"
                $destNginx = "$rutaNginx\nginx.zip"
                Invoke-WebRequest -Uri $urlNginx -OutFile $destNginx -UseBasicParsing
                
                Write-Host "  ~ Generando Hash SHA256 para Nginx..." -ForegroundColor Cyan
                $hashN = (Get-FileHash -Path $destNginx -Algorithm SHA256).Hash
                $hashN | Out-File -FilePath "$destNginx.sha256" -Encoding ascii
                Write-Host "  + Nginx listo y asegurado." -ForegroundColor Green

                Write-Host "  ~ Descargando Apache (VERSION CON SSL INCLUIDO)..." -ForegroundColor Cyan
                # === AQUÍ ESTÁ EL CAMBIO MAESTRO DE LA URL ===
                $urlApache = "https://archive.apache.org/dist/httpd/binaries/win32/httpd-2.2.25-win32-x86-openssl-0.9.8y.msi"
                $destApache = "$rutaApache\apache.msi"
                Invoke-WebRequest -Uri $urlApache -OutFile $destApache -UseBasicParsing
                
                Write-Host "  ~ Generando Hash SHA256 para Apache..." -ForegroundColor Cyan
                $hashA = (Get-FileHash -Path $destApache -Algorithm SHA256).Hash
                $hashA | Out-File -FilePath "$destApache.sha256" -Encoding ascii
                Write-Host "  + Apache listo y asegurado." -ForegroundColor Green

                Write-Host "`n+ BOVEDA 100% LISTA PARA USARSE CON EL ORQUESTADOR." -ForegroundColor Magenta
            } catch {
                Write-Host "- Error al descargar los archivos. Verifique su conexion a internet." -ForegroundColor Red
                Write-Host "  Detalle: $($_.Exception.Message)" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "! Descarga omitida. Debera colocar los instaladores manualmente." -ForegroundColor Yellow
        }
    }

    if ($opcion -notin @("1","2","3")) {
        Write-Host "- Opcion invalida. Abortando..." -ForegroundColor Red
    }
    Write-Host ""
    Pause
}

function Activar-Seguridad-FTPS {
    Clear-Host
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "   BLINDAJE SSL/TLS PARA FTP (FTPS)" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    $respuesta = Read-Host "Desea activar SSL en este servicio FTP? [S/N]"

    if ($respuesta -match "^[Ss]$") {
        Write-Host "`n> 1. Generando Certificado Digital Autofirmado..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate -DnsName "www.reprobados.com", "localhost", $env:COMPUTERNAME -CertStoreLocation "cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(1)
        Write-Host "  + Certificado creado." -ForegroundColor Green

        Write-Host "> 2. Inyectando Certificado en IIS FTP..." -ForegroundColor Yellow
        Import-Module WebAdministration
        Set-ItemProperty -Path "IIS:\Sites\FTP" -Name "ftpServer.security.ssl.serverCertHash" -Value $cert.Thumbprint
        
        Write-Host "> 3. Forzando Politicas de Cifrado Estricto..." -ForegroundColor Yellow
        Set-ItemProperty -Path "IIS:\Sites\FTP" -Name "ftpServer.security.ssl.controlChannelPolicy" -Value "SslRequire"
        Set-ItemProperty -Path "IIS:\Sites\FTP" -Name "ftpServer.security.ssl.dataChannelPolicy" -Value "SslRequire"

        Restart-Service ftpsvc -Force

        Write-Host "`n=====================================" -ForegroundColor Green
        Write-Host "      RESUMEN DE VALIDACION" -ForegroundColor Green
        Write-Host "=====================================" -ForegroundColor Green
        Write-Host "    - Servicio     : FTP (Microsoft IIS)" -ForegroundColor White
        Write-Host "    - Estado SSL   : ACTIVO (Requerido)" -ForegroundColor Cyan
        Write-Host "    - Puerto       : 21 (Con TLS Explicito)" -ForegroundColor White
        Write-Host "=====================================`n" -ForegroundColor Green
        
        Write-Host "! AVISO: Los clientes DEBEN usar 'Requiere FTP explicito sobre TLS'." -ForegroundColor Magenta
    } else {
        Write-Host "`n- Operacion cancelada." -ForegroundColor DarkGray
    }
    Pause
}