; Inno Setup script لإنتاج مُثبّت ويندوز كلاسيكي لـ NABOO
; يعمل بدبل كليك: Next → Install → اختصار سطح المكتب → Run.
; يُبنى تلقائيًا داخل GitHub Actions (release-windows.yml).

#define MyAppName "NABOO"
#define MyAppPublisher "NABOO Systems"
#define MyAppURL "https://naboo-93580.web.app/"
#define MyAppExeName "naboo.exe"

; قيم تُحقن من سطر الأوامر (workflow): /DMyAppVersion=2.0.2 /DBuildSrc=...
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#ifndef BuildSrc
  #define BuildSrc "build\windows\x64\runner\Release"
#endif
#ifndef OutputBaseFilename
  #define OutputBaseFilename "naboo-windows-setup"
#endif

[Setup]
AppId={{F2A2E8E1-1E8A-4AE6-B6E4-3F1A6D7F9E10}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}

; لغة معالج التثبيت: الإنجليزية فقط (موثوق في CI؛ Arabic.isl قد يغيب في Inno من Chocolatey).
; التطبيق نفسه يبقى RTL وعربي حسب إعدادات Flutter.
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: checkedonce

[Files]
Source: "{#BuildSrc}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

