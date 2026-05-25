#Requires -RunAsAdministrator
Clear-Host
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " FASE 6: FGPP Y AUDITORIA DE EVENTOS            " -ForegroundColor Cyan
Write-Host " Windows Server 2022 - Sin entorno grafico      " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# ----------------------------------------------------------
# VARIABLES BASE
# ----------------------------------------------------------
$Dominio = (Get-ADDomain).DistinguishedName

Write-Host "`n  Dominio DN : $Dominio`n" -ForegroundColor DarkGray

# ----------------------------------------------------------
# GUARDIA: Verificar que Fase 5 corrio primero
# ----------------------------------------------------------
Write-Host "> 0. Verificando dependencias de Fase 5..." -ForegroundColor Yellow

if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Administradores_Delegados'" -ErrorAction SilentlyContinue)) {
    Write-Host "  [-] ERROR: OU 'Administradores_Delegados' no existe." -ForegroundColor Red
    Write-Host "  [!] Ejecuta Fase_5_RBAC.ps1 antes de continuar." -ForegroundColor Yellow
    exit
}

$rolesFase5 = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")
$rolesFaltantes = $rolesFase5 | Where-Object {
    -not (Get-ADUser -Filter "SamAccountName -eq '$_'" -ErrorAction SilentlyContinue)
}
if ($rolesFaltantes) {
    Write-Host "  [-] Usuarios faltantes de Fase 5: $($rolesFaltantes -join ', ')" -ForegroundColor Red
    Write-Host "  [!] Ejecuta Fase_5_RBAC.ps1 antes de continuar." -ForegroundColor Yellow
    exit
}
Write-Host "  [+] Dependencias de Fase 5 verificadas." -ForegroundColor Green

# ----------------------------------------------------------
# 1. CREAR GRUPOS DE SEGURIDAD PARA FGPP
# (FGPP solo aplica a usuarios o grupos, no directamente a OUs)
# ----------------------------------------------------------
Write-Host "`n> 1. Creando Grupos de Seguridad para FGPP..." -ForegroundColor Yellow

$GrupoAdmins   = "Grupo_FGPP_Admins"
$GrupoEstandar = "Grupo_FGPP_Estandar"

foreach ($grupo in @($GrupoAdmins, $GrupoEstandar)) {
    if (-not (Get-ADGroup -Filter "Name -eq '$grupo'" -ErrorAction SilentlyContinue)) {
        New-ADGroup `
            -Name          $grupo `
            -GroupCategory Security `
            -GroupScope    Global `
            -Path          "CN=Users,$Dominio" | Out-Null
        Write-Host "  [+] Grupo '$grupo' creado." -ForegroundColor Green
    } else {
        Write-Host "  [-] Grupo '$grupo' ya existe." -ForegroundColor DarkGray
    }
}

# Poblar Grupo_FGPP_Admins con los 4 roles delegados de Fase 5
$admins = Get-ADUser -Filter * `
          -SearchBase "OU=Administradores_Delegados,$Dominio" `
          -ErrorAction SilentlyContinue
foreach ($admin in $admins) {
    Add-ADGroupMember -Identity $GrupoAdmins -Members $admin -ErrorAction SilentlyContinue
}
Write-Host "  [+] Administradores delegados agregados a '$GrupoAdmins'." -ForegroundColor Green

# Poblar Grupo_FGPP_Estandar con usuarios de cuates y NoCuates 
foreach ($ou in @("OU=Cuates,$Dominio", "OU=NoCuates,$Dominio")) {
    $usuarios = Get-ADUser -Filter * -SearchBase $ou -ErrorAction SilentlyContinue
    foreach ($usr in $usuarios) {
        Add-ADGroupMember -Identity $GrupoEstandar -Members $usr -ErrorAction SilentlyContinue
    }
}
Write-Host "  [+] Usuarios estandar agregados a '$GrupoEstandar'." -ForegroundColor Green

# ----------------------------------------------------------
# 2. CREAR Y APLICAR FGPP
# ----------------------------------------------------------
Write-Host "`n> 2. Configurando Directivas de Contrasena Ajustada (FGPP)..." -ForegroundColor Yellow

