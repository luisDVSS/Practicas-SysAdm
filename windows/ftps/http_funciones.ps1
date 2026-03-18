function Generar-Certificados-Web {
    param([string]$DirectorioDestino)
    
    if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
        Write-Host "> Instalando motor criptografico OpenSSL..." -ForegroundColor Cyan
        Instalar-Chocolatey
        choco install openssl.light -y --force | Out-Null
        $env:Path += ";C:\Program Files\OpenSSL\bin;C:\Program Files\OpenSSL-Win64\bin"
    }

    $crt = "$DirectorioDestino\server.crt"
    $key = "$DirectorioDestino\server.key"
    
    Write-Host "> Generando Llave Privada y Certificado..." -ForegroundColor Yellow
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout $key -out $crt -subj "/C=MX/ST=Estado/L=Ciudad/O=Reprobados/CN=localhost" 2>$null
    
    if (Test-Path $crt) {
        Write-Host "  + Certificados creados exitosamente." -ForegroundColor Green
        return $true
    } else {
        Write-Host "  - Fallo al generar certificados." -ForegroundColor Red
        return $false
    }
}

function Invoke-DescargaSeguraFTP {
    param([string]$ServidorIP, [string]$UsuarioFTP, [securestring]$PassFTP, [string]$RutaRemota, [string]$RutaLocalDestino)
    Write-Host "`n===================================================" -ForegroundColor Cyan
    Write-Host "  DESCARGA SEGURA DESDE FTP PRIVADO (TÚNEL SSL)" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan

    # 1. Ignorar errores del certificado autofirmado (Crucial para entornos locales)
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    [System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 2. Desencriptar la contraseña de forma segura para usarla en la red
    $passPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($PassFTP))
    
    $UrlArchivo = "ftp://${ServidorIP}${RutaRemota}"
    $UrlHash = "${UrlArchivo}.sha256"
    $RutaLocalHash = "${RutaLocalDestino}.sha256"

    $DirectorioLocal = Split-Path $RutaLocalDestino -Parent
    if (-not (Test-Path $DirectorioLocal)) { New-Item -ItemType Directory -Path $DirectorioLocal -Force | Out-Null }

    try {
        Write-Host "> 1. Conectando al FTP (Iniciando Handshake SSL)..." -ForegroundColor Yellow
        
        # Descarga del Instalador usando FTPS (EnableSsl = $true)
        $ftpreq = [System.Net.FtpWebRequest]::Create($UrlArchivo)
        $ftpreq.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $ftpreq.Credentials = New-Object System.Net.NetworkCredential($UsuarioFTP, $passPlain)
        $ftpreq.EnableSsl = $true
        $ftpresponse = $ftpreq.GetResponse()
        $responsestream = $ftpresponse.GetResponseStream()
        $targetfile = New-Object System.IO.FileStream($RutaLocalDestino, [System.IO.FileMode]::Create)
        $responsestream.CopyTo($targetfile)
        $targetfile.Close()
        $ftpresponse.Close()

        Write-Host "> 2. Descargando firma de integridad criptografica..." -ForegroundColor Yellow
        
        # Descarga del Hash usando FTPS
        $ftpreq2 = [System.Net.FtpWebRequest]::Create($UrlHash)
        $ftpreq2.Method = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $ftpreq2.Credentials = New-Object System.Net.NetworkCredential($UsuarioFTP, $passPlain)
        $ftpreq2.EnableSsl = $true
        $ftpresponse2 = $ftpreq2.GetResponse()
        $responsestream2 = $ftpresponse2.GetResponseStream()
        $targetfile2 = New-Object System.IO.FileStream($RutaLocalHash, [System.IO.FileMode]::Create)
        $responsestream2.CopyTo($targetfile2)
        $targetfile2.Close()
        $ftpresponse2.Close()

    } catch {
        Write-Host "- ERROR: El servidor FTP rechazo la conexion (Credenciales o Red)." -ForegroundColor Red
        Write-Host "  Detalle tecnico: $($_.Exception.Message)" -ForegroundColor DarkGray
        Pause # ESTE PAUSE EVITA EL PARPADEO PARA QUE PUEDAS LEER EL ERROR
        return $false
    }

    Write-Host "> 3. Verificando integridad SHA256..." -ForegroundColor Yellow
    $HashRemoto = (Get-Content $RutaLocalHash -Raw).Trim().ToUpper()
    $HashLocal = (Get-FileHash -Path $RutaLocalDestino -Algorithm SHA256).Hash.ToUpper()

    if ($HashRemoto -eq $HashLocal) {
        Write-Host "+ INTEGRIDAD CONFIRMADA." -ForegroundColor Green
        return $true
    } else {
        Write-Host "- ALERTA DE SEGURIDAD: Archivo corrupto. Hashes no coinciden." -ForegroundColor Red
        Pause # OTRO CANDADO VISUAL
        return $false
    }
}

