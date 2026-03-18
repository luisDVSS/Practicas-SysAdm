# ============================================================
#  ssl_funciones.ps1  -  Practica 7 (Windows Server 2022)
#  Generacion y configuracion de SSL/TLS para:
#    HTTP : IIS, Apache, Nginx
#    FTP  : IIS FTP (FTPS explicito)
# ============================================================

$DOMAIN      = "reprobados.com"
$CERT_STORE  = "Cert:\LocalMachine\My"
$CERT_DIR    = "C:\ssl\reprobados"
$CERT_PFX    = "$CERT_DIR\reprobados.pfx"
$CERT_CRT    = "$CERT_DIR\reprobados.crt"
$CERT_KEY    = "$CERT_DIR\reprobados.key"
$CERT_PASS   = ConvertTo-SecureString "reprobados123" -AsPlainText -Force
$FTP_SITE    = "Practica7-FTP"

# ── Generar certificado autofirmado y exportarlo ──────────────
function Generar-Certificado {
    Write-Host ""
    Write-Host "[SSL] Generando certificado autofirmado para $DOMAIN ..."

    if (-not (Test-Path $CERT_DIR)) {
        New-Item -ItemType Directory -Path $CERT_DIR -Force | Out-Null
    }

    # Eliminar certificados previos de Practica7 para evitar thumbprints duplicados
    $viejos = Get-ChildItem $CERT_STORE | Where-Object {
        $_.FriendlyName -like "Practica7*" -or $_.Subject -like "*$DOMAIN*"
    }
    foreach ($v in $viejos) {
        Remove-Item $v.PSPath -ErrorAction SilentlyContinue
        Write-Host "  [OK] Certificado anterior eliminado: $($v.Thumbprint)"
    }

    # Crear certificado nuevo en el almacen de Windows
    $cert = New-SelfSignedCertificate `
        -DnsName $DOMAIN `
        -CertStoreLocation $CERT_STORE `
        -NotAfter (Get-Date).AddDays(365) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -FriendlyName "Practica7-$DOMAIN" `
        -HashAlgorithm SHA256 `
        -KeyUsage DigitalSignature, KeyEncipherment `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")

    # Exportar .pfx (incluye clave privada)
    Export-PfxCertificate -Cert $cert -FilePath $CERT_PFX -Password $CERT_PASS | Out-Null

    # Exportar .crt (solo certificado publico, para Apache/Nginx)
    Export-Certificate -Cert $cert -FilePath "$CERT_DIR\reprobados.der" -Type CERT | Out-Null

    # Convertir DER a PEM (Base64) para Apache y Nginx
    $derBytes = [System.IO.File]::ReadAllBytes("$CERT_DIR\reprobados.der")
    $b64      = [Convert]::ToBase64String($derBytes)
    $pem      = "-----BEGIN CERTIFICATE-----`n"
    for ($i = 0; $i -lt $b64.Length; $i += 64) {
        $pem += $b64.Substring($i, [Math]::Min(64, $b64.Length - $i)) + "`n"
    }
    $pem += "-----END CERTIFICATE-----"
    $pem | Set-Content $CERT_CRT -Encoding ASCII

    # Exportar clave privada en PEM via openssl si esta disponible
    $opensslPath = Get-Command openssl -ErrorAction SilentlyContinue
    if ($opensslPath) {
        & openssl pkcs12 -in $CERT_PFX -nocerts -nodes `
            -out $CERT_KEY -passin "pass:reprobados123" 2>$null
        Write-Host "  [OK] Clave privada exportada: $CERT_KEY" -ForegroundColor Green
    } else {
        Write-Host "  [INFO] openssl no encontrado; Apache/Nginx usaran el .pfx directamente." -ForegroundColor Yellow
        Write-Host "  [INFO] Instala Git for Windows o Win64 OpenSSL para exportar la clave PEM."
    }

    Write-Host "[OK] Certificado generado." -ForegroundColor Green
    Write-Host "     Thumbprint : $($cert.Thumbprint)"
    Write-Host "     PFX        : $CERT_PFX"
    Write-Host "     CRT (PEM)  : $CERT_CRT"

    return $cert.Thumbprint
}

# ── Obtener thumbprint del certificado reprobados.com ─────────
function Get-Thumbprint {
    $cert = Get-ChildItem $CERT_STORE | Where-Object {
        $_.FriendlyName -like "Practica7*" -or $_.Subject -like "*$DOMAIN*"
    } | Sort-Object NotAfter -Descending | Select-Object -First 1

    if (-not $cert) {
        Write-Host "[ADVERTENCIA] Certificado no encontrado. Generando ..." -ForegroundColor Yellow
        return Generar-Certificado
    }
    return $cert.Thumbprint
}

# ════════════════════════════════════════════════════════════════
#  IIS HTTPS
# ════════════════════════════════════════════════════════════════

function SSL-IIS {
    param([int]$Puerto = 443)

    Write-Host ""
    Write-Host "[SSL] Configurando HTTPS en IIS (puerto $Puerto) ..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $thumb = Get-Thumbprint

    # ── Eliminar cualquier sslcert previo en ese puerto (evita conflicto con netsh) ──
    # netsh falla silenciosamente si ya hay uno registrado — hay que borrarlo primero
    $sslcertExiste = netsh http show sslcert ipport="0.0.0.0:$Puerto" 2>&1
    if ($sslcertExiste -match "IP:port") {
        Write-Host "  [INFO] Eliminando sslcert previo en 0.0.0.0:$Puerto ..."
        netsh http delete sslcert ipport="0.0.0.0:$Puerto" | Out-Null
    }

    # ── Binding HTTPS ─────────────────────────────────────────────
    $bindingExiste = Get-WebBinding -Name "Default Web Site" -Protocol "https" -ErrorAction SilentlyContinue
    if ($bindingExiste) {
        Write-Host "  [INFO] Eliminando binding HTTPS previo ..."
        Remove-WebBinding -Name "Default Web Site" -Protocol "https" -ErrorAction SilentlyContinue
    }
    New-WebBinding -Name "Default Web Site" -Protocol "https" -Port $Puerto -IPAddress "*" -SslFlags 0 | Out-Null
    Write-Host "  [OK] Binding HTTPS creado en puerto $Puerto."

    # ── Asociar certificado: metodo WebAdministration (mas confiable que netsh solo) ──
    # 1. Registrar via netsh (crea la asociacion en http.sys)
    $guid = "{$([System.Guid]::NewGuid().ToString())}"
    $netshOut = netsh http add sslcert ipport="0.0.0.0:$Puerto" certhash=$thumb appid="$guid" 2>&1
    Write-Host "  [netsh] $netshOut"

    if ($netshOut -match "successfully") {
        Write-Host "  [OK] Certificado registrado en http.sys." -ForegroundColor Green
    } else {
        Write-Host "  [ADVERTENCIA] netsh pudo haber fallado. Intentando via WebAdministration..." -ForegroundColor Yellow
        # 2. Fallback: asignar cert directamente al binding via IIS drive
        try {
            $binding = Get-WebBinding -Name "Default Web Site" -Protocol "https" -Port $Puerto
            $binding.AddSslCertificate($thumb, "My")
            Write-Host "  [OK] Certificado asignado via WebAdministration." -ForegroundColor Green
        } catch {
            Write-Host "  [ERROR] No se pudo asignar el certificado al binding: $_" -ForegroundColor Red
            Write-Host "         Intento manual: En IIS Manager -> Default Web Site -> Bindings -> https -> editar -> seleccionar cert."
        }
    }

    # ── Verificar que IIS URL Rewrite esta instalado antes de crear web.config ──
    $rewriteModule = Get-WebConfiguration "system.webServer/rewrite" -ErrorAction SilentlyContinue
    $webconfig = "$WEBROOT_IIS\web.config"
    if (-not (Test-Path (Split-Path $webconfig))) {
        New-Item -ItemType Directory -Path (Split-Path $webconfig) -Force | Out-Null
    }

    if ($rewriteModule -ne $null) {
        # URL Rewrite disponible: crear redireccion HTTP -> HTTPS
        if (-not (Test-Path $webconfig)) {
            @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="HTTP a HTTPS" stopProcessing="true">
          <match url="(.*)" />
          <conditions>
            <add input="{HTTPS}" pattern="^OFF$" />
          </conditions>
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>
</configuration>
"@ | Set-Content $webconfig -Encoding UTF8
            Write-Host "  [OK] web.config con redireccion HTTP->HTTPS creado." -ForegroundColor Green
        }
    } else {
        Write-Host "  [INFO] IIS URL Rewrite no instalado. Sin redireccion automatica HTTP->HTTPS." -ForegroundColor Yellow
        Write-Host "         Puedes instalarlo desde: https://www.iis.net/downloads/microsoft/url-rewrite"
    }

    # ── Firewall ──────────────────────────────────────────────────
    $r = Get-NetFirewallRule -DisplayName "IIS-HTTPS-$Puerto" -ErrorAction SilentlyContinue
    if ($r) { Remove-NetFirewallRule -DisplayName "IIS-HTTPS-$Puerto" }
    New-NetFirewallRule -DisplayName "IIS-HTTPS-$Puerto" -Direction Inbound `
        -Protocol TCP -LocalPort $Puerto -Action Allow | Out-Null
    Write-Host "  [OK] Firewall: puerto $Puerto abierto."

    # ── Reiniciar IIS ─────────────────────────────────────────────
    try {
        Restart-WebItem "IIS:\Sites\Default Web Site" -ErrorAction Stop
        Write-Host "  [OK] Sitio IIS reiniciado." -ForegroundColor Green
    } catch {
        Write-Host "  [ADVERTENCIA] Restart-WebItem fallo: $_" -ForegroundColor Yellow
        iisreset /restart 2>&1 | Out-Null
        Write-Host "  [OK] iisreset ejecutado."
    }

    # ── Verificacion inmediata ────────────────────────────────────
    Start-Sleep -Seconds 3
    $escucha = Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue
    if ($escucha) {
        Write-Host "[OK] IIS HTTPS activo en puerto $Puerto. Proceso PID: $($escucha[0].OwningProcess)" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Puerto $Puerto NO esta en estado Listen tras configurar SSL." -ForegroundColor Red
        Write-Host "        Posibles causas:"
        Write-Host "          1) IIS Web Server no esta instalado (solo FTP). Instala opcion 1."
        Write-Host "          2) El binding HTTPS no se creo correctamente."
        Write-Host "          3) El certificado no se asocio a http.sys."
        Write-Host "        Diagnostico rapido:"
        Write-Host "          netsh http show sslcert ipport=0.0.0.0:$Puerto"
        Write-Host "          Get-WebBinding -Name 'Default Web Site'"
        Write-Host "          netstat -ano | findstr :$Puerto"
    }
}

# ════════════════════════════════════════════════════════════════
#  Apache HTTPS
# ════════════════════════════════════════════════════════════════

function SSL-Apache {
    param([int]$Puerto = 443)

    Write-Host ""
    Write-Host "[SSL] Configurando SSL en Apache (puerto $Puerto) ..."

    $conf = "C:\Apache24\conf\httpd.conf"
    if (-not (Test-Path $conf)) {
        Write-Host "[ERROR] No se encontro $conf. Instala Apache primero." -ForegroundColor Red
        return
    }

    # Asegurar que existen el .crt y el .pfx
    if (-not (Test-Path $CERT_CRT) -or -not (Test-Path $CERT_PFX)) {
        Write-Host "  [INFO] Certificados no encontrados. Generando ..." -ForegroundColor Yellow
        Generar-Certificado | Out-Null
    }

    # ── Exportar clave privada PEM si no existe ───────────────────
    # Apache necesita un archivo .key PEM. Si openssl no estaba disponible
    # al generar el certificado, el .key no existira y Apache fallara al arrancar.
    if (-not (Test-Path $CERT_KEY)) {
        Write-Host "  [INFO] Archivo .key no encontrado. Intentando extraer del .pfx ..."

        # Intento 1: openssl
        $opensslPath = Get-Command openssl -ErrorAction SilentlyContinue
        if ($opensslPath) {
            & openssl pkcs12 -in $CERT_PFX -nocerts -nodes `
                -out $CERT_KEY -passin "pass:reprobados123" 2>$null
            if (Test-Path $CERT_KEY) {
                Write-Host "  [OK] Clave privada exportada con openssl." -ForegroundColor Green
            }
        }

        # Intento 2: openssl incluido con Apache
        if (-not (Test-Path $CERT_KEY)) {
            $apacheOpenSSL = "C:\Apache24\bin\openssl.exe"
            if (Test-Path $apacheOpenSSL) {
                & $apacheOpenSSL pkcs12 -in $CERT_PFX -nocerts -nodes `
                    -out $CERT_KEY -passin "pass:reprobados123" 2>$null
                if (Test-Path $CERT_KEY) {
                    Write-Host "  [OK] Clave privada exportada con openssl de Apache." -ForegroundColor Green
                }
            }
        }

        # Intento 3: PowerShell puro (exportar desde el cert store a PEM)
        if (-not (Test-Path $CERT_KEY)) {
            Write-Host "  [INFO] Extrayendo clave privada via PowerShell ..." -ForegroundColor Yellow
            try {
                $cert = Get-ChildItem $CERT_STORE | Where-Object {
                    $_.FriendlyName -like "Practica7*" -or $_.Subject -like "*$DOMAIN*"
                } | Sort-Object NotAfter -Descending | Select-Object -First 1

                if ($cert -and $cert.HasPrivateKey) {
                    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
                    $keyBytes = $rsa.ExportRSAPrivateKey()
                    $b64Key = [Convert]::ToBase64String($keyBytes)
                    $pemKey = "-----BEGIN RSA PRIVATE KEY-----`n"
                    for ($i = 0; $i -lt $b64Key.Length; $i += 64) {
                        $pemKey += $b64Key.Substring($i, [Math]::Min(64, $b64Key.Length - $i)) + "`n"
                    }
                    $pemKey += "-----END RSA PRIVATE KEY-----"
                    $pemKey | Set-Content $CERT_KEY -Encoding ASCII
                    Write-Host "  [OK] Clave privada exportada via PowerShell." -ForegroundColor Green
                } else {
                    Write-Host "  [ERROR] El certificado no tiene clave privada exportable." -ForegroundColor Red
                }
            } catch {
                Write-Host "  [ERROR] No se pudo exportar la clave privada: $_" -ForegroundColor Red
            }
        }

        if (-not (Test-Path $CERT_KEY)) {
            Write-Host "[ERROR] No se pudo obtener el archivo .key." -ForegroundColor Red
            Write-Host "        Instala OpenSSL y ejecuta manualmente:"
            Write-Host "        openssl pkcs12 -in $CERT_PFX -nocerts -nodes -out $CERT_KEY -passin pass:reprobados123"
            return
        }
    }

    # ── Habilitar modulos SSL en httpd.conf ───────────────────────
    $contenido = Get-Content $conf -Raw
    $contenido = $contenido -replace '#LoadModule ssl_module',           'LoadModule ssl_module'
    $contenido = $contenido -replace '#LoadModule socache_shmcb_module', 'LoadModule socache_shmcb_module'
    $contenido = $contenido -replace '#Include conf/extra/httpd-ssl.conf', 'Include conf/extra/httpd-ssl.conf'
    # Asegurar que el puerto SSL este definido (puede que Listen 443 ya este en httpd-ssl.conf)
    if ($contenido -notmatch "Listen $Puerto") {
        $contenido = $contenido -replace "(Listen \d+)", "`$1`nListen $Puerto"
    }
    $contenido | Set-Content $conf -Encoding ASCII

    # ── Generar conf/extra/httpd-ssl.conf ─────────────────────────
    $sslConf    = "C:\Apache24\conf\extra\httpd-ssl.conf"
    $certPath   = ($CERT_CRT -replace "\\", "/")
    $keyPath    = ($CERT_KEY -replace "\\", "/")
    $docRootEsc = ($WEBROOT_APACHE -replace "\\", "/")
    $logDir     = "C:/Apache24/logs"

    @"
Listen $Puerto

SSLPassPhraseDialog  builtin
SSLSessionCache      "shmcb:$logDir/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost _default_:$Puerto>
    DocumentRoot "$docRootEsc"
    ServerName $DOMAIN`:$Puerto

    SSLEngine on
    SSLCertificateFile    "$certPath"
    SSLCertificateKeyFile "$keyPath"

    SSLProtocol           all -SSLv3 -TLSv1 -TLSv1.1
    SSLCipherSuite        HIGH:!aNULL:!MD5

    <Directory "$docRootEsc">
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    CustomLog "$logDir/ssl_access.log" combined
    ErrorLog  "$logDir/ssl_error.log"
</VirtualHost>
"@ | Set-Content $sslConf -Encoding ASCII
    Write-Host "  [OK] httpd-ssl.conf generado." -ForegroundColor Green

    # ── Firewall ──────────────────────────────────────────────────
    $r = Get-NetFirewallRule -DisplayName "Apache-HTTPS-$Puerto" -ErrorAction SilentlyContinue
    if ($r) { Remove-NetFirewallRule -DisplayName "Apache-HTTPS-$Puerto" }
    New-NetFirewallRule -DisplayName "Apache-HTTPS-$Puerto" -Direction Inbound `
        -Protocol TCP -LocalPort $Puerto -Action Allow | Out-Null
    Write-Host "  [OK] Firewall: puerto $Puerto abierto."

    # ── Validar config antes de reiniciar ─────────────────────────
    $apacheExe = "C:\Apache24\bin\httpd.exe"
    $testConfig = & $apacheExe -t 2>&1
    if ($testConfig -match "Syntax OK") {
        Write-Host "  [OK] Sintaxis de configuracion Apache: OK" -ForegroundColor Green
        Restart-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $svcStatus = (Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue).Status
        if ($svcStatus -eq "Running") {
            Write-Host "[OK] Apache HTTPS activo en puerto $Puerto." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Apache no arranco. Revisa C:\Apache24\logs\ssl_error.log" -ForegroundColor Red
        }
    } else {
        Write-Host "[ERROR] Error de sintaxis en configuracion Apache:" -ForegroundColor Red
        Write-Host $testConfig
        Write-Host "        Revisa $sslConf"
    }
}

