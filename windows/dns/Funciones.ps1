
# Instalacion de servicios (equivalente a apt install)

function Get-ServiceFeature {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Features
    )

    foreach ($feature in $Features) {
        Install-WindowsFeature -Name $feature -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    }
}


# Obtener dominios (Windows DNS)

function Get-Domains {
    Write-Host ("{0,-30} {1,-15}" -f "DOMINIO", "IP")
    Write-Host ("{0,-30} {1,-15}" -f "------------------------------", "---------------")

    $zones = Get-DnsServerZone | Where-Object { $_.ZoneName -notlike "*.arpa" }

    foreach ($zone in $zones) {
        $record = Get-DnsServerResourceRecord -ZoneName $zone.ZoneName -RRType A -ErrorAction SilentlyContinue |
                  Select-Object -First 1

        if ($record) {
            $ip = $record.RecordData.IPv4Address.IPAddressToString
            Write-Host ("{0,-30} {1,-15}" -f $zone.ZoneName, $ip)
        }
    }
}


# Validar IP de host

function Is-HostIp {
    param([string]$Ip)

    if (-not (Is-IpFormat $Ip)) { return $false }

    $octets = $Ip.Split('.').ForEach({ [int]$_ })

    if ($Ip -in @("0.0.0.0","1.0.0.0","127.0.0.0","127.0.0.1","255.255.255.255")) {
        return $false
    }

    if ($octets[0] -eq 0) { return $false }

    return $true
}


# Validacion debil de IP

function Is-IpFormat {
    param([string]$Ip)

    if ($Ip -notmatch '^(\d{1,3}\.){3}\d{1,3}$') { return $false }

    foreach ($oct in $Ip.Split('.')) {
        if ([int]$oct -lt 0 -or [int]$oct -gt 255) {
            return $false
        }
    }

    return $true
}


# Validar nombre de dominio

function Is-DomainName {
    param([string]$Name)

    $regex = '^[a-zA-Z0-9]+(\-[a-zA-Z0-9]+)?\.[a-zA-Z]{2,}$'
    return $Name -match $regex
}
#verificacion si la ip es estatica
function Test-IPStatica {
    param (
        [string]$Interfaz
    )

    if (-not $Interfaz) {
        Write-Host "[ERROR] Debes indicar el nombre de la interfaz"
        return
    }

    $config = Get-NetIPInterface -InterfaceAlias $Interfaz -AddressFamily IPv4 -ErrorAction SilentlyContinue

    if (-not $config) {
        Write-Host "[ERROR] La interfaz no existe"
        return
    }

    if ($config.Dhcp -eq "Disabled") {
        Write-Host "La interfaz $Interfaz tiene IP ESTATICA" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host "La interfaz $Interfaz usa DHCP (IP DINAMICA)" -ForegroundColor Yellow
        return $false
    }
}
# Verificar si un Feature esta instalado

function Is-Installed {
    param([string]$Feature)

    $f = Get-WindowsFeature -Name $Feature
    return $f.Installed
}


# Validar entero

function Is-Int {
    param($Value)
    return $Value -match '^\d+$'
}


# IP a entero

function Ip-ToInt {
    param([string]$Ip)

    $o = $Ip.Split('.') | ForEach-Object { [int]$_ }
    return ($o[0] -shl 24) -bor ($o[1] -shl 16) -bor ($o[2] -shl 8) -bor $o[3]
}


# Mismo segmento

function Is-SameSegment {
    param($Ip1, $Ip2, $Mask)

    return ((Ip-ToInt $Ip1 -band Ip-ToInt $Mask) -eq (Ip-ToInt $Ip2 -band Ip-ToInt $Mask))
}


# Prefijo a mascara

function Prefix-ToMask {
    param([int]$Prefix)

    $mask = [uint32]0xFFFFFFFF -shl (32 - $Prefix)
    return Int-ToIp $mask
}

function Int-ToIp {
    param([uint32]$Int)

    return "{0}.{1}.{2}.{3}" -f `
        (($Int -shr 24) -band 255),
        (($Int -shr 16) -band 255),
        (($Int -shr 8) -band 255),
        ($Int -band 255)
}


# Zona inversa (/24)

function Get-ZonaInversa {
    param([string]$Ip)

    if (-not (Is-IpFormat $Ip)) { return $null }

    $o = $Ip.Split('.')
    return "$($o[2]).$($o[1]).$($o[0])"
}


# Reiniciar DNS (equivalente a bind restart)

function Reset-Dns {
    Restart-Service DNS -Force
}


# Obtener octeto

function Get-Octet {
    param([string]$Ip, [int]$Num)

    if ($Num -lt 1 -or $Num -gt 4) { return $null }
    if (-not (Is-IpFormat $Ip)) { return $null }

    return $Ip.Split('.')[$Num - 1]
}


# Verificar dominio existente

function Domain-Exists {
    param([string]$Domain)

    return (Get-DnsServerZone -Name $Domain -ErrorAction SilentlyContinue) -ne $null
}


# Eliminar dominio

function Delete-Domain {
    $domain = Read-Host "Dominio a eliminar"

    if (-not (Domain-Exists $domain)) {
        Write-Host "El dominio no existe"
        return
    }

    Remove-DnsServerZone -Name $domain -Force
    Write-Host "Dominio eliminado correctamente"
    Reset-Dns
}
function Set-ConfigDefaultEthernet2 {

    $Interfaz = "Ethernet 2"
    $IP       = "192.168.11.1"
    $Prefijo  = 24
    $Gateway  = "192.168.11.254"
    $DNS      = "192.168.11.1"

    Write-Host "Configurando $Interfaz con valores por defecto..." -ForegroundColor Cyan

    # Verificar que exista la interfaz
    if (-not (Get-NetAdapter -Name $Interfaz -ErrorAction SilentlyContinue)) {
        Write-Host "La interfaz $Interfaz no existe." -ForegroundColor Red
        return
    }

    # Desactivar DHCP
    Set-NetIPInterface -InterfaceAlias $Interfaz -Dhcp Disabled

    # Eliminar IPs previas
    Get-NetIPAddress -InterfaceAlias $Interfaz -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false

    # Asignar nueva IP
    New-NetIPAddress `
        -InterfaceAlias $Interfaz `
        -IPAddress $IP `
        -PrefixLength $Prefijo `
        -DefaultGateway $Gateway `
        -AddressFamily IPv4

    # Configurar DNS
    Set-DnsClientServerAddress `
        -InterfaceAlias $Interfaz `
        -ServerAddresses $DNS

    Write-Host "SE APLICO UNA CONFIGURACION POR DEFECTO DE RED CON VALORES:"
    Write-Host "Ethernet 2"
    Write-Host "IP=192.168.11.1"
    Write-Host "Prefijo=24"
    Write-Host "Gateway=192.168.11.254"
    Write-Host "DNS=192.168.11.1"
}