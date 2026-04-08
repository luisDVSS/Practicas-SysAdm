# ==============================================================
# DIAGNOSTICO COMPLETO DE APPLOCKER
# Ejecutar en el cliente Windows 10 como empresa\Administrador
# ==============================================================

$sep = "=" * 60
$gpoId = "12060e52-1cdf-4d42-af1a-2e2195c39679"
$gpoNombre = "GPO-HorarioNoCuates"
$dominio = "empresa.local"

function titulo($txt) {
    Write-Host "`n$sep" -ForegroundColor Cyan
    Write-Host "  $txt" -ForegroundColor Cyan
    Write-Host $sep -ForegroundColor Cyan
}

# --------------------------------------------------------------
titulo "1. USUARIO Y MAQUINA ACTUAL"
# --------------------------------------------------------------
Write-Host "Usuario actual : $(whoami)"
Write-Host "Nombre equipo  : $env:COMPUTERNAME"
Write-Host "Hora local     : $(Get-Date)"

# --------------------------------------------------------------
titulo "2. ESTADO DEL SERVICIO AppIDSvc"
# --------------------------------------------------------------
$svc = Get-Service AppIDSvc
Write-Host "Estado   : $($svc.Status)"
Write-Host "StartType: $($svc.StartType)"

if ($svc.Status -ne "Running") {
    Write-Host "[!] El servicio NO esta corriendo. Intentando arrancar..." -ForegroundColor Yellow
    Start-Service AppIDSvc
    Start-Sleep 3
    Write-Host "Estado ahora: $((Get-Service AppIDSvc).Status)"
}

# --------------------------------------------------------------
titulo "3. POLITICA APPLOCKER EFECTIVA EN ESTE EQUIPO"
# --------------------------------------------------------------
$effective = Get-AppLockerPolicy -Effective
Write-Host "Version            : $($effective.Version)"
Write-Host "RuleCollections    : $($effective.RuleCollections)"
Write-Host "RuleCollectionTypes: $($effective.RuleCollectionTypes)"

# --------------------------------------------------------------
titulo "4. POLITICA APPLOCKER DIRECTO DESDE EL GPO (LDAP)"
# --------------------------------------------------------------
try {
    $ldap = "LDAP://CN={$gpoId},CN=Policies,CN=System,DC=empresa,DC=local"
    $polGPO = Get-AppLockerPolicy -Domain -Ldap $ldap
    Write-Host "Version            : $($polGPO.Version)"
    Write-Host "RuleCollections    : $($polGPO.RuleCollections)"
    Write-Host "RuleCollectionTypes: $($polGPO.RuleCollectionTypes)"
} catch {
    Write-Host "[ERROR] No se pudo leer la politica via LDAP: $_" -ForegroundColor Red
}

# --------------------------------------------------------------
titulo "5. REGISTRO LOCAL DE APPLOCKER (SrpV2)"
# --------------------------------------------------------------
$srp = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\SrpV2"
if (Test-Path $srp) {
    Write-Host "La clave SrpV2 EXISTE en el registro:" -ForegroundColor Green
    Get-ChildItem $srp | ForEach-Object {
        Write-Host "  $($_.PSChildName)"
        Get-ItemProperty $_.PSPath | Select-Object * -ExcludeProperty PS* | Format-List
    }
} else {
    Write-Host "[!] La clave SrpV2 NO existe. AppLocker no tiene politica cacheada." -ForegroundColor Yellow
}

# --------------------------------------------------------------
titulo "6. GPRESULT - GPOs APLICADOS A ESTE EQUIPO"
# --------------------------------------------------------------
gpresult /r /scope computer

# --------------------------------------------------------------
titulo "7. SYSVOL - CONTENIDO DEL XML EN EL GPO"
# --------------------------------------------------------------
$rutaSysvol = "\\$dominio\SYSVOL\$dominio\Policies\{$gpoId}\Machine\Microsoft\Windows NT\AppLocker\Exe.xml"
if (Test-Path $rutaSysvol) {
    Write-Host "Archivo existe: $rutaSysvol" -ForegroundColor Green

    # Verificar BOM
    $bytes = [System.IO.File]::ReadAllBytes($rutaSysvol)
    $bom = ($bytes[0..2] | ForEach-Object { "{0:X2}" -f $_ }) -join " "
    Write-Host "Primeros 3 bytes (BOM check): $bom"
    if ($bom -eq "EF BB BF") {
        Write-Host "[!] El archivo tiene BOM UTF-8. Esto puede impedir que AppLocker lo parsee." -ForegroundColor Red
    } else {
        Write-Host "[OK] Sin BOM. Encoding correcto." -ForegroundColor Green
    }

    Write-Host "`nContenido del XML:"
    Get-Content $rutaSysvol
} else {
    Write-Host "[ERROR] No se encontro el archivo en SYSVOL: $rutaSysvol" -ForegroundColor Red
}

# --------------------------------------------------------------
titulo "8. EXTENSION CSE DE APPLOCKER EN EL OBJETO GPO (AD)"
# --------------------------------------------------------------
try {
    $gpoObj = [ADSI]"LDAP://CN={$($gpoId.ToUpper())},CN=Policies,CN=System,DC=empresa,DC=local"
    $ext = $gpoObj.Properties["gPCMachineExtensionNames"].Value
    Write-Host "gPCMachineExtensionNames: $ext"
    $cseBuena = "{F312195E-3D9D-447A-A3F5-08DFFA22735E}{D02B1F72-3407-48AE-BA88-E8213C6761F1}"
    if ($ext -like "*F312195E*") {
        Write-Host "[OK] El CSE de AppLocker esta registrado en el GPO." -ForegroundColor Green
    } else {
        Write-Host "[!] El CSE de AppLocker NO esta en gPCMachineExtensionNames." -ForegroundColor Red
        Write-Host "    Valor esperado (entre otros): [$cseBuena]"
    }
} catch {
    Write-Host "[ERROR] No se pudo leer el atributo del GPO: $_" -ForegroundColor Red
}

# --------------------------------------------------------------
titulo "9. LOG DE EVENTOS DE APPLOCKER"
# --------------------------------------------------------------
Write-Host "Ultimos 10 eventos de AppLocker (EXE and DLL):"
Get-WinEvent -LogName "Microsoft-Windows-AppLocker/EXE and DLL" -MaxEvents 10 -ErrorAction SilentlyContinue |
    Format-Table TimeCreated, Id, Message -AutoSize

# --------------------------------------------------------------
titulo "10. RESUMEN FINAL"
# --------------------------------------------------------------
Write-Host ""
$checks = @(
    @{ Ok = ($svc.Status -eq "Running");      Msg = "AppIDSvc corriendo" },
    @{ Ok = ($effective.RuleCollections -ne "{}"); Msg = "Politica efectiva con reglas" },
    @{ Ok = (Test-Path $rutaSysvol);          Msg = "Exe.xml existe en SYSVOL" },
    @{ Ok = ($bom -ne "EF BB BF");            Msg = "XML sin BOM" }
)
foreach ($c in $checks) {
    $color = if ($c.Ok) { "Green" } else { "Red" }
    $icono = if ($c.Ok) { "[OK]" } else { "[FALLA]" }
    Write-Host "$icono $($c.Msg)" -ForegroundColor $color
}
