@echo off
REM NEO Chatbot - Quick Start Script for Windows
REM This script sets up and runs the NEO Chatbot

echo ========================================
echo NEO Chatbot - Starting Server
echo ========================================
echo.

REM Check if virtual environment exists (one level up)
if not exist "..\venv\" (
    echo [WARNING] Virtual environment not found!
    echo Please run setup.bat first to create the virtual environment
    pause
    exit /b 1
)

REM Activate virtual environment
echo [1/3] Activating virtual environment...
call ..\venv\Scripts\activate.bat

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
echo   - Local: http://localhost:3960
echo   - Network: http://192.168.16.20:3960
echo   - API Docs: http://localhost:3960/docs
echo   - Chatbot UI: http://localhost:3960/chatbot
echo.
echo [3/3] Press Ctrl+C to stop the server
echo ========================================
echo.

uvicorn app.main:app --reload --port 3960 --host 0.0.0.0

pause
