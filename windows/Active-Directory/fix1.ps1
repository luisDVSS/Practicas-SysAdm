# parche_mfa_usuarios_existentes.ps1
# Ejecutar como Administrador

$RutaMultiOTP = "C:\Program Files\multiOTP"
$ExeMultiOTP  = ".\multiotp.exe"
Set-Location $RutaMultiOTP

$LlaveCuates = "JLDWY3DPEHPK3PXE"
$LlaveNoCuates = "JLDWY3DPEHPK3PXF"
$Dominio = (Get-ADDomain).DistinguishedName

Write-Host "Asignando MFA a Cuates..." -ForegroundColor Yellow
$UsersCuates = Get-ADUser -Filter * -SearchBase "OU=Cuates,$Dominio" -ErrorAction SilentlyContinue
foreach ($u in $UsersCuates) {
    $nombre = $u.SamAccountName.ToLower()
    if (Test-Path "$RutaMultiOTP\users\$nombre.db") { Remove-Item "$RutaMultiOTP\users\$nombre.db" -Force }
    & $ExeMultiOTP -createga $nombre $LlaveCuates | Out-Null
    & $ExeMultiOTP -set $nombre prefix-pin=0 | Out-Null
    Write-Host "  [+] Token asignado a: $nombre" -ForegroundColor Green
}

Write-Host "`nAsignando MFA a No Cuates..." -ForegroundColor Yellow
$UsersNoCuates = Get-ADUser -Filter * -SearchBase "OU=NoCuates,$Dominio" -ErrorAction SilentlyContinue
foreach ($u in $UsersNoCuates) {
    $nombre = $u.SamAccountName.ToLower()
    if (Test-Path "$RutaMultiOTP\users\$nombre.db") { Remove-Item "$RutaMultiOTP\users\$nombre.db" -Force }
    & $ExeMultiOTP -createga $nombre $LlaveNoCuates | Out-Null
    & $ExeMultiOTP -set $nombre prefix-pin=0 | Out-Null
    Write-Host "  [+] Token asignado a: $nombre" -ForegroundColor Green
}
