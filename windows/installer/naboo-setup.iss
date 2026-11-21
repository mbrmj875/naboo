; Inno Setup script لإنتاج مُثبّت ويندوز كلاسيكي لـ NABOO
; يعمل بدبل كليك: Next → Install → اختصار سطح المكتب → Run.
; يُبنى تلقائيًا داخل GitHub Actions (.github/workflows/release.yml).

#define MyAppName "NABOO"
#define MyAppPublisher "NABOO Systems"
#define MyAppURL "https://naboo-93580.web.app/"
#define MyAppExeName "naboo.exe"

; قيم تُحقن من سطر الأوامر (workflow): /DMyAppVersion=2.0.2 /DBuildSrc=...
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
; مسارات [Files] نسبية لمجلد السكربت (windows\installer\) — أو يُمرَّر مطلق من CI
#ifndef BuildSrc
  #define BuildSrc "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputBaseFilename
  #define OutputBaseFilename "naboo-windows-setup"
#endif

[Setup]
AppId={{F2A2E8E1-1E8A-4AE6-B6E4-3F1A6D7F9E10}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\Programs\{#MyAppName}
DefaultGroupName={#MyAppName}
; تثبيت بأبسط مسار: افتح الملف → Install → انتهى (بدون صفحات اختيار)
DisableWelcomePage=yes
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
CloseApplications=yes
RestartApplications=yes
UsePreviousAppDir=yes
OutputBaseFilename={#OutputBaseFilename}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; بدون مسؤول: مجلد المستخدم + مكتبات VC بجانب naboo.exe
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; مسار نسبي من موقع هذا الملف (windows\installer\) — لا يستخدم جذر المشروع
SetupIconFile=..\runner\resources\app_icon.ico
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
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Classes\io.supabase.naboo"; ValueType: string; ValueName: ""; ValueData: "URL:NABOO"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\io.supabase.naboo"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
Root: HKCU; Subkey: "Software\Classes\io.supabase.naboo\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "{cm:LaunchProgram,{#MyAppName}}"; Flags: nowait postinstall skipifsilent

