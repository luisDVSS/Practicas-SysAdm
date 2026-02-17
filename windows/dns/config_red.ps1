
# Importar funciones auxiliares

. .\Funciones.ps1 


# Configurar DNS

function Set-ConfigDns {

    Write-Host "Configurando DNS..."

    while ($true) {
        $dominio = Read-Host "Ingresa el nombre del dominio"

        if (-not (Is-DomainName $dominio)) {
            Write-Host "Nombre de dominio no valido"
            continue
        }

        if (Domain-Exists $dominio) {
            Write-Host "Este dominio ya esta agregado"
            continue
        }

        break
    }

    # Solicitar IP

    while ($true) {
        $ip_add = Read-Host "Ingresa la IP"

        if (-not (Is-HostIp $ip_add)) {
            Write-Host "IP no valida"
            continue
        }

        $dominio_inverso = Get-ZonaInversa $ip_add
        $ultimo_octeto   = Get-Octet $ip_add 4
        $zona_inversa    = "$dominio_inverso.in-addr.arpa"

        # Verificar si el PTR ya existe
        try {
            $ptr = Get-DnsServerResourceRecord `
                -ZoneName $zona_inversa `
                -RRType PTR `
                -ErrorAction Stop |
                Where-Object { $_.HostName -eq $ultimo_octeto }

            if ($ptr) {
                Write-Host "Esta IP ya esta registrada"
                continue
            }
        } catch {
            # Zona inversa no existe → OK
        }

        break
    }

    Set-ConfFiles $dominio $ip_add $dominio_inverso
    Reset-Dns
}


# Crear zonas y registros DNS

function Set-ConfFiles {
    param(
        [string]$Dominio,
        [string]$Ip,
        [string]$DominioInverso
    )

    $ultimo_octeto = Get-Octet $Ip 4
    $zona_inversa  = "$DominioInverso.in-addr.arpa"


    # Calcular NetworkId UNA vez

    $octetos   = $Ip.Split('.')
    $networkId = "$($octetos[0]).$($octetos[1]).$($octetos[2]).0/24"


    # Zona directa

    if (-not (Domain-Exists $Dominio)) {
        Add-DnsServerPrimaryZone `
            -Name $Dominio `
            -ZoneFile "$Dominio.dns" `
            -DynamicUpdate None
    }


    # Zona inversa

    if (-not (Get-DnsServerZone -Name $zona_inversa -ErrorAction SilentlyContinue)) {
        Write-Host "Creando zona inversa $zona_inversa"

        Add-DnsServerPrimaryZone `
            -NetworkId $networkId `
            -ZoneFile "$DominioInverso.dns" `
            -DynamicUpdate None
    }

  
    # Registros A

    Add-DnsServerResourceRecordA `
        -ZoneName $Dominio `
        -Name "@" `
        -IPv4Address $Ip `
        -AllowUpdateAny `
        -ErrorAction SilentlyContinue

    Add-DnsServerResourceRecordA `
        -ZoneName $Dominio `
        -Name "ns1" `
        -IPv4Address $Ip `
        -AllowUpdateAny `
        -ErrorAction SilentlyContinue

    Add-DnsServerResourceRecordA `
        -ZoneName $Dominio `
        -Name "www" `
        -IPv4Address $Ip `
        -AllowUpdateAny `
        -ErrorAction SilentlyContinue


    # Registro PTR (SEGURO)

    Add-DnsServerResourceRecordPtr `
        -ZoneName $zona_inversa `
        -Name $ultimo_octeto `
        -PtrDomainName "ns1.$Dominio" `
        -AllowUpdateAny `
        -ErrorAction SilentlyContinue
}
