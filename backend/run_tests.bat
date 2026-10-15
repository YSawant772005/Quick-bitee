@echo off
cd /d C:\Users\Dell\QuickBitee\backend
.venv\Scripts\python -m pytest tests -q --asyncio-mode=auto --no-header -p no:warnings > test_output10.log 2>&1
exit /b %errorlevel%