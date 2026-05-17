@echo off
setlocal
cd /d "%~dp0.."
where python >nul 2>nul
if errorlevel 1 (
  echo Python was not found on PATH.
  echo Try: C:\ProgramData\Anaconda3\python.exe tools\esp_cam_debug_server.py --port 8765
  pause
  exit /b 1
)
echo Starting ESP32-CAM debug server on http://127.0.0.1:8765
echo Press Ctrl+C in this window to stop it.
python tools\esp_cam_debug_server.py --port 8765
