@echo off
echo Installing requirements...
pip install -r requirements.txt
playwright install chromium

echo Running automation...
python auto_upload.py
pause