# FGPP Admins: 12 caracteres + bloqueo 3 intentos = 30 minutos
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'FGPP_Admins_12'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy `
        -Name                        "FGPP_Admins_12" `
        -Precedence                  10 `
        -MinPasswordLength           12 `
        -MaxPasswordAge              (New-TimeSpan -Days 90) `
        -MinPasswordAge              (New-TimeSpan -Days 1) `
        -PasswordHistoryCount        5 `
        -ComplexityEnabled           $true `
        -ReversibleEncryptionEnabled $false `
        -LockoutDuration             (New-TimeSpan -Minutes 30) `
        -LockoutObservationWindow    (New-TimeSpan -Minutes 15) `
        -LockoutThreshold            3 | Out-Null

    Add-ADFineGrainedPasswordPolicySubject `
        -Identity "FGPP_Admins_12" `
        -Subjects $GrupoAdmins
    Write-Host "  [+] FGPP_Admins_12 : 12 chars, bloqueo 3 intentos / 30 min." -ForegroundColor Green
} else {
    Write-Host "  [-] FGPP_Admins_12 ya existe." -ForegroundColor DarkGray
}

# FGPP Estandar: 8 caracteres + bloqueo 3 intentos = 30 minutos
if (-not (Get-ADFineGrainedPasswordPolicy -Filter "Name -eq 'FGPP_Estandar_8'" -ErrorAction SilentlyContinue)) {
    New-ADFineGrainedPasswordPolicy `
        -Name                        "FGPP_Estandar_8" `
        -Precedence                  20 `
        -MinPasswordLength           8 `
        -MaxPasswordAge              (New-TimeSpan -Days 90) `
        -MinPasswordAge              (New-TimeSpan -Days 1) `
        -PasswordHistoryCount        3 `
        -ComplexityEnabled           $true `
        -ReversibleEncryptionEnabled $false `
        -LockoutDuration             (New-TimeSpan -Minutes 30) `
        -LockoutObservationWindow    (New-TimeSpan -Minutes 15) `
        -LockoutThreshold            3 | Out-Null

    Add-ADFineGrainedPasswordPolicySubject `
        -Identity "FGPP_Estandar_8" `
        -Subjects $GrupoEstandar
    Write-Host "  [+] FGPP_Estandar_8: 8 chars, bloqueo 3 intentos / 30 min." -ForegroundColor Green
} else {
    Write-Host "  [-] FGPP_Estandar_8 ya existe." -ForegroundColor DarkGray
}

# ----------------------------------------------------------
# 3. HARDENING DE AUDITORIA CON AUDITPOL
# Se intentan nombres en espanol e ingles para cubrir
# cualquier configuracion de idioma de WS2022
# ----------------------------------------------------------
Write-Host "`n> 3. Activando politicas de auditoria..." -ForegroundColor Yellow

$subcategorias = @(
    @{ ES = "Inicio de sesion";            EN = "Logon" },
    @{ ES = "Cierre de sesion";            EN = "Logoff" },
    @{ ES = "Acceso a objetos";            EN = "Object Access" },
    @{ ES = "Cambio de politica";          EN = "Policy Change" },
    @{ ES = "Uso de privilegios";          EN = "Privilege Use" },
    @{ ES = "Administracion de cuentas";   EN = "Account Management" }
)

foreach ($sub in $subcategorias) {
    auditpol /set /subcategory:"$($sub.ES)" /success:enable /failure:enable 2>$null | Out-Null
    auditpol /set /subcategory:"$($sub.EN)" /success:enable /failure:enable 2>$null | Out-Null
    Write-Host "  [+] Auditoria '$($sub.EN)' habilitada." -ForegroundColor Green
}

# ----------------------------------------------------------
# 4. GENERAR SCRIPT DE MONITOREO PARA admin_auditoria
# ----------------------------------------------------------
Write-Host "`n> 4. Generando script de extraccion de alertas..." -ForegroundColor Yellow

if (-not (Test-Path "C:\Reportes_Auditoria")) {
    New-Item -Path "C:\Reportes_Auditoria" -ItemType Directory -Force | Out-Null
}

