@echo off
REM MSOP MAMEhooker INI Generator - launcher (Windows).
REM Generates empty MAMEhooker .ini skeletons into output\<channel>\ini\. Pass --channel stable|beta
REM (default stable), --report to diff against the shipped references, or --rom <name> for one game.
python "%~dp0msop_mamehooker_ini_generator.py" %*
if errorlevel 1 (
    echo.
    echo The generate failed - see the output above.
    pause
    exit /b 1
)
echo.
echo Done - .ini skeletons generated under output\<channel>\ini\.
pause
exit /b 0