function Validar-Puerto-HTTP {
    param([string]$Puerto)
    if ($Puerto -notmatch "^\d+$" -or [int]$Puerto -lt 1 -or [int]$Puerto -gt 65535) { return 1 }
    $ocupado = Get-NetTCPConnection -LocalPort $Puerto -ErrorAction SilentlyContinue
    if ($ocupado) { return 2 }
    return 0
}

function Instalar-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "> Instalando Chocolatey..." -ForegroundColor Cyan
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:Path += ";$env:ALLUSERSPROFILE\chocolatey\bin"
    }
}

function Seleccionar-Version-Choco {
    param([string]$Paquete)
    $lineas = choco search $Paquete --exact --all-versions --limit-output 2>$null
    if (-not $lineas) { return $null }
    $versiones = $lineas | ForEach-Object { ($_ -split '\|')[1] }
    Write-Host "Versiones: 1) LTS  2) Latest  3) Oldest"
    $sel = Read-Host "Seleccione la version"
    if ($sel -eq "1") { return $versiones[0] } elseif ($sel -eq "2") { return $versiones[0] } elseif ($sel -eq "3") { return $versiones[-1] } else { return $null }
}

function Desplegar-IIS {
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "      DESPLIEGUE DINAMICO: IIS" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    $usarSSL = Read-Host "Desea activar SSL en este servicio? [S/N]"

    do {
        $PUERTO = Read-Host "Ingrese el puerto base (ej. 80)"
        $estado = Validar-Puerto-HTTP -Puerto $PUERTO
    } while ($estado -ne 0)

    Write-Host "> Instalando IIS silenciosamente..." -ForegroundColor Cyan
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    Import-Module WebAdministration

    Get-WebBinding -Name "Default Web Site" | Remove-WebBinding -ErrorAction SilentlyContinue
    New-WebBinding -Name "Default Web Site" -IPAddress "*" -Port $PUERTO -Protocol http | Out-Null
    New-NetFirewallRule -DisplayName "HTTP-IIS-Custom" -LocalPort $PUERTO -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

    $htmlPath = "C:\inetpub\wwwroot\index.html"
    Set-Content -Path $htmlPath -Value "<h1>IIS Funcionando</h1>" -Force

    if ($usarSSL -match "^[Ss]$") {
        Write-Host "> Configurando SSL en IIS..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate -DnsName "localhost" -CertStoreLocation "cert:\LocalMachine\My" -NotAfter (Get-Date).AddYears(1)
        
        New-WebBinding -Name "Default Web Site" -IPAddress "*" -Port 443 -Protocol https | Out-Null
        $binding = Get-WebBinding -Name "Default Web Site" -Port 443 -Protocol https
        $binding.AddSslCertificate($cert.Thumbprint, "my")
        New-NetFirewallRule -DisplayName "HTTPS-IIS-Custom" -LocalPort 443 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

        Write-Host "  ~ Instalando modulo Rewrite..." -ForegroundColor Cyan
        Instalar-Chocolatey
        choco install urlrewrite -y | Out-Null

        $webConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <system.webServer>
        <rewrite>
            <rules>
                <rule name="Redireccion HTTPS" stopProcessing="true">
                    <match url="(.*)" />
                    <conditions><add input="{HTTPS}" pattern="off" ignoreCase="true" /></conditions>
                    <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
                </rule>
            </rules>
        </rewrite>
    </system.webServer>
</configuration>
"@
        Set-Content -Path "C:\inetpub\wwwroot\web.config" -Value $webConfig -Force
        $estadoSSL = "ACTIVO"
        $puertosFinales = "$PUERTO y 443"
    } else {
        $estadoSSL = "INACTIVO"
        $puertosFinales = "$PUERTO"
    }

    iisreset /restart | Out-Null

    Write-Host "`n=====================================" -ForegroundColor Green
    Write-Host "      RESUMEN DE VALIDACION" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "    - Servicio   : Microsoft IIS" -ForegroundColor White
    Write-Host "    - Estado SSL : $estadoSSL" -ForegroundColor Cyan
    Write-Host "    - Puertos    : $puertosFinales" -ForegroundColor White
    Write-Host "=====================================`n" -ForegroundColor Green
    Pause
}

