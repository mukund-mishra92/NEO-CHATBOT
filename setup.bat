@echo off
REM NEO Chatbot - Setup Script for Windows

echo ========================================
echo NEO Chatbot - Initial Setup
echo ========================================
echo.

REM Check Python installation
py --version >nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python is not installed or not in PATH
    echo Please install Python 3.9 or higher from python.org
    pause
    exit /b 1
)

echo [1/5] Python found!
py --version
echo.

REM Create virtual environment
echo [2/5] Creating virtual environment...
if exist "NEO\" (
    echo Virtual environment already exists, skipping...
) else (
    py -m NEO backend\NEO
    echo Virtual environment created successfully!
)
echo.

REM Activate virtual environment
echo [3/5] Activating virtual environment...
call NEO\Scripts\activate.bat

REM Upgrade pip
echo [4/5] Upgrading pip...
py -m pip install --upgrade pip
echo.

REM Install dependencies
echo [5/5] Installing dependencies...
echo This may take a few minutes...
pip install -r backend\requirements.txt
echo.

REM Create .env from example if it doesn't exist
if not exist "backend\.env" (
    echo Creating .env file from template...
    copy backend\.env.example backend\.env
    echo.
    echo [IMPORTANT] Please edit backend\.env and add your API keys!
) else (
    echo .env file already exists
)

echo.
echo ========================================
echo Setup Complete!
echo ========================================
echo.
echo Next steps:
echo 1. Edit backend\.env and add your API keys
echo 2. Place your documents in data\documents\
echo 3. Run: python scripts\ingest_documents.py
echo 4. Run: start.bat to start the server
echo.
pause
