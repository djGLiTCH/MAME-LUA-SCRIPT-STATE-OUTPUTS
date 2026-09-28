@echo off
REM MSOP HOTR defaultLG Generator - launcher (Windows).
REM Generates Hook Of The Reaper defaultLG files into output\<channel>\defaultLG\. Pass --channel
REM stable|beta (default stable), --report to diff against the shipped examples, or --rom <name>.
python "%~dp0msop_hotr_defaultlg_generator.py" %*
if errorlevel 1 (
    echo.
    echo The generate failed - see the output above.
    pause
    exit /b 1
)
echo.
echo Done - defaultLG generated under output\<channel>\defaultLG\.
pause
exit /b 0
