$Dominio = (Get-ADDomain).DistinguishedName
$NombreDominio = (Get-ADDomain).Name
$Gpo = Get-GPO -Name "GPO-HorarioNoCuates"
$GpoId = $Gpo.Id.ToString()
$gpoPath = "\\empresa.local\SYSVOL\empresa.local\Policies\{$GpoId}\Machine\Microsoft\Windows NT\AppLocker"

# XML con regla por NOMBRE/RUTA - bloquea notepad.exe a NoCuates
$xml = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Appx" EnforcementMode="NotConfigured"/>
  <RuleCollection Type="Dll" EnforcementMode="NotConfigured"/>
  <RuleCollection Type="Msi" EnforcementMode="NotConfigured"/>
  <RuleCollection Type="Script" EnforcementMode="NotConfigured"/>

  <RuleCollection Type="Exe" EnforcementMode="Enabled">

    <!-- Administradores: acceso total -->
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2"
      Name="Permitir Administradores"
      Description=""
      Action="Allow" UserOrGroupSid="S-1-5-32-544">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>

    <!-- Everyone: rutas del sistema -->
    <FilePathRule Id="a1000001-0000-0000-0000-000000000001"
      Name="Permitir System32"
      Description=""
      Action="Allow" UserOrGroupSid="S-1-1-0">
      <Conditions>
        <FilePathCondition Path="%SYSTEM32%\*"/>
      </Conditions>
    </FilePathRule>

    <FilePathRule Id="a1000002-0000-0000-0000-000000000002"
      Name="Permitir SysWOW64"
      Description=""
      Action="Allow" UserOrGroupSid="S-1-1-0">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\SysWOW64\*"/>
      </Conditions>
    </FilePathRule>

    <FilePathRule Id="a1000003-0000-0000-0000-000000000003"
      Name="Permitir Program Files"
      Description=""
      Action="Allow" UserOrGroupSid="S-1-1-0">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*"/>
      </Conditions>
    </FilePathRule>

    <FilePathRule Id="a1000004-0000-0000-0000-000000000004"
      Name="Permitir Program Files x86"
      Description=""
      Action="Allow" UserOrGroupSid="S-1-1-0">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES(X86)%\*"/>
      </Conditions>
    </FilePathRule>

    <!-- Bloqueo de Notepad: ruta absoluta (más confiable) -->
    <FilePathRule Id="d0000001-0000-0000-0000-000000000001"
      Name="Bloquear Notepad por ruta"
      Description=""
      Action="Deny" UserOrGroupSid="S-1-1-0">
      <Conditions>
        <FilePathCondition Path="%SYSTEM32%\notepad.exe"/>
      </Conditions>
    </FilePathRule>

    <!-- También bloquear desde WINDIR raíz (Windows lo copia ahí) -->
    <FilePathRule Id="d0000003-0000-0000-0000-000000000003"
      Name="Bloquear Notepad raiz Windows"
      Description=""
      Action="Deny" UserOrGroupSid="S-1-1-0">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\notepad.exe"/>
      </Conditions>
    </FilePathRule>

    <FileHashRule Id="d0000002-0000-0000-0000-000000000002"
      Name="Bloquear Notepad por hash"
      Description=""
      Action="Deny" UserOrGroupSid="S-1-1-0">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256"
            Data="0xF9D9B9DED9A67AA3CFDBD5002F3B524B265C4086C188E1BE7C936AB25627BF01"
            SourceFileName="notepad.exe"
            SourceFileLength="201216"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

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
