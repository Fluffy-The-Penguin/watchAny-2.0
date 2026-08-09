@echo off
title watchAny Release Publisher
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -File "%~dp0publish_release.ps1" %*
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo =============================================
    echo   RELEASE PUBLISH FAILED!
    echo =============================================
) else (
    echo.
    echo =============================================
    echo   RELEASE PUBLISHED SUCCESSFULLY!
    echo =============================================
)
pause
