# ============================================================
#  ftp_cliente.ps1  -  Practica 7 (Windows Server 2022)
#  Cliente FTP dinamico:
#    - Navega estructura /http/Windows/<Servicio>/<archivo>
#    - Descarga binario + .sha256
#    - Verifica integridad SHA256
#    - Instala el paquete descargado
# ============================================================

# Con aislamiento de usuario en IIS FTP, 'repo' ve su carpeta de aislamiento como raiz "/".
# La junction dentro de esa carpeta se llama 'repo' y apunta a C:\srv\ftp\repo.
# Por tanto la ruta correcta es /repo/http/Windows (no /http/Windows).
# NOTA: Se usa $FTP_REPO_BASE (no $FTP_BASE) para evitar colision con la variable
#       homonima definida en ftp_funciones.ps1 al hacer dot-source en main.ps1.
$FTP_REPO_BASE = "/repo/http/Windows"
$DOWNLOAD_DIR  = "C:\Temp\practica7\repo_ftp"

# Variables de sesion FTP (se llenan en Configurar-FtpRepo)
$script:FTP_HOST = ""
$script:FTP_USER = ""
$script:FTP_PASS = ""

# ── Pedir credenciales del servidor FTP repositorio ──────────
function Configurar-FtpRepo {
    Write-Host ""
    Write-Host "=== Configuracion del repositorio FTP privado ==="
    $script:FTP_HOST = Read-Host "  IP del servidor FTP repositorio"
    $script:FTP_USER = Read-Host "  Usuario FTP"
    $passSegura      = Read-Host "  Contrasena FTP" -AsSecureString
    $script:FTP_PASS = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passSegura)
    )
    if (-not (Test-Path $DOWNLOAD_DIR)) {
        New-Item -ItemType Directory -Path $DOWNLOAD_DIR -Force | Out-Null
    }
}

# ── Helper: crear FtpWebRequest con credenciales ─────────────
function New-FtpRequest {
    param([string]$Uri, [string]$Metodo, [bool]$UsarSSL = $false)
    $req = [System.Net.FtpWebRequest]::Create($Uri)
    $req.Method      = $Metodo
    $req.Credentials = New-Object System.Net.NetworkCredential($script:FTP_USER, $script:FTP_PASS)
    $req.EnableSsl   = $UsarSSL
    $req.UsePassive  = $true
    $req.UseBinary   = $true
    if ($UsarSSL) {
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
    }
    return $req
}

# ── Listar contenido de un directorio FTP ────────────────────
function FTP-Listar {
    param([string]$Ruta)

    $uri = "ftp://$($script:FTP_HOST)$Ruta/"

    # Intentar primero sin SSL (FTP plain).
    # IMPORTANTE: si falla con 530 (credenciales) o 550 (ruta) se reporta inmediatamente
    # y NO se reintenta con SSL; el reintento solo sirve para errores de protocolo/conexion.
    $ultimoError = $null
    foreach ($ssl in @($false, $true)) {
        try {
            $req    = New-FtpRequest -Uri $uri -Metodo ([System.Net.WebRequestMethods+Ftp]::ListDirectory) -UsarSSL $ssl
            $resp   = $req.GetResponse()
            $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $text   = $reader.ReadToEnd()
            $reader.Close()
            $resp.Close()

            return ($text -split "`n" | ForEach-Object { $_.Trim() } |
                    Where-Object { $_ -ne "" -and -not $_.StartsWith(".") })
        } catch {
            $msg = $_.Exception.Message
            $ultimoError = $msg

            # 530 = credenciales incorrectas; no cambia con SSL
            if ($msg -match "530") {
                Write-Host "  [ERROR] Credenciales rechazadas (530). Verifica usuario y contrasena." -ForegroundColor Red
                return @()
            }

            # 550 = ruta no existe; no cambia con SSL
            if ($msg -match "550|path|not found") {
                Write-Host "  [ERROR] Ruta no encontrada en el servidor: $Ruta" -ForegroundColor Red
                Write-Host "          Verifica que la estructura existe en el repositorio." -ForegroundColor Yellow
                return @()
            }

            # Otro error en modo plain: reintenta con FTPS
            if (-not $ssl) {
                Write-Host "  [INFO] Intento FTP plain fallido ($msg). Reintentando con FTPS..." -ForegroundColor Yellow
                continue
            }

            # Ambos modos fallaron
            Write-Host "  [ERROR] No se pudo listar ${Ruta}: $ultimoError" -ForegroundColor Red
            return @()
        }
    }
    return @()
}

