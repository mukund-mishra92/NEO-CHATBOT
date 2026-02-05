@echo off
REM NEO Chatbot - Quick Start Script for Windows
REM This script sets up and runs the NEO Chatbot

echo ========================================
echo NEO Chatbot - Starting Server
echo ========================================
echo.

REM Check if virtual environment exists
if not exist "backend\NEO\" (
    echo [WARNING] Virtual environment not found!
    echo Please run setup.bat first to create the virtual environment
    pause
    exit /b 1
)

REM Activate virtual environment
echo [1/3] Activating virtual environment...
call backend\NEO\Scripts\activate.bat

REM Check if .env file exists
if not exist "backend\.env" (
    echo [WARNING] .env file not found!
    echo Please copy backend\.env.example to backend\.env and configure it
    pause
    exit /b 1
)

REM Change to backend directory
cd backend

REM Start the server
echo [2/3] Starting NEO Chatbot server...
echo.
echo Server will be available at:
echo   - API: http://localhost:8000
echo   - Docs: http://localhost:8000/docs
echo   - Chatbot UI: http://localhost:8000/chatbot
echo.
echo [3/3] Press Ctrl+C to stop the server
echo ========================================
echo.

python -m app.main --reload --port 3960 --host 127.0.0.1

pause