$ScriptAuditor = @'
#Requires -RunAsAdministrator
Clear-Host
Write-Host "=====================================================" -ForegroundColor Red
Write-Host " REPORTE DE INTENTOS DE INTRUSION - Evento ID 4625  " -ForegroundColor Red
Write-Host " Generado : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') " -ForegroundColor Gray
Write-Host "=====================================================" -ForegroundColor Red

$FechaStamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$RutaReporte = "C:\Reportes_Auditoria\Reporte_$FechaStamp.csv"

try {
    $Eventos = Get-WinEvent -FilterHashtable @{
        LogName = 'Security'
        Id      = 4625
    } -MaxEvents 10 -ErrorAction Stop

    $Reporte = $Eventos | ForEach-Object {
        [PSCustomObject]@{
            Fecha      = $_.TimeCreated.ToString("yyyy-MM-dd HH:mm:ss")
            EventoID   = $_.Id
            Usuario    = $_.Properties[5].Value
            Dominio    = $_.Properties[6].Value
            Origen_IP  = $_.Properties[19].Value
            Tipo_Fallo = $_.Properties[8].Value
        }
    }

    $Reporte | Format-Table -AutoSize
    $Reporte | Export-Csv -Path $RutaReporte -NoTypeInformation -Encoding UTF8

    Write-Host "`n[+] $($Eventos.Count) evento(s) encontrados." -ForegroundColor Green
    Write-Host "[+] Reporte CSV guardado en: $RutaReporte"      -ForegroundColor Green

} catch {
    Write-Host "[-] No se encontraron eventos 4625 recientes." -ForegroundColor Green
    Write-Host "    El sistema no registra intentos fallidos recientes." -ForegroundColor DarkGray
}
'@

$ScriptAuditor | Out-File "C:\Auditar_Accesos.ps1" -Encoding UTF8
Write-Host "  [+] Script generado en C:\Auditar_Accesos.ps1" -ForegroundColor Green

# ----------------------------------------------------------
# 5. VERIFICACION FINAL
# ----------------------------------------------------------
Write-Host "`n> 5. Verificacion de resultados..." -ForegroundColor Yellow

$errores = 0

# Verificar grupos FGPP
foreach ($grupo in @($GrupoAdmins, $GrupoEstandar)) {
    if (Get-ADGroup -Filter "Name -eq '$grupo'" -ErrorAction SilentlyContinue) {
        Write-Host "  [OK] Grupo '$grupo' existe." -ForegroundColor Green
    } else {
        Write-Host "  [FALLO] Grupo '$grupo' no encontrado." -ForegroundColor Red
        $errores++
    }
}

# Verificar FGPP
foreach ($politica in @("FGPP_Admins_12", "FGPP_Estandar_8")) {
    $fgpp = Get-ADFineGrainedPasswordPolicy -Identity $politica -ErrorAction SilentlyContinue
    if ($fgpp) {
        Write-Host "  [OK] $politica | MinLen: $($fgpp.MinPasswordLength) | Lockout: $($fgpp.LockoutThreshold) intentos / $($fgpp.LockoutDuration.TotalMinutes) min" -ForegroundColor Green
    } else {
        Write-Host "  [FALLO] $politica no encontrada." -ForegroundColor Red
        $errores++
    }
}

# Verificar auditoria
$auditCheck = auditpol /get /subcategory:"Logon" 2>$null
if ($auditCheck -match "Success and Failure|Exito y error") {
    Write-Host "  [OK] Auditoria de Logon activa (Exito y Fallo)." -ForegroundColor Green
} else {
    Write-Host "  [!] Verifica auditoria manualmente con: auditpol /get /category:*" -ForegroundColor Yellow
}

# Verificar script de monitoreo
if (Test-Path "C:\Auditar_Accesos.ps1") {
    Write-Host "  [OK] Script de auditoria generado." -ForegroundColor Green
} else {
    Write-Host "  [FALLO] Script de auditoria no generado." -ForegroundColor Red
    $errores++
}

Write-Host "`n=================================================" -ForegroundColor Cyan
if ($errores -eq 0) {
    Write-Host " FASE 6 COMPLETADA EXITOSAMENTE                 " -ForegroundColor Green
} else {
    Write-Host " FASE 6 COMPLETADA CON $errores ERROR(ES)        " -ForegroundColor Red
}
Write-Host "=================================================" -ForegroundColor Cyan