# ── Descargar un archivo desde FTP ───────────────────────────
function FTP-Descargar {
    param(
        [string]$RutaRemota,
        [string]$Destino
    )

    Write-Host "  Descargando: ftp://$($script:FTP_HOST)$RutaRemota ..."

    $uri = "ftp://$($script:FTP_HOST)$RutaRemota"

    $ultimoError = $null
    foreach ($ssl in @($false, $true)) {
        try {
            $req    = New-FtpRequest -Uri $uri -Metodo ([System.Net.WebRequestMethods+Ftp]::DownloadFile) -UsarSSL $ssl
            $resp   = $req.GetResponse()
            $stream = $resp.GetResponseStream()
            $file   = [System.IO.File]::Create($Destino)
            $stream.CopyTo($file)
            $file.Close()
            $stream.Close()
            $resp.Close()

            # Verificar que el archivo no quedo vacio o truncado
            $descargado = (Get-Item $Destino -ErrorAction SilentlyContinue).Length
            if ($descargado -lt 1KB) {
                Write-Host "  [ERROR] Archivo descargado sospechosamente pequeño ($descargado bytes). Posible transferencia incompleta." -ForegroundColor Red
                Remove-Item $Destino -Force -ErrorAction SilentlyContinue
                return $false
            }

            Write-Host "  [OK] Guardado en: $Destino ($([math]::Round($descargado/1MB,2)) MB)" -ForegroundColor Green
            return $true
        } catch {
            $msg = $_.Exception.Message
            $ultimoError = $msg

            # 530 = credenciales; 550 = ruta. No reintentar con SSL.
            if ($msg -match "530|550") {
                Write-Host "  [ERROR] Fallo al descargar ${RutaRemota}: $msg" -ForegroundColor Red
                return $false
            }

            if (-not $ssl) {
                Write-Host "  [INFO] Intento FTP plain fallido ($msg). Reintentando con FTPS..." -ForegroundColor Yellow
                continue
            }

            Write-Host "  [ERROR] Fallo al descargar ${RutaRemota}: $ultimoError" -ForegroundColor Red
            return $false
        }
    }
    return $false
}

# ── Verificar integridad SHA256 ───────────────────────────────
function Verificar-Integridad {
    param([string]$Archivo)

    $hashFile = "${Archivo}.sha256"

    if (-not (Test-Path $hashFile)) {
        Write-Host "  [ERROR] No se encontro el archivo de hash: $hashFile" -ForegroundColor Red
        return $false
    }

    Write-Host "  Verificando integridad de $(Split-Path $Archivo -Leaf) ..."

    $hashRemoto = (Get-Content $hashFile -Raw).Trim().Split(" ")[0].Trim()
    $hashLocal  = (Get-FileHash -Path $Archivo -Algorithm SHA256).Hash.ToLower()
    $hashRemoto = $hashRemoto.ToLower()

    if ($hashLocal -eq $hashRemoto) {
        Write-Host "  [OK] Integridad verificada." -ForegroundColor Green
        Write-Host "       SHA256: $hashLocal"
        return $true
    } else {
        Write-Host "  [FAIL] El archivo esta CORRUPTO o fue modificado." -ForegroundColor Red
        Write-Host "         Esperado : $hashRemoto"
        Write-Host "         Calculado: $hashLocal"
        return $false
    }
}

