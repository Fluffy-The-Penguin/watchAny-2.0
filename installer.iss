#define MyAppName "watchAny"
#define MyAppVersion "2.2.46"
#define MyAppPublisher "watchAny"
#define MyAppURL "https://watchany.app"
#define MyAppExeName "watch_any.exe"

[Setup]
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
AppCopyright=Copyright (C) 2026 watchAny. All rights reserved.
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=build\windows
OutputBaseFilename=watchany_setup_{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
#ifndef WinReleaseDir
#define WinReleaseDir "build\windows\x64\runner\Release"
#endif

[Files]
Source: "{#WinReleaseDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

[Code]
procedure CurUninstallStepChanged(UninstallStep: TUninstallStep);
var
  LocalAppPath: String;
  RoamingAppPath: String;
begin
  if UninstallStep = usPostUninstall then
  begin
    if MsgBox('Do you want to clear all application data, settings, and downloaded cache?', mbConfirmation, MB_YESNO) = idYes then
    begin
      LocalAppPath := ExpandConstant('{localappdata}\watch_any');
      RoamingAppPath := ExpandConstant('{userappdata}\watchAny\watch_any');

      DelTree(LocalAppPath, True, True, True);
      DelTree(RoamingAppPath, True, True, True);
    end;
  end;
end;






































































