@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "REPO_ROOT=%SCRIPT_DIR%..\.."
cd /d "%REPO_ROOT%"

set "PYTHON_EXE=C:\Users\wangs\AppData\Local\Programs\Python\Python312\python.exe"
if not exist "%PYTHON_EXE%" set "PYTHON_EXE=python"

start "HOPE Dashboard" "%PYTHON_EXE%" "%SCRIPT_DIR%run_dashboard.py"
timeout /t 3 /nobreak >nul
start "" "http://127.0.0.1:8050"

endlocal