# ════════════════════════════════════════════════════════════════
#  Nginx HTTPS
# ════════════════════════════════════════════════════════════════

function SSL-Nginx {
    param([int]$Puerto = 443)

    Write-Host ""
    Write-Host "[SSL] Configurando SSL en Nginx (puerto $Puerto) ..."

    $conf = "C:\nginx\conf\nginx.conf"
    if (-not (Test-Path $conf)) {
        Write-Host "[ERROR] No se encontro $conf. Instala Nginx primero." -ForegroundColor Red
        return
    }

    # Asegurar certificados
    if (-not (Test-Path $CERT_CRT) -or -not (Test-Path $CERT_PFX)) {
        Write-Host "  [INFO] Certificados no encontrados. Generando ..." -ForegroundColor Yellow
        Generar-Certificado | Out-Null
    }

    # ── Exportar .key si no existe (reutiliza logica de SSL-Apache) ──
    if (-not (Test-Path $CERT_KEY)) {
        Write-Host "  [INFO] Archivo .key no encontrado. Intentando extraer del .pfx ..."
        $opensslPath = Get-Command openssl -ErrorAction SilentlyContinue
        if (-not $opensslPath) { $opensslPath = Get-Command "C:\Apache24\bin\openssl.exe" -ErrorAction SilentlyContinue }

        if ($opensslPath) {
            & $opensslPath.Source pkcs12 -in $CERT_PFX -nocerts -nodes `
                -out $CERT_KEY -passin "pass:reprobados123" 2>$null
        }

        if (-not (Test-Path $CERT_KEY)) {
            try {
                $cert = Get-ChildItem $CERT_STORE | Where-Object {
                    $_.FriendlyName -like "Practica7*" -or $_.Subject -like "*$DOMAIN*"
                } | Sort-Object NotAfter -Descending | Select-Object -First 1

                if ($cert -and $cert.HasPrivateKey) {
                    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
                    $keyBytes = $rsa.ExportRSAPrivateKey()
                    $b64Key = [Convert]::ToBase64String($keyBytes)
                    $pemKey = "-----BEGIN RSA PRIVATE KEY-----`n"
                    for ($i = 0; $i -lt $b64Key.Length; $i += 64) {
                        $pemKey += $b64Key.Substring($i, [Math]::Min(64, $b64Key.Length - $i)) + "`n"
                    }
                    $pemKey += "-----END RSA PRIVATE KEY-----"
                    $pemKey | Set-Content $CERT_KEY -Encoding ASCII
                    Write-Host "  [OK] Clave privada exportada via PowerShell." -ForegroundColor Green
                }
            } catch {
                Write-Host "  [ERROR] No se pudo exportar la clave privada: $_" -ForegroundColor Red
            }
        }

        if (-not (Test-Path $CERT_KEY)) {
            Write-Host "[ERROR] No se pudo obtener el archivo .key. Nginx necesita la clave en PEM." -ForegroundColor Red
            Write-Host "        Instala OpenSSL y ejecuta:"
            Write-Host "        openssl pkcs12 -in $CERT_PFX -nocerts -nodes -out $CERT_KEY -passin pass:reprobados123"
            return
        }
    }

    $certEsc = ($CERT_CRT -replace "\\", "/")
    $keyEsc  = ($CERT_KEY -replace "\\", "/")
    $rootEsc = ($WEBROOT_NGINX -replace "\\", "/")

    # Puerto HTTP actual (leer del conf para no hardcodear 8080)
    $puertHttp = 8080
    $confActual = Get-Content $conf -Raw -ErrorAction SilentlyContinue
    if ($confActual -match "listen\s+(\d+);") {
        $puertHttp = [int]$Matches[1]
        if ($puertHttp -eq $Puerto) { $puertHttp = 8080 }  # si ya era 443, HTTP queda en 8080
    }

    # ── Reescribir nginx.conf con bloque SSL ──────────────────────
    @"