function Desplegar-Nginx-Windows {
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "    DESPLIEGUE HIBRIDO: NGINX WIN" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    $origen = Read-Host "Instalar desde 1) Internet o 2) FTP Privado?"
    $usarSSL = Read-Host "Desea activar SSL en este servicio? [S/N]"

    $nginxDir = $null

    if ($origen -eq "1") {
        Instalar-Chocolatey
        $version = Seleccionar-Version-Choco -Paquete "nginx"
        if (-not $version) { return }
        choco install nginx --version $version -y --force
        $posibles = @("C:\tools", "C:\ProgramData\chocolatey\lib\nginx")
        foreach ($r in $posibles) { if (Test-Path $r) { $nginxDir = (Get-ChildItem -Path $r -Filter "nginx.exe" -Recurse | Select -First 1).DirectoryName; break } }
    } elseif ($origen -eq "2") {
        $ip = Read-Host "IP FTP"; $usr = Read-Host "Usuario"; $pass = Read-Host "Contrasena" -AsSecureString
        if (Invoke-DescargaSeguraFTP -ServidorIP $ip -UsuarioFTP $usr -PassFTP $pass -RutaRemota "/Instaladores/http/Windows/Nginx/nginx.zip" -RutaLocalDestino "C:\Temp\nginx.zip") {
            $nginxDir = "C:\nginx_local"
            if (Test-Path $nginxDir) { Remove-Item $nginxDir -Recurse -Force }
            Expand-Archive -Path "C:\Temp\nginx.zip" -DestinationPath $nginxDir -Force
            $nginxDir = (Get-ChildItem -Path $nginxDir -Filter "nginx.exe" -Recurse | Select -First 1).DirectoryName
        } else { return }
    } else { return }

    if (-not $nginxDir) { Write-Host "- Nginx no encontrado." -ForegroundColor Red; return }

    do {
        $PUERTO = Read-Host "Ingrese el puerto base (ej. 80)"
        $estado = Validar-Puerto-HTTP -Puerto $PUERTO
    } while ($estado -ne 0)

    $confPath = "$nginxDir\conf\nginx.conf"

    if ($usarSSL -match "^[Ss]$") {
        Write-Host "> Configurando SSL en Nginx..." -ForegroundColor Yellow
        Generar-Certificados-Web -DirectorioDestino "$nginxDir\conf" | Out-Null
        
        $nginxConfSSL = @"
worker_processes  1;
events { worker_connections  1024; }
http {
    include       mime.types;
    default_type  application/octet-stream;
    server_tokens off;

    server {
        listen       $PUERTO;
        server_name  localhost;
        return 301 https://`$host`$request_uri;
    }

    server {
        listen       443 ssl;
        server_name  localhost;
        ssl_certificate      server.crt;
        ssl_certificate_key  server.key;
        ssl_protocols TLSv1.2 TLSv1.3;

        location / {
            root   html;
            index  index.html index.htm;
        }
    }
}
"@
        Set-Content -Path $confPath -Value $nginxConfSSL -Force
        New-NetFirewallRule -DisplayName "HTTPS-Nginx-Custom" -LocalPort 443 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        $estadoSSL = "ACTIVO"
        $puertosFinales = "$PUERTO y 443"
    } else {
        $contenido = Get-Content $confPath
        $contenido = $contenido -replace 'listen\s+\d+;', "listen       $PUERTO;"
        $contenido | Set-Content $confPath -Force
        $estadoSSL = "INACTIVO"
        $puertosFinales = "$PUERTO"
    }

    New-NetFirewallRule -DisplayName "HTTP-Nginx-Custom" -LocalPort $PUERTO -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Set-Content -Path "$nginxDir\html\index.html" -Value "<h1>Nginx Orquestado</h1>" -Force
    
    Stop-Process -Name "nginx" -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -WindowStyle Hidden

    Write-Host "`n=====================================" -ForegroundColor Green
    Write-Host "      RESUMEN DE VALIDACION" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "    - Servicio   : NGINX Web" -ForegroundColor White
    Write-Host "    - Estado SSL : $estadoSSL" -ForegroundColor Cyan
    Write-Host "    - Puertos    : $puertosFinales" -ForegroundColor White
    Write-Host "=====================================`n" -ForegroundColor Green
    Pause
}

