# scripts/build_release.ps1
# بناء إصدار (release) على Windows مع تمرير المفاتيح تلقائياً من env\prod.env.
#
# الاستعمال (PowerShell):
#   .\scripts\build_release.ps1 windows   # تطبيق Windows
#   .\scripts\build_release.ps1 apk        # Android APK
#   .\scripts\build_release.ps1 appbundle  # Android AAB (للنشر على Play)
#   .\scripts\build_release.ps1 web        # نسخة الويب
#
# ملاحظة: iOS و macOS لا يُبنيان على Windows (يتطلبان جهاز Apple).

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('windows', 'apk', 'appbundle', 'aab', 'web')]
    [string]$Target
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$EnvFile = 'env\prod.env'
if (-not (Test-Path $EnvFile)) {
    Write-Error "خطأ: $EnvFile غير موجود. انسخ env\prod.env.example إلى env\prod.env واملأ القيم."
    exit 1
}

Write-Host "بناء [$Target] بالإصدار (release) باستخدام $EnvFile ..."

switch ($Target) {
    'windows'    { flutter build windows --release --dart-define-from-file="$EnvFile" }
    'apk'        { flutter build apk --release --dart-define-from-file="$EnvFile" }
    { $_ -in 'appbundle', 'aab' } { flutter build appbundle --release --dart-define-from-file="$EnvFile" }
    'web'        { flutter build web --release --dart-define-from-file="$EnvFile" }
}

Write-Host "تم البناء بنجاح ✅"
