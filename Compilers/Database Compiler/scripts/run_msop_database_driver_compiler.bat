@echo off
REM MSOP Database Driver Compiler - launcher (Windows).
REM Runs ONLY the driver compiler: it scrapes a MAME source checkout for each supported ROM's NATIVE
REM output names and writes output\<channel>\stateoutput\database_driver.lua (plus the scrape-report
REM JSON under output\<channel>\results\). It does NOT compile database.lua and does NOT regenerate
REM the HOTR defaultLG templates or the MAMEhooker INIs - use run_stable.*/run_beta.*/run.* for those.
REM
REM MAME source: pass --mame-src "<path>" (the folder containing src\mame), or leave it off and the
REM script falls back to the MAME_SRC_PATH constant near the top of msop_database_driver_compiler.py -
REM set that once and you can just double-click this file.
REM
REM Useful arguments (all passed straight through):
REM   --channel stable^|beta   which tree to read/write (default: stable)
REM   --rom ^<name^>            scrape a single ROM instead of every supported one (repeatable)
REM   --no-scrape-report      skip the audit JSON (database_driver.lua is always written)

python "%~dp0msop_database_driver_compiler.py" %*
if errorlevel 1 (
    echo.
    echo The driver compile failed - see the output above.
    pause
    exit /b 1
)
echo.
echo Done - database_driver.lua written under output\^<channel^>\stateoutput\.
pause
exit /b 0
