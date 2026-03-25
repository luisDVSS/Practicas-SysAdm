$Dominio = (Get-ADDomain).DistinguishedName
$NombreDominio = (Get-ADDomain).Name
$Gpo = Get-GPO -Name "GPO-HorarioNoCuates"
$GpoId = $Gpo.Id.ToString()
$gpoPath = "\\empresa.local\SYSVOL\empresa.local\Policies\{$GpoId}\Machine\Microsoft\Windows NT\AppLocker"

# XML con regla por NOMBRE/RUTA - bloquea notepad.exe a NoCuates
$xml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="Permitir Program Files" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a319-4cd0-9690-d2177cad7b51" Name="Permitir Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2" Name="Permitir Administradores" Description="" UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions><FilePathCondition Path="*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="bd6e1e66-1234-5678-abcd-ef1234567890" Name="Bloquear Notepad NoCuates" Description="Bloquea notepad.exe a usuarios NoCuates" UserOrGroupSid="$(
        (Get-ADGroup -Identity 'Grupo_NoCuates').SID.Value
    )" Action="Deny">
      <Conditions><FilePathCondition Path="%WINDIR%\System32\notepad.exe" /></Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@

New-Item -Path $gpoPath -ItemType Directory -Force | Out-Null
$xml | Out-File "$gpoPath\Exe.xml" -Encoding UTF8 -Force

# Registrar CSE
$GpoIdUpper = $GpoId.ToUpper()
Set-ADObject -Identity "CN={$GpoIdUpper},CN=Policies,CN=System,$Dominio" `
    -Replace @{ gPCMachineExtensionNames = "[{F312195E-3D9D-447A-A3F5-08DFFA22735E}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]" }

Write-Host "Listo. Corre gpupdate /force en el cliente." -ForegroundColor Green
Get-Content "$gpoPath\Exe.xml"
