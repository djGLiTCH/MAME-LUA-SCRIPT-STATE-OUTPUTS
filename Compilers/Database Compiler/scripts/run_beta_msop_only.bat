@echo off
REM MSOP Database Compiler - BETA, MSOP-ONLY launcher (Windows). Builds the beta channel WITHOUT the
REM MAME driver's native outputs:
REM   1. database compiler   (input\beta\database\games  ->  output\beta\stateoutput\database.lua/json)
REM   2. drops database_driver.lua from the plugin folder (does NOT run the driver compiler)
REM   3. HOTR defaultLG        (beta database  ->  output\beta\defaultLG)         [never uses the driver]
REM   4. MAMEhooker .ini       (beta database  ->  output\beta\ini, --no-driver)  [MSOP outputs only]
REM The result reflects the plugin's own MSOP state outputs plus each game's curated
REM ADDITIONAL_OUTPUT_FORWARDS - but NOT the scraped MAME native outputs. Use run_beta.* (with MAME_SRC
REM set) instead when you DO want the MAME driver outputs.

echo === [BETA / MSOP-only] Database Compiler ===
python "%~dp0msop_database_compiler.py" beta
if errorlevel 1 goto :error

if exist "%~dp0..\output\beta\stateoutput\database_driver.lua" (
    echo === [BETA / MSOP-only] removing database_driver.lua from the plugin folder ===
    del /q "%~dp0..\output\beta\stateoutput\database_driver.lua"
)

echo.
echo === [BETA / MSOP-only] HOTR defaultLG Generator ^(-^> output\beta\defaultLG^) ===
python "%~dp0msop_hotr_defaultlg_generator.py" --channel beta
if errorlevel 1 goto :error

echo.
echo === [BETA / MSOP-only] MAMEhooker INI Generator ^(MSOP-only default -^> output\beta\ini^) ===
python "%~dp0msop_mamehooker_ini_generator.py" --channel beta
if errorlevel 1 goto :error

echo.
echo Done - output\beta\ is a MSOP-ONLY build (no database_driver.lua, no MAME native outputs).
echo        Re-run run_beta.* with MAME_SRC set to restore the driver + native forwarding.
pause
exit /b 0

:error
echo.
echo A step failed - see the output above.
pause
exit /b 1
