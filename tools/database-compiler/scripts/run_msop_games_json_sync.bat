@echo off
REM MSOP games.json Sync - launcher (Windows).
REM Aligns the "Channels" of updates\msop-games.json with a channel's game database. Pass --channel
REM stable|beta (default stable), --check to report without writing, or --backfill (one-off seeding).
REM The full launchers (run_stable.bat / run_beta.bat / run.bat) already run this as their last step.
python "%~dp0msop_games_json_sync.py" %*
if errorlevel 1 (
    echo.
    echo The sync failed or found problems - see the output above.
    pause
    exit /b 1
)
echo.
echo Done - games.json checked against the channel database.
pause
exit /b 0
