[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. .\validip.ps1
. .\conf_red.ps1
. .\monitor.ps1
. .\validsegmn.ps1
Write-Host "DEBUG: imports OK"
Read-Host "ENTER para continuar"
function Valid-InstDHCP {
    (Get-WindowsFeature -Name DHCP).Installed
}

function Install-DHCP {
    Install-WindowsFeature DHCP -IncludeManagementTools
}
function Convert-IPToInt {
    param ([string]$IP)

    $b = $IP.Split('.') | ForEach-Object { [uint32]$_ }

    return `
        ($b[0] -shl 24) `
    -bor ($b[1] -shl 16) `
    -bor ($b[2] -shl 8)  `
    -bor  $b[3]
}

function Get-FirstHost {
    param (
        [string]$NetworkIP,
        [int]$Prefix
    )

    $b = $NetworkIP.Split('.') | ForEach-Object { [uint32]$_ }

    $ipInt =
        ($b[0] -shl 24) `
     -bor ($b[1] -shl 16) `
     -bor ($b[2] -shl 8)  `
     -bor  $b[3]

    $firstHostInt = $ipInt + 1

    return "{0}.{1}.{2}.{3}" -f `
        (($firstHostInt -shr 24) -band 0xFF),
        (($firstHostInt -shr 16) -band 0xFF),
        (($firstHostInt -shr 8)  -band 0xFF),
        ( $firstHostInt -band 0xFF)
}

function Convert-PrefixToMask {
    param (
        [Parameter(Mandatory)]
        [ValidateRange(0,32)]
        [int]$Prefix
    )

    # Crear máscara de 32 bits
    if ($Prefix -eq 0) {
        return "0.0.0.0"
    }

    $maskInt = ([uint32]::MaxValue) -shl (32 - $Prefix)


    # Convertir a octetos
    $o1 = ($maskInt -shr 24) -band 0xFF
    $o2 = ($maskInt -shr 16) -band 0xFF
    $o3 = ($maskInt -shr 8)  -band 0xFF
    $o4 =  $maskInt -band 0xFF

    return "$o1.$o2.$o3.$o4"
}

function Test-ValidNetwork {
    param (
        [string]$NetworkIP,
        [int]$Prefix
    )

    # Validar IP básica
    if (-not (Test-ValidIPFormat $NetworkIP)) {
        return $false
    }
    
    # Validar prefijo CIDR
    if ($Prefix -lt 0 -or $Prefix -gt 32) {
        return $false
    }

    # Convertir IP a entero
    $ipBytes = $NetworkIP.Split('.') | ForEach-Object { [int]$_ }
   $ipInt =
    ([uint32]$ipBytes[0] -shl 24) `
 -bor ([uint32]$ipBytes[1] -shl 16) `
 -bor ([uint32]$ipBytes[2] -shl 8)  `
 -bor ([uint32]$ipBytes[3])

    # Crear máscara a partir del prefijo
   if ($Prefix -eq 0) {
    $maskInt = [uint32]0
}
else {
    $maskInt = ([uint32]::MaxValue) -shl (32 - $Prefix)

}

    # Calcular red real
    $networkCalc = $ipInt -band $maskInt

    # Comparar
    return ($ipInt -eq $networkCalc)
}

function Get-Broadcast {
    param (
        [string]$Network,
        [string]$Mask
    )

    $net  = [uint32](Convert-IPToInt $Network)
    $mask = [uint32](Convert-IPToInt $Mask)

    $broadcast = $net -bor ([uint32]::MaxValue -bxor $mask)

    return "{0}.{1}.{2}.{3}" -f `
        (($broadcast -shr 24) -band 0xFF),
        (($broadcast -shr 16) -band 0xFF),
        (($broadcast -shr 8)  -band 0xFF),
        ( $broadcast -band 0xFF)
}
function Test-UsableIP {
    param (
        [string]$IP,
        [string]$Network,
        [string]$Mask
    )

    $ipInt  = Convert-IPToInt $IP
    $netInt = Convert-IPToInt $Network
    $bcInt  = Convert-IPToInt (Get-Broadcast $Network $Mask)

    return ($ipInt -gt $netInt -and $ipInt -lt $bcInt)
}

while ($true) {
    Clear-Host
    Write-Host "========== MENU =========="
    Write-Host "1) Instalar y configurar DHCP"
    Write-Host "2) Modulo de monitoreo"
    Write-Host "3) Validacion de instalacion de DHCP"
    Write-Host "4) Salir"
    $op = Read-Host "Selecciona una opcion"

    switch ($op) {

        "1" {
            # 1️⃣ Verificar DHCP
if (-not (Valid-InstDHCP)) {

    $resp = Read-Host "DHCP Server no esta instalado. ¿Deseas instalarlo? (S/N)"
    if ($resp -notmatch '^[sS]') {
        Write-Host "No se puede continuar sin DHCP Server"
        Read-Host "ENTER para volver al menu"
        break
    }

    Write-Host "Instalando DHCP Server..."
    Install-DHCP
    
if (-not (Valid-InstDHCP)) {
    Write-Host "Error al instalar DHCP Server"
    Read-Host "ENTER para volver al menu"
    break
}
}
else {
    Write-Host "DHCP ya esta instalado"

    #Preguntar si se sobrescribirá la configuración
    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($scopes) {
        $resp = Read-Host "Ya existen scopes DHCP. ¿Deseas sobrescribir la configuracion? (S/N)"
        if ($resp -notmatch '^[sS]') {
            Write-Host "Configuracion cancelada por el usuario"
            Read-Host "ENTER para volver al menu"
            break
        }

        foreach ($s in $scopes) {
            Remove-DhcpServerv4Scope -ScopeId $s.ScopeId -Force
        }
    }
}


            Get-NetAdapter | Format-Table Name, Status
            $interfaz = Read-Host "Ingresa el nombre de la interfaz"

           do {
    $network = Read-Host "IP de la network (ej: 192.168.1.0)"
    $prefixStr = Read-Host "Sufijo CIDR (0-32)"

    if ($prefixStr -match '^\d+$') {
        $prefix = [int]$prefixStr
    } else {
        $prefix = -1
    }

} until (Test-ValidNetwork $network $prefix)


$mascara = Convert-PrefixToMask $prefix

$serverIP = Get-FirstHost $network $prefix
Config-RedSV $interfaz $serverIP $prefix

do {
    do { 
        $ipMin = Read-Host "IP minima" 
    } until (Test-ValidIP $ipMin)

    do { 
        $ipMax = Read-Host "IP maxima" 
    } until (Test-ValidIP $ipMax)

    $valido = $true

    if (-not (Test-SameNetwork $network $ipMin $mascara)) {
        Write-Host "La IP minima no pertenece a la red" 
        $valido = $false
    }

    if (-not (Test-SameNetwork $network $ipMax $mascara)) {
        Write-Host "La IP maxima no pertenece a la red"
        $valido = $false
    }

    if ((Convert-IPToInt $ipMin) -gt (Convert-IPToInt $ipMax)) {
        Write-Host "La IP minima no puede ser mayor que la IP maxima" 
        $valido = $false
    }

    if (-not $valido) {
        Read-Host "Rango inválido. Presiona ENTER para intentar de nuevo"
    }
if (-not (Test-UsableIP $ipMin $network $mascara)) {
    Write-Host "La IP minima no es usable (network/broadcast)" 
    $valido = $false
}

if (-not (Test-UsableIP $ipMax $network $mascara)) {
    Write-Host "La IP maxima no es usable (network/broadcast)" 
    $valido = $false
}

} until ($valido)

            do {
    $leaseSeconds = Read-Host "Tiempo de concesion DHCP (en segundos)"
} until ($leaseSeconds -match '^\d+$' -and [int]$leaseSeconds -gt 0)

$leaseTime = [TimeSpan]::FromSeconds([int]$leaseSeconds)
            #input de de dns
do {
    $dns = Read-Host "IP DNS (en blanco=$serverIP)"
    #si esta vacia se le añade la ip del sv
    if ([string]::IsNullOrWhiteSpace($dns)) {
        dns="$serverIP"
    }
} until ((Test-ValidIP $dns))
            do {
    $gw = Read-Host "Gateway (ENTER para omitir)"
} until ([string]::IsNullOrWhiteSpace($gw) -or (Test-ValidIP $gw))


            Add-DhcpServerv4Scope `
    -Name "Scope-$network" `
    -StartRange $ipMin `
    -EndRange $ipMax `
    -SubnetMask $mascara `
    -LeaseDuration $leaseTime

if (-not [string]::IsNullOrWhiteSpace($gw)) {
    Set-DhcpServerv4OptionValue -Router $gw
}

if (-not [string]::IsNullOrWhiteSpace($dns)) {
    Set-DhcpServerv4OptionValue -DnsServer $dns
    Write-Host "Configurando DNS..."
    Set-DnsClientServerAddress `
    -InterfaceAlias $interfaz `
    -ServerAddresses $dns
}

Restart-Service DHCPServer
Write-Host "DHCP configurado y activo"

            
            Read-Host "Presiona ENTER para continuar"
        }

        "2" {
            Monitorear
        }

        "4" {
            Write-Host "Hasta luego"
            exit
        }
        "3" {
    Clear-Host
    Write-Host "Validacion de DHCP"

    
    if (Valid-InstDHCP) {
        Write-Host "DHCP Server esta INSTALADO"
    }
    else {
        Write-Host "DHCP Server NO esta instalado"
        Read-Host "ENTER para volver al menu"
        break
    }

    
    $svc = Get-Service DHCPServer -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "Servicio DHCPServer en ejecucion"
    }
    else {
        Write-Host "Servicio DHCPServer detenido"
    }

    #Mostrar scopes configurados
    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($scopes) {
        Write-Host "Scopes configurados:"
        $scopes | Format-Table ScopeId, Name, StartRange, EndRange, State
    }
    else {
        Write-Host "No hay scopes DHCP configurados"
    }

    #Mostrar opciones activas
    Write-Host "Opciones DHCP:"
    Get-DhcpServerv4OptionValue -ErrorAction SilentlyContinue |
        Format-Table OptionId, Name, Value

    Read-Host "ENTER para volver al menu"
}


        default {
            Write-Host "Opcion invalida"
            Start-Sleep 1
        }
    }
}
