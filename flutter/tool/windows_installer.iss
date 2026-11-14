#ifndef PayloadDir
  #error PayloadDir must point to the verified production portable bundle
#endif
#ifndef OutputDir
  #define OutputDir "..\..\downloads"
#endif

[Setup]
AppId={{807BE2A8-EA8D-4D1E-B573-990091A3EB98}
AppName=Space
AppVersion=2.3.4
AppPublisher=Cers-wy
AppPublisherURL=https://github.com/Cers-wy/Space-of-Work-and-Life
DefaultDirName={localappdata}\Programs\Space
DefaultGroupName=Space
DisableDirPage=no
AlwaysShowDirOnReadyPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.22000
WizardStyle=modern
OutputDir={#OutputDir}
OutputBaseFilename=Space-2.3.4-Windows-x64-Setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Space.exe
Compression=lzma2/fast
SolidCompression=yes
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#PayloadDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Space"; Filename: "{app}\Space.exe"
Name: "{autodesktop}\Space"; Filename: "{app}\Space.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Space.exe"; Description: "Launch Space"; Flags: nowait postinstall skipifsilent unchecked

; No registry, user-data, InstallDelete, or UninstallDelete entries:
; application data in %APPDATA%\SpaceFlutter and unknown files are preserved.