function Desplegar-Apache-Windows {
    Write-Host "=====================================" -ForegroundColor Cyan
    Write-Host "   DESPLIEGUE HIBRIDO: APACHE WIN" -ForegroundColor Cyan
    Write-Host "=====================================" -ForegroundColor Cyan

    $origen = Read-Host "Instalar desde 1) Internet o 2) FTP Privado?"
    $usarSSL = Read-Host "Desea activar SSL en este servicio? [S/N]"

    $apacheDir = $null

    if ($origen -eq "1") {
        Instalar-Chocolatey
        $version = Seleccionar-Version-Choco -Paquete "apache-httpd"
        if (-not $version) { return }
        choco install apache-httpd --version $version -y --force
        $posibles = @("C:\tools", "C:\Apache24", "C:\ProgramData\chocolatey\lib", $env:APPDATA)
        foreach ($r in $posibles) { if (Test-Path $r) { $busqueda = Get-ChildItem -Path $r -Filter "httpd.exe" -Recurse | Select -First 1; if($busqueda){ $apacheDir = $busqueda.DirectoryName; $apacheDir = (Get-Item $apacheDir).Parent.FullName; break } } }
	} elseif ($origen -eq "2") {
        $ip = Read-Host "IP FTP"; $usr = Read-Host "Usuario"; $pass = Read-Host "Contrasena" -AsSecureString
        if (Invoke-DescargaSeguraFTP -ServidorIP $ip -UsuarioFTP $usr -PassFTP $pass -RutaRemota "/Instaladores/http/Windows/Apache/apache.msi" -RutaLocalDestino "C:\Temp\apache.msi") {
            
            Write-Host "> Ejecutando instalador de Apache en segundo plano..." -ForegroundColor Yellow
            Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"C:\Temp\apache.msi`" /quiet /norestart ALLUSERS=1" -Wait
            
            # Búsqueda dinámica agresiva del directorio (32 bits y 64 bits)
            $posiblesRutas = @(
                "C:\Program Files (x86)\Apache Software Foundation\Apache2.2",
                "C:\Program Files\Apache Software Foundation\Apache2.2",
                "C:\Program Files (x86)\Apache Group\Apache2",
                "C:\Program Files\Apache Group\Apache2"
            )
            foreach ($ruta in $posiblesRutas) {
                if (Test-Path "$ruta\bin\httpd.exe") {
                    $apacheDir = $ruta
                    Write-Host "+ Directorio de Apache localizado en: $apacheDir" -ForegroundColor Green
                    break
                }
            }
        } else { return }
    } else { return }

    if (-not $apacheDir -or -not (Test-Path $apacheDir)) { Write-Host "- Apache no localizado." -ForegroundColor Red; return }

    do {
        $PUERTO = Read-Host "Ingrese el puerto base HTTP (ej. 80)"
        $estado = Validar-Puerto-HTTP -Puerto $PUERTO
    } while ($estado -ne 0)

    $confPath = "$apacheDir\conf\httpd.conf"
    $rutaCorregida = $apacheDir -replace '\\', '/'

    $contenido = Get-Content $confPath
    $contenido = $contenido -replace 'Listen \d+', "Listen $PUERTO"
    $contenido = $contenido -replace 'ServerName localhost:\d+', "ServerName localhost:$PUERTO"
    $contenido = $contenido -replace 'Define SRVROOT ".*"', "Define SRVROOT `"$rutaCorregida`""
    $contenido | Set-Content $confPath -Force

    if ($usarSSL -match "^[Ss]$") {
        Write-Host "> Configurando SSL en Apache..." -ForegroundColor Yellow
        Generar-Certificados-Web -DirectorioDestino "$apacheDir\conf" | Out-Null

        $conf = Get-Content $confPath
        $conf = $conf -replace '#LoadModule ssl_module', 'LoadModule ssl_module'
        $conf = $conf -replace '#LoadModule rewrite_module', 'LoadModule rewrite_module'
        $conf = $conf -replace '#LoadModule socache_shmcb_module', 'LoadModule socache_shmcb_module'
        $conf | Set-Content $confPath -Force

        $vhostSSL = @"

<VirtualHost *:$PUERTO>
    ServerName localhost
    Redirect permanent / https://localhost/
</VirtualHost>

Listen 443
<VirtualHost *:443>
    ServerName localhost
    DocumentRoot "$rutaCorregida/htdocs"
    SSLEngine on
    SSLCertificateFile "$rutaCorregida/conf/server.crt"
    SSLCertificateKeyFile "$rutaCorregida/conf/server.key"
</VirtualHost>
"@
        Add-Content -Path $confPath -Value $vhostSSL
        New-NetFirewallRule -DisplayName "HTTPS-Apache-Custom" -LocalPort 443 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        $estadoSSL = "ACTIVO"
        $puertosFinales = "$PUERTO y 443"
    } else {
        $estadoSSL = "INACTIVO"
        $puertosFinales = "$PUERTO"
    }

    New-NetFirewallRule -DisplayName "HTTP-Apache-Custom" -LocalPort $PUERTO -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    Set-Content -Path "$apacheDir\htdocs\index.html" -Value "<h1>Apache Orquestado</h1>" -Force

    Stop-Process -Name "httpd" -Force -ErrorAction SilentlyContinue
    Start-Process -FilePath "$apacheDir\bin\httpd.exe" -WindowStyle Hidden

    Write-Host "`n=====================================" -ForegroundColor Green
    Write-Host "      RESUMEN DE VALIDACION" -ForegroundColor Green
    Write-Host "=====================================" -ForegroundColor Green
    Write-Host "    - Servicio   : Apache HTTPD" -ForegroundColor White
    Write-Host "    - Estado SSL : $estadoSSL" -ForegroundColor Cyan
    Write-Host "    - Puertos    : $puertosFinales" -ForegroundColor White
    Write-Host "=====================================`n" -ForegroundColor Green
    Pause
}