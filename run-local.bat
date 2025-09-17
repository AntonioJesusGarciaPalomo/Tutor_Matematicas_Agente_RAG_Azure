@echo off
REM ================================================
REM Math Tutor - Local Development Runner for Windows
REM ================================================

echo =========================================
echo  MATH TUTOR - Starting Local Development
echo =========================================
echo.

REM Check if .env exists
if not exist ".env" (
    echo ERROR: .env file not found!
    echo Please run deploy-local-dev.ps1 first or create .env from .env.template
    pause
    exit /b 1
)

REM Check if virtual environments exist
if not exist "backend\.venv" (
    echo ERROR: Backend virtual environment not found!
    echo Please run: python setup-and-verify.py
    pause
    exit /b 1
)

if not exist "frontend\.venv" (
    echo ERROR: Frontend virtual environment not found!
    echo Please run: python setup-and-verify.py
    pause
    exit /b 1
)

echo Starting services...
echo.

REM Start backend in a new window
echo [1/2] Starting Backend on http://localhost:8000
start "Math Tutor Backend" cmd /k "cd backend && .venv\Scripts\activate && set ENVIRONMENT=local && set DEBUG=true && python main.py"

REM Wait for backend to start
echo Waiting for backend to initialize...
timeout /t 5 /nobreak > nul

REM Check if backend is responding
curl -s http://localhost:8000/health > nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: Backend may not be ready yet. Continuing anyway...
)

REM Start frontend in a new window
echo [2/2] Starting Frontend on http://localhost:7860
start "Math Tutor Frontend" cmd /k "cd frontend && .venv\Scripts\activate && set BACKEND_URI=http://localhost:8000 && python app.py"

echo.
echo =========================================
echo  Services Started Successfully!
echo =========================================
echo.
echo  Backend:  http://localhost:8000
echo  Frontend: http://localhost:7860
echo  API Docs: http://localhost:8000/docs
echo  Health:   http://localhost:8000/health
echo.
echo  Press any key to open the frontend in your browser...
pause > nul

REM Open browser
start http://localhost:7860

echo.
echo  To stop the services:
echo  - Close the Backend and Frontend windows
echo  - Or press Ctrl+C in each window
echo.
echo  This window can be closed now.
pause
