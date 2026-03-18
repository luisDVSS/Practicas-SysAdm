Import-Module WebAdministration

$thumb  = "9631A9BF9494CD8CD79541901454B508C40EA208"
$puerto = 443

# Binding HTTPS
New-WebBinding -Name "Default Web Site" -Protocol "https" -Port $puerto -IPAddress "*" -SslFlags 0
Write-Host "[1] Binding creado."

# Registrar cert en http.sys
$guid = "{$(New-Guid)}"
netsh http add sslcert ipport="0.0.0.0:$puerto" certhash=$thumb appid="$guid"

# Reiniciar sitio
Restart-WebItem "IIS:\Sites\Default Web Site" -ErrorAction SilentlyContinue
iisreset /noforce 2>&1 | Out-Null
Start-Sleep 4

# Verificar
Write-Host "--- Bindings ---"
Get-WebBinding -Name "Default Web Site"
Write-Host "--- sslcert ---"
netsh http show sslcert ipport="0.0.0.0:$puerto"
Write-Host "--- netstat ---"
netstat -ano | Select-String ":443"