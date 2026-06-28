[Setup]
AppName=watchAny
AppVersion=2.0.2
DefaultDirName={autopf}\watchAny
DefaultGroupName=watchAny
OutputDir=build\windows
OutputBaseFilename=watchany_setup
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs

[Icons]
Name: "{group}\watchAny"; Filename: "{app}\watch_any.exe"
Name: "{autodesktop}\watchAny"; Filename: "{app}\watch_any.exe"

[Run]
Filename: "{app}\watch_any.exe"; Description: "Launch watchAny"; Flags: nowait postinstall skipifsilent

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
      RoamingAppPath := ExpandConstant('{userappdata}\com.example\watch_any');
      
      DelTree(LocalAppPath, True, True, True);
      DelTree(RoamingAppPath, True, True, True);
    end;
  end;
end;
