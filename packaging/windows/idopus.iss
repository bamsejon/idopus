; iDOpus — Inno Setup script (Windows installer)
;
; Build locally:
;   1. Build Release x64 of idopus-qt.exe via MSVC (see README → Windows build)
;   2. Run windeployqt on the binary so the Qt DLLs land next to it
;   3. Point ISCC.exe at this file:
;        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" \
;          /DIdopusSourceDir=C:\idopus\build\Release \
;          packaging\windows\idopus.iss
;
; The CI workflow at .github/workflows/windows-release.yml packages this on a
; tag push.

#define MyAppName       "iDOpus"
#define MyAppPublisher  "Jon Bylund"
#define MyAppURL        "https://github.com/bamsejon/idopus"
#define MyAppExeName    "idopus-qt.exe"

; Version injected by CI via /DIdopusVersion=... ; fallback to dev version.
#ifndef IdopusVersion
  #define IdopusVersion "0.0.0-dev"
#endif

; Source dir: where the built .exe + Qt DLLs live. Defaults to a local build.
#ifndef IdopusSourceDir
  #define IdopusSourceDir "..\..\build\Release"
#endif

[Setup]
AppId={{7F4D9A2C-2D4E-4B1F-A0F0-4C1A2D0B9B65}
AppName={#MyAppName}
AppVersion={#IdopusVersion}
AppVerName={#MyAppName} {#IdopusVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
DisableProgramGroupPage=yes
Compression=lzma2/max
SolidCompression=yes
OutputDir=build-installer
OutputBaseFilename=iDOpus-{#IdopusVersion}-Setup
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
PrivilegesRequiredOverridesAllowed=dialog
MinVersion=10.0.17763
UninstallDisplayIcon={app}\{#MyAppExeName}

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "associate_folder"; Description: "Set iDOpus as the default browser action when right-clicking folders (Open with iDOpus)"; GroupDescription: "Shell integration:"; Flags: unchecked

[Files]
; Grab everything windeployqt produced next to the binary. plugins/, translations/,
; Qt6*.dll, the MSVC runtime redist DLLs, etc.
Source: "{#IdopusSourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

; License + project metadata
Source: "..\..\LICENSE";   DestDir: "{app}"; DestName: "LICENSE.txt";   Flags: ignoreversion
Source: "..\..\README.md"; DestDir: "{app}"; DestName: "README.md";     Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Registry]
; "Open with iDOpus" on folder right-click — cheap shell integration.
Root: HKA; Subkey: "Software\Classes\Directory\shell\OpenWithIDOpus"; ValueType: string; ValueData: "Open with iDOpus"; Flags: uninsdeletekey; Tasks: associate_folder
Root: HKA; Subkey: "Software\Classes\Directory\shell\OpenWithIDOpus\command"; ValueType: string; ValueData: """{app}\{#MyAppExeName}"" ""%1"""; Tasks: associate_folder

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent
