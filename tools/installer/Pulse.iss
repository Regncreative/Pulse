; Pulse Windows installer (Inno Setup 6)
; Produced by tools/scripts/package_beta.ps1
;
; End users double-click Pulse-Setup-*-windows-x64.exe
; No PowerShell. No ExecutionPolicy. UAC elevation only.

#define MyAppName "Pulse"
#define MyAppVersion "0.3.2-beta"
#define MyAppPublisher "Regncreative"
#define MyAppURL "https://github.com/Regncreative/Pulse"
#define MyAppExeName "Pulse.exe"

#ifndef PulsePayloadDir
  #define PulsePayloadDir "..\..\dist\Pulse"
#endif

#ifndef PulseOutDir
  #define PulseOutDir "..\..\dist"
#endif

[Setup]
AppId={{8F3C2A91-6D4E-4B7A-9E12-7C1D0A5B4E8F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\Pulse
DefaultGroupName=Pulse
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#PulseOutDir}
OutputBaseFilename=Pulse-Setup-{#MyAppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
RestartIfNeededByRun=no
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
Source: "{#PulsePayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Pulse"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall Pulse"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Pulse"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
; Launch after install — service is started in [Code] before this runs.
Filename: "{app}\{#MyAppExeName}"; \
  Description: "Launch Pulse"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{app}\service\PulseService.exe"; \
  Parameters: "--uninstall"; \
  Flags: runhidden waituntilterminated; \
  RunOnceId: "UninstallPulseService"
; Remove Pulse-created AI client MCP registrations only (never other servers).
; Prefer PulseMCP.exe (bundled private Node); fall back to PulseMCP.cmd.
Filename: "{cmd}"; \
  Parameters: "/c if exist ""{app}\PulseMCP.exe"" (""{app}\PulseMCP.exe"" --cleanup-registrations) else if exist ""{app}\PulseMCP.cmd"" (""{app}\PulseMCP.cmd"" --cleanup-registrations)"; \
  Flags: runhidden waituntilterminated; \
  RunOnceId: "CleanupPulseMcpRegistrations"

[Code]
function ExecChecked(const FileName, Params, WorkDir: String; var ResultCode: Integer): Boolean;
begin
  Result := Exec(FileName, Params, WorkDir, SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Redist: String;
  ServiceExe: String;
begin
  if CurStep <> ssPostInstall then
    Exit;

  Redist := ExpandConstant('{app}\redist\VC_redist.x64.exe');
  ServiceExe := ExpandConstant('{app}\service\PulseService.exe');

  { 1) Visual C++ Redistributable (quiet). 0 / 1638 / 3010 are acceptable. }
  if FileExists(Redist) then
  begin
    WizardForm.StatusLabel.Caption := 'Installing Visual C++ runtime…';
    if ExecChecked(Redist, '/install /quiet /norestart',
                   ExpandConstant('{app}\redist'), ResultCode) then
    begin
      if (ResultCode <> 0) and (ResultCode <> 1638) and (ResultCode <> 3010) then
        MsgBox('Visual C++ Redistributable returned exit code ' + IntToStr(ResultCode) + '.' + #13#10 +
               'Pulse may still run using bundled runtime DLLs.',
               mbInformation, MB_OK);
    end;
  end;

  { 2) Register + auto-start + start PulseService. No PowerShell. }
  WizardForm.StatusLabel.Caption := 'Installing and starting PulseService…';
  if not FileExists(ServiceExe) then
  begin
    MsgBox('PulseService.exe is missing from the install folder.', mbError, MB_OK);
    Exit;
  end;

  if not ExecChecked(ServiceExe, '--install-start',
                     ExpandConstant('{app}\service'), ResultCode) then
  begin
    MsgBox('Could not run PulseService --install-start.', mbError, MB_OK);
    Exit;
  end;

  if ResultCode <> 0 then
  begin
    MsgBox('PulseService did not start (exit code ' + IntToStr(ResultCode) + ').' + #13#10 +
           'Pulse will stay Offline until the service is running.' + #13#10 +
           'Reboot and open Pulse from the Start menu, or re-run this installer.',
           mbError, MB_OK);
    Exit;
  end;

  WizardForm.StatusLabel.Caption := 'PulseService is running.';
end;