events { worker_connections 1024; }

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    # Redireccion HTTP -> HTTPS
    server {
        listen $puertHttp;
        server_name $DOMAIN;
        return 301 https://`$host:`$request_uri;
    }

    server {
        listen $Puerto ssl;
        server_name $DOMAIN;
        root $rootEsc;

        ssl_certificate     $certEsc;
        ssl_certificate_key $keyEsc;

        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers   HIGH:!aNULL:!MD5;

        add_header Strict-Transport-Security "max-age=31536000" always;

        location / {
            index index.html;
        }
    }
}
"@ | Set-Content $conf -Encoding ASCII
    Write-Host "  [OK] nginx.conf actualizado con SSL en puerto $Puerto."

    # ── Firewall ──────────────────────────────────────────────────
    $r = Get-NetFirewallRule -DisplayName "Nginx-HTTPS-$Puerto" -ErrorAction SilentlyContinue
    if ($r) { Remove-NetFirewallRule -DisplayName "Nginx-HTTPS-$Puerto" }
    New-NetFirewallRule -DisplayName "Nginx-HTTPS-$Puerto" -Direction Inbound `
        -Protocol TCP -LocalPort $Puerto -Action Allow | Out-Null
    Write-Host "  [OK] Firewall: puerto $Puerto abierto."

    # ── Recargar Nginx: servicio o proceso directo ────────────────
    $svc = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Restart-Service -Name "nginx" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        # Nginx corriendo como proceso directo (Start-Process)
        $proc = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
        if ($proc) {
            & "C:\nginx\nginx.exe" -s reload 2>&1 | Out-Null
            Write-Host "  [OK] nginx recargado (nginx -s reload)."
        } else {
            Start-Process "C:\nginx\nginx.exe" -WorkingDirectory "C:\nginx"
            Start-Sleep -Seconds 2
            Write-Host "  [OK] nginx iniciado."
        }
    }

    Start-Sleep -Seconds 2
    $escucha = Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue
    if ($escucha) {
        Write-Host "[OK] Nginx HTTPS activo en puerto $Puerto." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Puerto $Puerto NO escucha. Revisa C:\nginx\logs\error.log" -ForegroundColor Red
    }
}

# ════════════════════════════════════════════════════════════════
#  IIS FTP  → FTPS (SSL explicito)
# ════════════════════════════════════════════════════════════════

function SSL-FTP {
    Write-Host ""
    Write-Host "[SSL] Configurando FTPS en IIS FTP ..."

    # Siempre leer thumbprint fresco del store — nunca usar uno en cache
    $thumb = Get-Thumbprint

    # Sincronizar thumbprint en applicationHost.config
    $configPath = "$env:windir\system32\inetsrv\config\applicationHost.config"
    [xml]$config = Get-Content $configPath -Raw
    $sitio = $config.configuration.'system.applicationHost'.sites.site |
        Where-Object { $_.name -eq $FTP_SITE }

    if (-not $sitio) {
        Write-Host "[ERROR] Sitio '$FTP_SITE' no encontrado. Ejecuta primero opcion 5->2." -ForegroundColor Red
        return
    }

    # Verificar thumbprint actual en config
    $thumbActual = $sitio.ftpServer.security.ssl.serverCertHash
    if ($thumbActual -and $thumbActual -ne $thumb) {
        Write-Host "  [INFO] Thumbprint desincronizado. Actualizando..." -ForegroundColor Yellow
        Write-Host "         Config  : $thumbActual"
        Write-Host "         Store   : $thumb"
    }

    # Usar Set-FtpSSL de ftp_funciones.ps1 (edita XML directamente)
    Set-FtpSSL -Thumbprint $thumb

    # Arrancar ftpsvc
    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($svc.Status -ne "Running") {
        Start-Service ftpsvc -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }

    $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
    if ($svc.Status -eq "Running") {
        Write-Host "[OK] FTPS activo en sitio '$FTP_SITE'." -ForegroundColor Green
        Write-Host "     Thumbprint: $thumb"
    } else {
        Write-Host "[ERROR] ftpsvc no pudo arrancar. Revisa el Event Viewer." -ForegroundColor Red
        Write-Host "        Thumbprint aplicado: $thumb"
    }
}

# ── Verificar SSL de un endpoint ─────────────────────────────
function Verificar-SSL {
    param(
        [string]$Servicio,
        [string]$Host = "127.0.0.1",
        [int]$Puerto
    )

    Write-Host ""
    Write-Host "--- Verificando SSL: $Servicio (puerto $Puerto) ---"

    $tcp = $null
    $ssl = $null
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient($Host, $Puerto)
        $ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false,
            { $true })  # aceptar cualquier certificado
        $ssl.AuthenticateAsClient($DOMAIN)

        $cert = $ssl.RemoteCertificate
        Write-Host "[OK] $Servicio responde con SSL:" -ForegroundColor Green
        Write-Host "     Subject  : $($cert.Subject)"
        Write-Host "     Expira   : $($cert.GetExpirationDateString())"
        return $true
    } catch {
        Write-Host "[FAIL] $Servicio NO responde por SSL en puerto $Puerto." -ForegroundColor Red
        Write-Host "       Error: $_"
        return $false
    } finally {
        if ($ssl)  { $ssl.Dispose() }
        if ($tcp)  { $tcp.Dispose() }
    }
}

# ── Resumen SSL de todos los servicios ────────────────────────
function Resumen-SSL {
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Cyan
    Write-Host "          RESUMEN DE VERIFICACION SSL/TLS             "
    Write-Host "======================================================"

    $ok   = 0
    $fail = 0

    $checks = @(
        @{ Nombre = "IIS HTTPS";    Puerto = 443  },
        @{ Nombre = "Apache HTTPS"; Puerto = 443  },
        @{ Nombre = "Nginx HTTPS";  Puerto = 443  },
        @{ Nombre = "IIS FTP/TLS";  Puerto = 21   }
    )

    foreach ($c in $checks) {
        $r = Verificar-SSL -Servicio $c.Nombre -Puerto $c.Puerto
        if ($r) { $ok++ } else { $fail++ }
    }

    Write-Host "------------------------------------------------------"
    Write-Host "  Exitosos : $ok   Fallidos : $fail"
    Write-Host "======================================================"
}