@echo off
chcp 65001 >nul
setlocal
REM انقر نقراً مزدوجاً لتشغيل لوحة NABOO الإدارية على Windows.
REM يحرّر المنفذ 3010، يحذف .next، ويعيد التشغيل.

cd /d "%~dp0"
set PORT=3010

echo ==================================
echo   NABOO Admin — clean start
echo   path: %CD%
echo   port: %PORT%
echo ==================================

REM إيقاف أي عملية على المنفذ 3010 إن وُجدت
for /f "tokens=5" %%p in ('netstat -ano ^| findstr ":%PORT% " ^| findstr LISTENING') do (
  echo * Stopping PID %%p on port %PORT%...
  taskkill /F /PID %%p >nul 2>&1
)

if exist ".next" (
  echo * Removing .next cache...
  rmdir /s /q ".next"
)

if not exist "node_modules\" (
  echo * Installing dependencies...
  call npm install
  if errorlevel 1 (
    echo فشل npm install — تأكد من تثبيت Node.js من https://nodejs.org
    pause
    exit /b 1
  )
)

if not exist ".env.local" (
  echo.
  echo خطأ: ملف .env.local غير موجود.
  echo انسخ .env.local.example إلى .env.local واملأ المفاتيح من جهاز الماك.
  pause
  exit /b 1
)

echo * Starting server...
echo   Open: http://localhost:%PORT%
echo   Stop: Ctrl+C
echo ==================================
call npm run dev
pause
