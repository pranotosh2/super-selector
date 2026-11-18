@echo off
title Push SupeRR Selector to GitHub
cd /d "D:\Data Pack"

echo ===================================================
echo Pushing repository to GitHub (pranotosh2/super-selector)
echo ===================================================
echo.
echo If a GitHub sign-in window appears in your browser,
echo please click 'Authorize' or 'Sign in'.
echo.

"C:\Program Files\Git\cmd\git.exe" push -u origin main
if errorlevel 1 (
    echo.
    echo [ERROR] Push failed. If prompted for password, use a Personal Access Token (PAT).
    pause
    exit /b %errorlevel%
)

echo.
echo Pushing gh-pages branch (for Live GitHub Pages)...
"C:\Program Files\Git\cmd\git.exe" push -u origin gh-pages

echo.
echo ===================================================
echo SUCCESS! All code and reports pushed to GitHub!
echo   Repository:   https://github.com/pranotosh2/super-selector
echo   Live Report:  https://pranotosh2.github.io/super-selector/
echo ===================================================
pause
