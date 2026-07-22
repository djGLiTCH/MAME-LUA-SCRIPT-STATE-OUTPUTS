@echo off
REM MSOP Database Compiler - BETA channel launcher (Windows). Runs the full BETA pipeline:
REM   1. database compiler   (input\beta\database\games  ->  output\beta\stateoutput\database.lua/json)
REM   2. driver compiler      (MAME source                ->  output\beta\stateoutput\native_outputs_by_rom.lua) [optional]
REM   3. HOTR defaultLG        (beta database              ->  output\beta\defaultLG)
REM   4. MAMEhooker .ini       (beta database              ->  output\beta\ini)
REM BETA is intentionally isolated from STABLE (its own input\beta\ tree), so experimental games AND
REM plugin code can't touch the shipped stable build. See run.bat for both channels, run_stable.bat for stable.
REM Set MAME_SRC to your MAME source checkout (contains src\mame) to enable the driver step; EMPTY skips it.
REM (The driver step matters for beta whenever beta adds new ROMs.)
set "MAME_SRC="

echo === [BETA] Database Compiler ===
python "%~dp0msop_database_compiler.py" beta
if errorlevel 1 goto :error

echo.
if "%MAME_SRC%"=="" (
    echo === [BETA] Driver Compiler SKIPPED - MAME_SRC not set in this launcher ===
) else (
    echo === [BETA] Driver Compiler ^(MAME source -^> native_outputs_by_rom.lua^) ===
    python "%~dp0msop_native_outputs_compiler.py" --channel beta --mame-src "%MAME_SRC%"
    if errorlevel 1 goto :error
)

echo.
echo === [BETA] HOTR defaultLG Generator ^(-^> output\beta\defaultLG^) ===
python "%~dp0msop_hotr_defaultlg_generator.py" --channel beta
if errorlevel 1 goto :error

echo.
echo === [BETA] MAMEhooker INI Generator ^(--include-driver -^> output\beta\ini^) ===
python "%~dp0msop_mamehooker_ini_generator.py" --channel beta --include-driver
if errorlevel 1 goto :error

echo.
echo Done - output\beta\ is tagged BETA and ready to ship.
pause
exit /b 0

:error
echo.
echo A step failed - see the output above.
pause
exit /b 1