# ── Instalar el paquete descargado ────────────────────────────
function Instalar-PaqueteFTP {
    param([string]$Archivo)

    $ext  = [System.IO.Path]::GetExtension($Archivo).ToLower()
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Archivo).ToLower()

    Write-Host ""
    Write-Host "  Instalando $(Split-Path $Archivo -Leaf) ..."

    # ── Verificar que el archivo no esta truncado/corrupto ────────
    if ($ext -eq ".zip") {
        $tamano = (Get-Item $Archivo).Length
        if ($tamano -lt 100KB) {
            Write-Host "  [ERROR] El archivo ZIP parece truncado ($tamano bytes). Re-ejecuta prep_repo.ps1." -ForegroundColor Red
            return $false
        }
        # Validar firma ZIP (primeros 4 bytes deben ser PK\x03\x04)
        try {
            $bytes = [System.IO.File]::ReadAllBytes($Archivo) | Select-Object -First 4
            if (-not ($bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B -and $bytes[2] -eq 0x03 -and $bytes[3] -eq 0x04)) {
                Write-Host "  [ERROR] El archivo no es un ZIP valido (firma incorrecta). Re-ejecuta prep_repo.ps1." -ForegroundColor Red
                return $false
            }
            # Validar firma de fin de directorio central (ultimos bytes deben contener PK\x05\x06)
            $allBytes  = [System.IO.File]::ReadAllBytes($Archivo)
            $tailBytes = $allBytes[($allBytes.Length - 22)..($allBytes.Length - 1)]
            $eocdrOk   = $false
            for ($i = 0; $i -lt $tailBytes.Length - 3; $i++) {
                if ($tailBytes[$i] -eq 0x50 -and $tailBytes[$i+1] -eq 0x4B -and
                    $tailBytes[$i+2] -eq 0x05 -and $tailBytes[$i+3] -eq 0x06) {
                    $eocdrOk = $true; break
                }
            }
            if (-not $eocdrOk) {
                Write-Host "  [ERROR] ZIP corrupto: falta el directorio central (End of Central Directory)." -ForegroundColor Red
                Write-Host "          Tamaño del archivo: $([math]::Round($tamano/1MB,1)) MB"
                Write-Host "          Causas: descarga FTP incompleta o archivo dañado en el repositorio."
                Write-Host "          Solucion: elimina el archivo del repo y re-ejecuta prep_repo.ps1."
                Write-Host "            Remove-Item '$Archivo' -Force"
                Write-Host "            Remove-Item 'C:\srv\ftp\repo\http\Windows\Apache\httpd-*.zip' -Force"
                return $false
            }
        } catch {
            Write-Host "  [ADVERTENCIA] No se pudo validar la firma del ZIP: $_" -ForegroundColor Yellow
        }
    }

    $exito = $false
    switch ($ext) {
        ".zip" {
            if ($base -like "httpd-*" -or $base -like "apache*") {
                Write-Host "  [INFO] Detectado: Apache httpd."
                $puerto = Leer-Puerto -Default 80
                Instalar-Apache -Puerto $puerto -ArchivoLocal $Archivo
                # Comprobar si la instalacion tuvo exito verificando que httpd.exe existe
                $exito = (Test-Path "C:\Apache24\bin\httpd.exe")
            } elseif ($base -like "nginx*") {
                Write-Host "  [INFO] Detectado: Nginx."
                $puerto = Leer-Puerto -Default 8080
                Instalar-Nginx -Puerto $puerto -ArchivoLocal $Archivo
                $exito = (Test-Path "C:\nginx\nginx.exe")
            } else {
                Write-Host "  [INFO] Extrayendo .zip en C:\Temp\practica7\extraido ..."
                Expand-Archive -Path $Archivo -DestinationPath "C:\Temp\practica7\extraido" -Force
                Write-Host "  [ADVERTENCIA] Configura el servicio manualmente desde la carpeta extraida."
                $exito = $true
            }
        }
        ".msi" {
            $puerto = Leer-Puerto -Default 80
            Start-Process msiexec.exe -ArgumentList "/i `"$Archivo`" /qn" -Wait
            Write-Host "  [OK] MSI instalado. Revisa y configura el servicio." -ForegroundColor Green
            $exito = $true
        }
        ".exe" {
            Start-Process $Archivo -ArgumentList "/S" -Wait
            Write-Host "  [OK] Instalador ejecutado." -ForegroundColor Green
            $exito = $true
        }
        default {
            Write-Host "  [ADVERTENCIA] Extension '$ext' no reconocida. Instalacion manual necesaria." -ForegroundColor Yellow
            return $false
        }
    }

    if ($exito) {
        Write-Host "  [OK] Instalacion completada." -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] La instalacion fallo. Revisa los mensajes anteriores." -ForegroundColor Red
    }
    return $exito
}

# ════════════════════════════════════════════════════════════════
#  Flujo principal: navegacion FTP dinamica
# ════════════════════════════════════════════════════════════════

function Instalar-DesdeFTP {
    Configurar-FtpRepo

    Write-Host ""
    Write-Host "  Conectando al repositorio FTP $($script:FTP_HOST) ..."

    # 1. Listar servicios bajo /repo/http/Windows/
    $servicios = @(FTP-Listar -Ruta $FTP_REPO_BASE | Where-Object { $_ -ne "" })

    if ($servicios.Count -eq 0) {
        Write-Host "  [ERROR] No se encontraron servicios en $FTP_REPO_BASE" -ForegroundColor Red
        Write-Host ""
        Write-Host "  Causas comunes:" -ForegroundColor Yellow
        Write-Host "    1) Credenciales incorrectas (usuario/contrasena)"
        Write-Host "    2) La ruta '$FTP_REPO_BASE' no existe en el repositorio."
        Write-Host "       Estructura esperada en el servidor:"
        Write-Host "         C:\srv\ftp\repo\http\Windows\Apache\"
        Write-Host "         C:\srv\ftp\repo\http\Windows\Nginx\"
        Write-Host "       Ejecuta prep_repo.ps1 para poblar el repositorio."
        Write-Host "    3) El usuario 'repo' no tiene la junction creada."
        Write-Host "       Ejecuta Menu-FTP -> opcion 6 (Crear usuario repositorio)."
        return
    }

    Write-Host ""
    Write-Host "  Servicios disponibles en el repositorio:"
    for ($i = 0; $i -lt $servicios.Count; $i++) {
        Write-Host "    $($i+1)) $($servicios[$i])"
    }

    do {
        $idxSvc = Read-Host "  Selecciona el servicio [1-$($servicios.Count)]"
    } while (-not ($idxSvc -match '^\d+$') -or [int]$idxSvc -lt 1 -or [int]$idxSvc -gt $servicios.Count)

    $servicio  = $servicios[[int]$idxSvc - 1]
    $rutaSvc   = "$FTP_REPO_BASE/$servicio"

    # 2. Listar archivos del servicio (excluir .sha256)
    $archivos = @(FTP-Listar -Ruta $rutaSvc | Where-Object { $_ -notmatch '\.sha256$' -and $_ -ne "" })

    if ($archivos.Count -eq 0) {
        Write-Host "  [ERROR] No hay archivos en $rutaSvc" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "  Versiones disponibles de $servicio :"
    for ($i = 0; $i -lt $archivos.Count; $i++) {
        Write-Host "    $($i+1)) $($archivos[$i])"
    }

    do {
        $idxArch = Read-Host "  Selecciona el archivo [1-$($archivos.Count)]"
    } while (-not ($idxArch -match '^\d+$') -or [int]$idxArch -lt 1 -or [int]$idxArch -gt $archivos.Count)

    $archivo   = $archivos[[int]$idxArch - 1]
    $rutaArch  = "$rutaSvc/$archivo"

    # 3. Descargar binario
    $destBin = "$DOWNLOAD_DIR\$archivo"
    $ok = FTP-Descargar -RutaRemota $rutaArch -Destino $destBin
    if (-not $ok) { return }

    # 4. Descargar .sha256
    $destHash = "$destBin.sha256"
    $okHash = FTP-Descargar -RutaRemota "$rutaArch.sha256" -Destino $destHash
    if (-not $okHash) {
        Write-Host "  [ADVERTENCIA] No se encontro .sha256. Omitiendo verificacion." -ForegroundColor Yellow
    }

    # 5. Verificar integridad
    if (Test-Path $destHash) {
        $integro = Verificar-Integridad -Archivo $destBin
        if (-not $integro) {
            Write-Host "  [ABORTANDO] Instalacion cancelada por fallo de integridad." -ForegroundColor Red
            return
        }
    }

    # 6. Instalar
    Instalar-PaqueteFTP -Archivo $destBin
}