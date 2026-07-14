@echo off
REM MSOP Database Compiler - STABLE, MSOP-ONLY launcher (Windows). Builds the stable channel WITHOUT
REM the MAME driver's native outputs:
REM   1. database compiler   (input\stable\database\games  ->  output\stable\stateoutput\database.lua/json)
REM   2. drops database_driver.lua from the plugin folder (does NOT run the driver compiler)
REM   3. HOTR defaultLG        (stable database  ->  output\stable\defaultLG)         [never uses the driver]
REM   4. MAMEhooker .ini       (stable database  ->  output\stable\ini, --no-driver)  [MSOP outputs only]
REM The result reflects the plugin's own MSOP state outputs (recoil/reload/ammo/life/damage/credits/
REM lampstart) plus each game's curated ADDITIONAL_OUTPUT_FORWARDS - but NOT the scraped MAME native
REM outputs. Use run_stable.* (with MAME_SRC set) instead when you DO want the MAME driver outputs.

echo === [STABLE / MSOP-only] Database Compiler ===
python "%~dp0msop_database_compiler.py" stable
if errorlevel 1 goto :error

if exist "%~dp0..\output\stable\stateoutput\database_driver.lua" (
    echo === [STABLE / MSOP-only] removing database_driver.lua from the plugin folder ===
    del /q "%~dp0..\output\stable\stateoutput\database_driver.lua"
)

echo.
echo === [STABLE / MSOP-only] HOTR defaultLG Generator ^(-^> output\stable\defaultLG^) ===
python "%~dp0msop_hotr_defaultlg_generator.py" --channel stable
if errorlevel 1 goto :error

echo.
echo === [STABLE / MSOP-only] MAMEhooker INI Generator ^(MSOP-only default -^> output\stable\ini^) ===
python "%~dp0msop_mamehooker_ini_generator.py" --channel stable
if errorlevel 1 goto :error

echo.
echo Done - output\stable\ is a MSOP-ONLY build (no database_driver.lua, no MAME native outputs).
echo        Re-run run_stable.* with MAME_SRC set to restore the driver + native forwarding.
pause
exit /b 0

:error
echo.
echo A step failed - see the output above.
pause
exit /b 1
