#Requires -RunAsAdministrator
Clear-Host
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " FASE 5: RBAC Y DELEGACION DE CONTROL           " -ForegroundColor Cyan
Write-Host " Windows Server 2022 - Sin entorno grafico      " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# ----------------------------------------------------------
# VARIABLES BASE
# ----------------------------------------------------------
$Dominio       = (Get-ADDomain).DistinguishedName
$NombreDominio = (Get-ADDomain).Name
$DominioDNS    = (Get-ADDomain).DNSRoot        
$PassSegura    = ConvertTo-SecureString "P@ssw0rdDelegado!" -AsPlainText -Force

Write-Host "`n  Dominio DN  : $Dominio"        -ForegroundColor DarkGray
Write-Host "  Dominio DNS : $DominioDNS"       -ForegroundColor DarkGray
Write-Host "  NetBIOS     : $NombreDominio`n"  -ForegroundColor DarkGray

# ----------------------------------------------------------
# FUNCION HELPER: Agregar a grupo mediante SID o RID
# ----------------------------------------------------------
function Agregar-GrupoPorSID {
    param(
        [string]$Identificador,
        [string]$Miembro,
        [string]$NombreLogico
    )
    try {
        # Busca el grupo en AD que coincida con el SID/RID proporcionado
        $Grupo = Get-ADGroup -Identity $Identificador -ErrorAction Stop
        if ($Grupo) {
            Add-ADGroupMember -Identity $Grupo.ObjectGUID -Members $Miembro -ErrorAction Stop
            Write-Host "    [+] '$Miembro' agregado a '$($Grupo.Name)' ($NombreLogico)." -ForegroundColor Green
        }
    } catch {
        Write-Host "    [-] Error al intentar agregar '$Miembro' al grupo $NombreLogico." -ForegroundColor Red
    }
}

# ----------------------------------------------------------
# 1. CREAR OU PARA ADMINISTRADORES DELEGADOS
# ----------------------------------------------------------
Write-Host "> 1. Verificando OU 'Administradores_Delegados'..." -ForegroundColor Yellow

$UODelegados = "Administradores_Delegados"
$RutaUO      = "OU=$UODelegados,$Dominio"

if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$UODelegados'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $UODelegados -Path $Dominio | Out-Null
    Write-Host "  [+] OU '$UODelegados' creada." -ForegroundColor Green
} else {
    Write-Host "  [-] OU ya existe. Continuando." -ForegroundColor DarkGray
}

# ----------------------------------------------------------
# 2. CREAR LOS 4 USUARIOS DE ROL
# ----------------------------------------------------------
Write-Host "`n> 2. Creando cuentas de Administradores Delegados..." -ForegroundColor Yellow

$Roles = @("admin_identidad", "admin_storage", "admin_politicas", "admin_auditoria")

foreach ($Rol in $Roles) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$Rol'" -ErrorAction SilentlyContinue)) {
        New-ADUser `
            -Name                "Delegado $Rol" `
            -SamAccountName      $Rol `
            -UserPrincipalName   "$Rol@$DominioDNS" `
            -AccountPassword     $PassSegura `
            -Path                $RutaUO `
            -Enabled             $true `
            -PasswordNeverExpires $true | Out-Null
        Write-Host "  [+] Usuario '$Rol' creado." -ForegroundColor Green
    } else {
        Write-Host "  [-] '$Rol' ya existe. Omitiendo." -ForegroundColor DarkGray
    }
}

# ----------------------------------------------------------
# 3. ASIGNAR GRUPOS NATIVOS POR ROL (Usando SIDs/RIDs Universales)
# ----------------------------------------------------------
Write-Host "`n> 3. Asignando membresías de grupo por rol..." -ForegroundColor Yellow

# ROL 3: Group Policy Creator Owners (RID: 520, es un grupo del dominio)
# Calculamos el SID dinámicamente usando el SID del dominio actual
Write-Host "  [*] admin_politicas -> Group Policy Creator Owners..."
try {
    $DomainSID = (Get-ADDomain).DomainSID.Value
    $SID_GPO = "$DomainSID-520"
    Agregar-GrupoPorSID -Identificador $SID_GPO -Miembro "admin_politicas" -NombreLogico "GPO Creator Owners"
} catch {
    Write-Host "    [-] Fallo critico al calcular SID de GPO." -ForegroundColor Red
}

