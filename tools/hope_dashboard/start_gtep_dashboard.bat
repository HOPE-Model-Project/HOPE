@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\.."
cd /d "%REPO_ROOT%"

set "PYTHON_EXE=C:\Users\wangs\AppData\Local\Programs\Python\Python312\python.exe"
if not exist "%PYTHON_EXE%" set "PYTHON_EXE=python"
if not defined HOPE_DASHBOARD_PORT set "HOPE_DASHBOARD_PORT=8051"

start "HOPE GTEP Dashboard" "%PYTHON_EXE%" "%SCRIPT_DIR%run_gtep_dashboard.py"
timeout /t 3 /nobreak >nul
start "" "http://127.0.0.1:%HOPE_DASHBOARD_PORT%"

endlocal
