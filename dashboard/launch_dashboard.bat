@echo off
cd /d "%~dp0\.."
if exist ".venv\Scripts\python.exe" (
  ".venv\Scripts\python.exe" dashboard\main.py
) else (
  python dashboard\main.py
)
if errorlevel 1 pause