# ROL 4: Event Log Readers (SID Local universal: S-1-5-32-573)
Write-Host "  [*] admin_auditoria -> Event Log Readers..."
Agregar-GrupoPorSID -Identificador "S-1-5-32-573" -Miembro "admin_auditoria" -NombreLogico "Event Log Readers"

# ROL 2: Server Operators (SID Local universal: S-1-5-32-549)
Write-Host "  [*] admin_storage -> Server Operators..."
Agregar-GrupoPorSID -Identificador "S-1-5-32-549" -Miembro "admin_storage" -NombreLogico "Server Operators"

# ROL 1: Sin grupo nativo, solo ACLs
Write-Host "  [*] admin_identidad -> Solo ACLs (sin grupo nativo)." -ForegroundColor DarkGray


# ----------------------------------------------------------
# 4. APLICAR ACLs GRANULARES CON DSACLS
# ----------------------------------------------------------
Write-Host "`n> 4. Aplicando ACLs con dsacls..." -ForegroundColor Yellow

$OUsObjetivo = @(
    "OU=Cuates,$Dominio",
    "OU=NoCuates,$Dominio"
)

# --- ROL 1: admin_identidad ---
Write-Host "  [*] ROL 1 - admin_identidad: Gestion completa de usuarios..."
foreach ($OU in $OUsObjetivo) {
    dsacls $OU /I:T /G "$NombreDominio\admin_identidad:CCDC;user"     2>$null | Out-Null
    dsacls $OU /I:S /G "$NombreDominio\admin_identidad:CA;Reset Password;user"   2>$null | Out-Null
    dsacls $OU /I:S /G "$NombreDominio\admin_identidad:CA;Change Password;user"  2>$null | Out-Null
    dsacls $OU /I:S /G "$NombreDominio\admin_identidad:WP;user"       2>$null | Out-Null
    Write-Host "    [+] ACLs de identidad en: $OU" -ForegroundColor Green
}

# --- ROL 2: admin_storage ---
Write-Host "  [*] ROL 2 - admin_storage: DENY Reset Password (dominio completo)..."
dsacls $Dominio /I:S /D "$NombreDominio\admin_storage:CA;Reset Password;user" 2>$null | Out-Null
Write-Host "    [+] DENY aplicado en raiz del dominio." -ForegroundColor Green

# --- ROL 3: admin_politicas ---
Write-Host "  [*] ROL 3 - admin_politicas: Lectura global + escritura gPLink..."
dsacls $Dominio /I:T /G "$NombreDominio\admin_politicas:GR" 2>$null | Out-Null
foreach ($OU in $OUsObjetivo) {
    dsacls $OU /I:T /G "$NombreDominio\admin_politicas:RPWP;gPLink" 2>$null | Out-Null
    Write-Host "    [+] gPLink habilitado en: $OU" -ForegroundColor Green
}

# --- ROL 4: admin_auditoria ---
Write-Host "  [*] ROL 4 - admin_auditoria: Read-Only en dominio..."
dsacls $Dominio /I:T /G "$NombreDominio\admin_auditoria:GR" 2>$null | Out-Null
Write-Host "    [+] Permiso de lectura global aplicado." -ForegroundColor Green

# ----------------------------------------------------------
# 5. VERIFICACION FINAL
# ----------------------------------------------------------
Write-Host "`n> 5. Verificacion de resultados..." -ForegroundColor Yellow

$errores = 0
foreach ($Rol in $Roles) {
    $user = Get-ADUser -Filter "SamAccountName -eq '$Rol'" -Properties MemberOf -ErrorAction SilentlyContinue
    if ($user) {
        $grupos = ($user.MemberOf | ForEach-Object { (Get-ADGroup $_).Name }) -join ", "
        if (-not $grupos) { $grupos = "Sin grupos adicionales (solo ACLs)" }
        Write-Host "  [OK] $Rol" -ForegroundColor Green
        Write-Host "       Grupos : $grupos" -ForegroundColor DarkGray
    } else {
        Write-Host "  [FALLO] $Rol no fue creado correctamente." -ForegroundColor Red
        $errores++
    }
}

Write-Host "`n=================================================" -ForegroundColor Cyan
if ($errores -eq 0) {
    Write-Host " FASE 5 COMPLETADA EXITOSAMENTE                 " -ForegroundColor Green
} else {
    Write-Host " FASE 5 COMPLETADA CON $errores ERROR(ES)        " -ForegroundColor Red
}
Write-Host " Contrasena temporal : P@ssw0rdDelegado!        " -ForegroundColor White
Write-Host "=================================================" -ForegroundColor Cyan
