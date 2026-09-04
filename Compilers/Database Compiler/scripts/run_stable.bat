@echo off
REM MSOP Database Compiler - STABLE channel launcher (Windows). Runs the full STABLE pipeline:
REM   1. database compiler   (input\stable\database\games  ->  output\stable\stateoutput\database.lua/json)
REM   2. driver compiler      (MAME source                  ->  output\stable\stateoutput\native_outputs_by_rom.lua) [optional]
REM   3. HOTR defaultLG        (stable database              ->  output\stable\defaultLG)
REM   4. MAMEhooker .ini       (stable database              ->  output\stable\ini)
REM See run.bat to build BOTH channels at once, run_beta.bat for beta.
REM Set MAME_SRC to your MAME source checkout (contains src\mame) to enable the driver step; EMPTY skips it.
set "MAME_SRC="

echo === [STABLE] Database Compiler ===
python "%~dp0msop_database_compiler.py" stable
if errorlevel 1 goto :error

echo.
if "%MAME_SRC%"=="" (
    echo === [STABLE] Driver Compiler SKIPPED - MAME_SRC not set in this launcher ===
) else (
    echo === [STABLE] Driver Compiler ^(MAME source -^> native_outputs_by_rom.lua^) ===
    python "%~dp0msop_native_outputs_compiler.py" --channel stable --mame-src "%MAME_SRC%"
    if errorlevel 1 goto :error
)

echo.
echo === [STABLE] HOTR defaultLG Generator ^(-^> output\stable\defaultLG^) ===
python "%~dp0msop_hotr_defaultlg_generator.py" --channel stable
if errorlevel 1 goto :error

echo.
echo === [STABLE] MAMEhooker INI Generator ^(driver natives by default -^> output\stable\ini^) ===
python "%~dp0msop_mamehooker_ini_generator.py" --channel stable
if errorlevel 1 goto :error

echo.
echo Done - output\stable\ is tagged STABLE and ready to ship.
pause
exit /b 0

:error
echo.
echo A step failed - see the output above.
pause
exit /b 1
