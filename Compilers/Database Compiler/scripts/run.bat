@echo off
setlocal
REM MSOP Database Compiler - unified launcher (Windows): builds BOTH release channels end to end.
REM For EACH channel (stable, then beta) it runs, in order:
REM   1. database compiler   (input\<ch>\database\games  ->  output\<ch>\stateoutput\database.lua/json)
REM   2. driver compiler      (MAME source                ->  output\<ch>\stateoutput\native_outputs_by_rom.lua) [optional]
REM   3. HOTR defaultLG        (<ch> database              ->  output\<ch>\defaultLG)
REM   4. MAMEhooker .ini       (<ch> database              ->  output\<ch>\ini)
REM Single-channel launchers: run_stable.bat / run_beta.bat. %~dp0 = this scripts\ folder.
REM
REM Set MAME_SRC below to your MAME source checkout (the folder that contains src\mame) to enable the
REM driver step for BOTH channels; leave it EMPTY to skip it.
set "MAME_SRC="
set "SCRIPTS=%~dp0"

call :run_channel stable
if errorlevel 1 goto :error
call :run_channel beta
if errorlevel 1 goto :error

echo.
echo Done - both channels built (output\stable\ + output\beta\).
pause
exit /b 0

:run_channel
if not exist "%SCRIPTS%..\input\%~1\database\games" (
    echo ==================== [%~1] SKIPPED - input\%~1\ not present ====================
    echo.
    exit /b 0
)
echo ==================== [%~1] ====================
echo === [%~1] Database Compiler ===
python "%SCRIPTS%msop_database_compiler.py" %~1
if errorlevel 1 exit /b 1
echo.
if "%MAME_SRC%"=="" (
    echo === [%~1] Driver Compiler SKIPPED - MAME_SRC not set in this launcher ===
) else (
    echo === [%~1] Driver Compiler ^(MAME source -^> native_outputs_by_rom.lua^) ===
    python "%SCRIPTS%msop_native_outputs_compiler.py" --channel %~1 --mame-src "%MAME_SRC%"
    if errorlevel 1 exit /b 1
)
echo.
echo === [%~1] HOTR defaultLG Generator ^(-^> output\%~1\defaultLG^) ===
python "%SCRIPTS%msop_hotr_defaultlg_generator.py" --channel %~1
if errorlevel 1 exit /b 1
echo.
echo === [%~1] MAMEhooker INI Generator ^(--include-driver -^> output\%~1\ini^) ===
python "%SCRIPTS%msop_mamehooker_ini_generator.py" --channel %~1 --include-driver
if errorlevel 1 exit /b 1
echo.
exit /b 0

:error
echo.
echo A step failed - see the output above.
pause
exit /b 1
