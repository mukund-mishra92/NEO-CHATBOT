@echo off
REM Kill any existing processes on port 8000
echo Cleaning up existing processes on port 8000...
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :8000') do (
    taskkill /F /PID %%a 2>nul
)

REM Wait a moment for cleanup
timeout /t 2 /nobreak >nul

REM Start the server
echo Starting NEO Chatbot Server...
cd /d "%~dp0backend"
call ..\venv\Scripts\activate.bat
python -m app.main

pause
