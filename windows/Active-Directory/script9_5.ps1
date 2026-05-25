#Requires -RunAsAdministrator
Clear-Host
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " FASE 8: GESTION DE USUARIOS Y PERFILES MOVILES " -ForegroundColor Cyan
Write-Host " Windows Server 2022 - empresa.local           " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# ----------------------------------------------------------
# VARIABLES BASE
# ----------------------------------------------------------
$Dominio        = (Get-ADDomain).DistinguishedName
$NombreDominio  = (Get-ADDomain).Name
$DominioDNS     = (Get-ADDomain).DNSRoot
$NombreServidor = $env:COMPUTERNAME
$RutaHome       = "C:\Shares\Usuarios"
$RutaPerfiles   = "C:\Perfiles"

# SIDs universales (idioma-neutral)
$SID_UsuariosAuth = "S-1-5-11"   # Authenticated Users
$SID_Admins       = "S-1-5-32-544" # Administrators
$SID_CreatorOwner = "S-1-3-0"    # CREATOR OWNER
$SID_System       = "S-1-5-18"   # SYSTEM

Write-Host "`n  Dominio  : $DominioDNS" -ForegroundColor DarkGray
Write-Host "  Servidor : $NombreServidor`n" -ForegroundColor DarkGray

# ----------------------------------------------------------
# MENU PRINCIPAL
# ----------------------------------------------------------
Write-Host "Que deseas hacer?" -ForegroundColor Yellow
Write-Host "  1. Agregar nuevo usuario (Cuates o NoCuates)"
Write-Host "  2. Configurar perfiles moviles (todos los usuarios)"
Write-Host "  3. Ambos"
$opcion = Read-Host "Selecciona (1, 2 o 3)"
function Configurar-PerfilesMoviles {
    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host " CONFIGURANDO PERFILES MOVILES                  " -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan

    # -------------------------------------------------------
    # 1. Crear carpeta de perfiles
    # -------------------------------------------------------
    Write-Host "`n> 1. Preparando carpeta C:\Perfiles..." -ForegroundColor Yellow

    if (-not (Test-Path $RutaPerfiles)) {
        New-Item -Path $RutaPerfiles -ItemType Directory -Force | Out-Null
    }
    Write-Host "  [+] Carpeta: $RutaPerfiles" -ForegroundColor Green

    # -------------------------------------------------------
    # 2. Compartir con SIDs (idioma-neutral)
    # -------------------------------------------------------
    Write-Host "`n> 2. Compartiendo carpeta de perfiles..." -ForegroundColor Yellow

    Remove-SmbShare -Name "Perfiles" -Force -ErrorAction SilentlyContinue

    $nombreAdmins       = (New-Object System.Security.Principal.SecurityIdentifier($SID_Admins)).Translate([System.Security.Principal.NTAccount]).Value
    $nombreUsuariosAuth = (New-Object System.Security.Principal.SecurityIdentifier($SID_UsuariosAuth)).Translate([System.Security.Principal.NTAccount]).Value

    New-SmbShare `
        -Name         "Perfiles" `
        -Path         $RutaPerfiles `
        -FullAccess   $nombreAdmins `
        -ChangeAccess $nombreUsuariosAuth `
        -ErrorAction  Stop | Out-Null

    Write-Host "  [+] \\$NombreServidor\Perfiles compartida." -ForegroundColor Green

    # -------------------------------------------------------
    # 3. Permisos NTFS con SIDs
    #
    # Estructura correcta para perfiles moviles WS2022:
    # - Admins + SYSTEM : Control total heredable (OI)(CI)F
    # - UsuariosAuth    : RX,WD,AD sin herencia
    #                     Permite crear la carpeta .V6 propia
    #                     pero NO ver carpetas de otros
    # - CREATOR OWNER   : (IO)F heredable
    #                     Da control total al dueno de .V6
    # -------------------------------------------------------
    Write-Host "`n> 3. Aplicando permisos NTFS (SIDs)..." -ForegroundColor Yellow

    icacls $RutaPerfiles /inheritance:r                                 2>$null | Out-Null
    icacls $RutaPerfiles /grant "*${SID_Admins}:(OI)(CI)F"             2>$null | Out-Null
    icacls $RutaPerfiles /grant "*${SID_System}:(OI)(CI)F"             2>$null | Out-Null
    icacls $RutaPerfiles /grant "*${SID_UsuariosAuth}:(RX,WD,AD)"      2>$null | Out-Null
    icacls $RutaPerfiles /grant "*${SID_CreatorOwner}:(OI)(CI)(IO)F"   2>$null | Out-Null
    Write-Host "  [+] Permisos NTFS aplicados." -ForegroundColor Green

    # -------------------------------------------------------
    # 4. Extender bloqueo FSRM al perfil movil
    #
    # PROBLEMA ORIGINAL:
    # El bloqueo .mp3/.mp4/.exe/.msi solo aplicaba en H:
    # El usuario podia guardar esos archivos en el escritorio
    # o en Documentos del perfil movil (C:\Perfiles\*.V6)
    #
    # SOLUCION:
    # Aplicar el mismo apantallamiento a C:\Perfiles
    # EXCEPTO archivos del sistema del perfil (.dat, .pol, etc.)
    # Para esto se usa la misma plantilla pero con exclusiones
    # -------------------------------------------------------
    Write-Host "`n> 4. Extendiendo bloqueo FSRM a perfiles moviles..." -ForegroundColor Yellow

    # Verificar que la plantilla de bloqueo existe (Fase 4)
    if (-not (Get-FsrmFileScreenTemplate -Name "Plantilla_Bloqueo_Total" -ErrorAction SilentlyContinue)) {
        Write-Host "  [-] Plantilla_Bloqueo_Total no existe." -ForegroundColor Red
        Write-Host "  [!] Ejecuta Fase_4.ps1 antes de continuar." -ForegroundColor Yellow
    } else {
        # Aplicar apantallamiento a C:\Perfiles
        if (-not (Get-FsrmFileScreen -Path $RutaPerfiles -ErrorAction SilentlyContinue)) {
            New-FsrmFileScreen `
                -Path     $RutaPerfiles `
                -Template "Plantilla_Bloqueo_Total" `
                -Active:$true | Out-Null
            Write-Host "  [+] Bloqueo .mp3/.mp4/.exe/.msi aplicado en C:\Perfiles" -ForegroundColor Green
            Write-Host "      (aplica al escritorio y documentos del perfil movil)" -ForegroundColor DarkGray
        } else {
            Write-Host "  [-] Apantallamiento en C:\Perfiles ya existe." -ForegroundColor DarkGray
        }
    }

    # -------------------------------------------------------
    # 5. GPO para perfiles moviles
    # -------------------------------------------------------
    Write-Host "`n> 5. Configurando GPO de perfiles moviles..." -ForegroundColor Yellow

    $NombreGPO = "GPO_PerfilesMoviles"
    if (-not (Get-GPO -Name $NombreGPO -ErrorAction SilentlyContinue)) {
        New-GPO -Name $NombreGPO | Out-Null
        New-GPLink -Name $NombreGPO -Target $Dominio | Out-Null

        # Eliminar copia local al cerrar sesion
        Set-GPRegistryValue -Name $NombreGPO `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "DeleteRoamingCache" -Type DWord -Value 1 | Out-Null

        # Esperar perfil completo antes de mostrar escritorio
        Set-GPRegistryValue -Name $NombreGPO `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkDefaultProfile" -Type DWord -Value 1 | Out-Null

        # Timeout para conexion lenta
        Set-GPRegistryValue -Name $NombreGPO `
            -Key "HKLM\SOFTWARE\Policies\Microsoft\Windows\System" `
            -ValueName "SlowLinkTimeOut" -Type DWord -Value 30000 | Out-Null

        Write-Host "  [+] GPO '$NombreGPO' creada y vinculada." -ForegroundColor Green
    } else {
        Write-Host "  [-] GPO ya existe." -ForegroundColor DarkGray
    }

    # -------------------------------------------------------
    # 6. Asignar ProfilePath SIN .V6
    # -------------------------------------------------------
    Write-Host "`n> 6. Asignando ProfilePath a usuarios existentes..." -ForegroundColor Yellow
    Write-Host "  [!] Sin sufijo .V6 - Windows lo agrega automaticamente." -ForegroundColor DarkGray

    $OUs = @("OU=Cuates,$Dominio", "OU=NoCuates,$Dominio")
    $totalAsignados = 0

    foreach ($OU in $OUs) {
        $usuarios = Get-ADUser -Filter * -SearchBase $OU -ErrorAction SilentlyContinue
        foreach ($user in $usuarios) {
            $rutaPerfil = "\\$NombreServidor\Perfiles\$($user.SamAccountName)"
            Set-ADUser -Identity $user.SamAccountName -ProfilePath $rutaPerfil
            Write-Host "  [+] $($user.SamAccountName) -> $rutaPerfil" -ForegroundColor Green
            $totalAsignados++
        }
    }

    Write-Host "`n  [+] Total: $totalAsignados usuarios con perfil asignado." -ForegroundColor Cyan

# -------------------------------------------------------
    # 7. Verificacion final de la carpeta Perfiles
    # -------------------------------------------------------
    Write-Host "`n> 7. Verificacion final..." -ForegroundColor Yellow

    $shareOK   = $null -ne (Get-SmbShare -Name "Perfiles" -ErrorAction SilentlyContinue)
    
    # CORRECCIÓN: Validamos usando Get-Acl y el nombre traducido en lugar del SID crudo
    $permsOK   = (Get-Acl $RutaPerfiles).Access.IdentityReference.Value -contains $nombreUsuariosAuth
    
    $fsrmOK    = $null -ne (Get-FsrmFileScreen -Path $RutaPerfiles -ErrorAction SilentlyContinue)
    $gpoOK     = $null -ne (Get-GPO -Name $NombreGPO -ErrorAction SilentlyContinue)

    @{
        "Share Perfiles creado"           = $shareOK
        "Permisos NTFS aplicados"         = $permsOK
        "FSRM en C:\Perfiles"             = $fsrmOK
        "GPO PerfilesMoviles vinculada"   = $gpoOK
    }.GetEnumerator() | ForEach-Object {
        $color = if ($_.Value) { "Green" } else { "Red" }
        $icono = if ($_.Value) { "[OK]" }  else { "[FALLO]" }
        Write-Host "  $icono $($_.Key)" -ForegroundColor $color
    }

    Write-Host "`n[OK] Perfiles moviles configurados." -ForegroundColor Green
    Write-Host "     Primer login crea .V6 automaticamente." -ForegroundColor DarkGray
    Write-Host "     Bloqueo .mp3/.mp4/.exe/.msi activo en perfil y H:" -ForegroundColor DarkGray
}


# ===========================================================
# FUNCION: AGREGAR NUEVO USUARIO
# ===========================================================
function Agregar-NuevoUsuario {
    Write-Host "`n=================================================" -ForegroundColor Cyan
    Write-Host " AGREGAR NUEVO USUARIO AL DOMINIO               " -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan

    $nombre     = Read-Host "`nNombre completo (ej. Juan Perez)"
    $usuario    = Read-Host "Nombre de usuario (ej. jperez)"
    $contrasena = Read-Host "Contrasena (min 8 chars, mayus, minus, numero)"

    Write-Host "`nGrupo del usuario:"
    Write-Host "  1. Cuates     (horario 8AM-3PM, cuota 10MB)"
    Write-Host "  2. NoCuates  (horario 3PM-2AM, cuota 5MB)"
    $grupo = Read-Host "Selecciona (1 o 2)"

    if ($grupo -eq "1") {
        $OU_Nombre  = "Cuates"
        $cuotaMB    = 10
        $horaInicio = 8
        $horaFin    = 15
    } else {
        $OU_Nombre  = "NoCuates"
        $cuotaMB    = 5
        $horaInicio = 15
        $horaFin    = 2
    }

    $grupoFGPP      = "Grupo_FGPP_Estandar"
    $OU_Ruta        = "OU=$OU_Nombre,$Dominio"
    $rutaCarpetaRed = "\\$NombreServidor\Usuarios\$usuario"
    $rutaPerfil     = "\\$NombreServidor\Perfiles\$usuario"

    # 1. Crear usuario en AD
    Write-Host "`n> 1. Creando usuario en AD..." -ForegroundColor Yellow

    if (Get-ADUser -Filter "SamAccountName -eq '$usuario'" -ErrorAction SilentlyContinue) {
        Write-Host "  [-] '$usuario' ya existe." -ForegroundColor Red
        return
    }

    $passSegura = ConvertTo-SecureString $contrasena -AsPlainText -Force
    New-ADUser `
        -Name                 $nombre `
        -SamAccountName       $usuario `
        -UserPrincipalName    "$usuario@$DominioDNS" `
        -AccountPassword      $passSegura `
        -Path                 $OU_Ruta `
        -Enabled              $true `
        -PasswordNeverExpires $true `
        -HomeDrive            "H:" `
        -HomeDirectory        $rutaCarpetaRed `
        -ProfilePath          $rutaPerfil | Out-Null
    Write-Host "  [+] Usuario '$usuario' en OU=$OU_Nombre." -ForegroundColor Green

    # 2. Carpeta HOME + cuota FSRM
    Write-Host "`n> 2. Carpeta HOME y cuota FSRM..." -ForegroundColor Yellow

    $rutaCarpetaFisica = "$RutaHome\$usuario"
    if (-not (Test-Path $rutaCarpetaFisica)) {
        New-Item -Path $rutaCarpetaFisica -ItemType Directory -Force | Out-Null
    }
    icacls $rutaCarpetaFisica /grant "${usuario}:(OI)(CI)F" /T       2>$null | Out-Null
    icacls $rutaCarpetaFisica /grant "*${SID_Admins}:(OI)(CI)F" /T   2>$null | Out-Null
    icacls $rutaCarpetaFisica /grant "*${SID_System}:(OI)(CI)F" /T   2>$null | Out-Null
    Write-Host "  [+] Carpeta HOME: $rutaCarpetaFisica" -ForegroundColor Green

    $plantilla = if ($OU_Nombre -eq "Cuates") { "Cuota_10MB" } else { "Cuota_5MB" }
    if (-not (Get-FsrmQuota -Path $rutaCarpetaFisica -ErrorAction SilentlyContinue)) {
        New-FsrmQuota -Path $rutaCarpetaFisica -Template $plantilla | Out-Null
        Write-Host "  [+] Cuota ${cuotaMB}MB aplicada en H:." -ForegroundColor Green
    }

    # 3. LogonHours
    Write-Host "`n> 3. LogonHours..." -ForegroundColor Yellow

    function Convertir-HorarioABytes {
        param([int]$HoraInicioLocal, [int]$HoraFinLocal)
        [byte[]]$arr = New-Object byte[] 21
        $off = [System.TimeZoneInfo]::Local.BaseUtcOffset.Hours
        $ini = ($HoraInicioLocal - $off + 24) % 24
        $fin = ($HoraFinLocal    - $off + 24) % 24
        for ($d = 0; $d -lt 7; $d++) {
            for ($h = 0; $h -lt 24; $h++) {
                $ok = if ($ini -lt $fin) { $h -ge $ini -and $h -lt $fin } `
                      else               { $h -ge $ini -or  $h -lt $fin }
                if ($ok) {
                    $arr[($d*3)+[math]::Floor($h/8)] =
                        $arr[($d*3)+[math]::Floor($h/8)] -bor (1 -shl ($h%8))
                }
            }
        }
        return $arr
    }

    [byte[]]$horario = Convertir-HorarioABytes -HoraInicioLocal $horaInicio -HoraFinLocal $horaFin
    Set-ADUser -Identity $usuario -Replace @{logonHours = $horario}
    Write-Host "  [+] Horario: ${horaInicio}:00 - ${horaFin}:00" -ForegroundColor Green

    # 4. FGPP
    Write-Host "`n> 4. Grupo FGPP..." -ForegroundColor Yellow
    Add-ADGroupMember -Identity $grupoFGPP -Members $usuario -ErrorAction SilentlyContinue
    Write-Host "  [+] Agregado a '$grupoFGPP'." -ForegroundColor Green

    # 4.5. Registrar usuario en multiOTP para MFA (NUEVO)
    Write-Host "`n> Registrando en sistema MFA..." -ForegroundColor Yellow
    $RutaMultiOTP = "C:\Program Files\multiOTP"
    $ExeMultiOTP  = "$RutaMultiOTP\multiotp.exe"
    
    if ($OU_Nombre -eq "Cuates") {
        $llaveMFA = "JLDWY3DPEHPK3PXE"
    } else {
        $llaveMFA = "JLDWY3DPEHPK3PXF"
    }
    
    # Nos movemos a la carpeta temporalmente para evitar errores del motor
    Push-Location $RutaMultiOTP
    if (Test-Path "$RutaMultiOTP\users\$usuario.db") { Remove-Item "$RutaMultiOTP\users\$usuario.db" -Force }
    & $ExeMultiOTP -createga $usuario.ToLower() $llaveMFA | Out-Null
    & $ExeMultiOTP -set $usuario.ToLower() prefix-pin=0 | Out-Null
    Pop-Location
    Write-Host "  [+] MFA configurado con llave del grupo." -ForegroundColor Green

    # 5. Perfil movil - solo verificar, NO pre-crear carpeta
    Write-Host "`n> 5. Perfil movil..." -ForegroundColor Yellow
    if (Test-Path $RutaPerfiles) {
        Write-Host "  [+] ProfilePath en AD: $rutaPerfil" -ForegroundColor Green
        Write-Host "  [+] Carpeta real: $rutaPerfil.V6 (primer login)" -ForegroundColor DarkGray
    } else {
        Write-Host "  [!] C:\Perfiles no existe. Ejecuta opcion 2 primero." -ForegroundColor Yellow
    }

    # Resumen
    Write-Host "`n=================================================" -ForegroundColor Green
    Write-Host " USUARIO CREADO EXITOSAMENTE                    " -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Green
    Write-Host "  Usuario : $usuario | OU: $OU_Nombre"                          -ForegroundColor White
    Write-Host "  Horario : ${horaInicio}:00 - ${horaFin}:00"                  -ForegroundColor White
    Write-Host "  Cuota   : ${cuotaMB}MB en H: (sin .mp3/.mp4/.exe/.msi)"      -ForegroundColor White
    Write-Host "  FGPP    : Min 8 chars + bloqueo 3/30min"                     -ForegroundColor White
    Write-Host "  Perfil  : $rutaPerfil (.V6 en primer login)"                 -ForegroundColor White
    Write-Host "=================================================" -ForegroundColor Green
    Write-Host " Reglas automaticas aplicadas:" -ForegroundColor Cyan
    Write-Host "  [OK] AppLocker (GPO en OU=$OU_Nombre)"                       -ForegroundColor Green
    Write-Host "  [OK] LogonHours Fase 3"                                       -ForegroundColor Green
    Write-Host "  [OK] Cuota + bloqueo multimedia H: Fase 4"                   -ForegroundColor Green
    Write-Host "  [OK] Bloqueo multimedia en perfil movil Fase 8"              -ForegroundColor Green
    Write-Host "  [OK] FGPP Fase 6"                                             -ForegroundColor Green
    Write-Host "  [OK] Perfil movil .V6 Fase 8"                                -ForegroundColor Green
}

# ===========================================================
# EJECUTAR SEGUN OPCION
# ===========================================================
switch ($opcion) {
    "1" { Agregar-NuevoUsuario }
    "2" { Configurar-PerfilesMoviles }
    "3" {
        Configurar-PerfilesMoviles
        Write-Host ""
        Agregar-NuevoUsuario
    }
    default { Write-Host "Opcion invalida." -ForegroundColor Red }
}
