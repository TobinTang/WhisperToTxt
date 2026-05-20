@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion

set "BASE=%~dp0"
if "%BASE:~-1%"=="\" set "BASE=%BASE:~0,-1%"

set "SCRIPT=%~f0"
set "WHISPER=%BASE%\whisper-cli.exe"
set "FFMPEG=%BASE%\ffmpeg.exe"
set "FFPROBE=%BASE%\ffprobe.exe"
set "REFRESH_SEC=15"

rem Color notes:
rem Some CMD windows do not render ANSI escape codes correctly and print 96m/0m as text.
rem Keep inline color variables empty, and use PowerShell Write-Host only for directory headings.
set "C_RESET="
set "C_TITLE="
set "C_OK="
set "C_WARN="
set "C_ERR="
set "C_INFO="
set "C_DIM="

set "ARG1=%~1"

if /I "%ARG1%"=="__one__" goto ONE_FILE
if /I "%ARG1%"=="__duration_one__" goto DURATION_ONE_FILE

:: top-level args:
::   arg1 = input file/folder
::   arg2 = output folder, optional; it may not exist yet
::   if arg2 is small / large / duration / notime / clean, it is treated as an option
::   following args = small / large / duration / notime / clean
set "TARGET=%~1"
set "MODE=TRANSCRIBE"
set "MODEL_ARG="
set "NOTIME=0"
set "NOTIME_ARG="
set "CLEAN=0"
set "CLEAN_ARG="
set "OUTDIR=%BASE%\output"

if "%TARGET%"=="" goto USAGE

set "ARG2=%~2"
if "%ARG2%"=="" goto PARSE_ARGS_DONE

call :IS_TOP_OPTION "%ARG2%"
if errorlevel 1 (
    set "OUTDIR=%ARG2%"
    for %%A in ("%~3" "%~4" "%~5" "%~6" "%~7" "%~8" "%~9") do call :PARSE_TOP_ARG "%%~A"
) else (
    for %%A in ("%~2" "%~3" "%~4" "%~5" "%~6" "%~7" "%~8" "%~9") do call :PARSE_TOP_ARG "%%~A"
)

:PARSE_ARGS_DONE

if "%NOTIME%"=="1" set "NOTIME_ARG=notime"
if "%CLEAN%"=="1" set "CLEAN_ARG=clean"

if /I "%MODEL_ARG%"=="small" (
    set "MODEL=%BASE%\models\ggml-small-q8_0.bin"
) else (
    set "MODEL=%BASE%\models\ggml-large-v3-turbo.bin"
)

echo %C_TITLE%========================================%C_RESET%
echo %C_INFO%Target:%C_RESET% "%TARGET%"
echo %C_INFO%Mode  :%C_RESET% %MODE%
if /I not "%MODE%"=="DURATION" echo %C_INFO%Model :%C_RESET% %MODEL%
if /I not "%MODE%"=="DURATION" echo %C_INFO%OutDir:%C_RESET% "%OUTDIR%"
echo %C_TITLE%========================================%C_RESET%

if not exist "%FFPROBE%" (
    echo %C_ERR%ffprobe.exe not found:%C_RESET%
    echo %FFPROBE%
    exit /b 1
)

if /I "%MODE%"=="DURATION" goto AFTER_TRANSCRIBE_CHECKS

if not exist "%WHISPER%" (
    echo %C_ERR%whisper-cli.exe not found:%C_RESET%
    echo %WHISPER%
    exit /b 1
)
if not exist "%MODEL%" (
    echo %C_ERR%model not found:%C_RESET%
    echo %MODEL%
    exit /b 1
)
if not exist "%FFMPEG%" (
    echo %C_ERR%ffmpeg.exe not found:%C_RESET%
    echo %FFMPEG%
    exit /b 1
)
if not exist "%BASE%\temp" mkdir "%BASE%\temp"
if not exist "%OUTDIR%" mkdir "%OUTDIR%"

:AFTER_TRANSCRIBE_CHECKS

if not exist "%TARGET%" goto PATH_NOT_FOUND
if exist "%TARGET%\*" goto TARGET_IS_FOLDER
goto TARGET_IS_FILE

:TARGET_IS_FILE
if /I "%MODE%"=="DURATION" goto RUN_DURATION_SINGLE
goto RUN_TRANSCRIBE_SINGLE

:RUN_DURATION_SINGLE
call "%SCRIPT%" __duration_one__ "%TARGET%" 1 1
exit /b %errorlevel%

:RUN_TRANSCRIBE_SINGLE
call "%SCRIPT%" __one__ "%TARGET%" 1 1 "%OUTDIR%" "%MODEL_ARG%" "%NOTIME_ARG%" "%CLEAN_ARG%"
echo.
echo %C_OK%All files done.%C_RESET%
exit /b %errorlevel%

:TARGET_IS_FOLDER
if /I "%MODE%"=="DURATION" goto RUN_DURATION_FOLDER
goto RUN_TRANSCRIBE_FOLDER

:PATH_NOT_FOUND
echo %C_ERR%Path not found.%C_RESET%
exit /b 1

:PARSE_TOP_ARG
set "A=%~1"
if "%A%"=="" exit /b 0
if /I "%A%"=="duration" set "MODE=DURATION"
if /I "%A%"=="small" set "MODEL_ARG=small"
if /I "%A%"=="large" set "MODEL_ARG=large"
if /I "%A%"=="notime" set "NOTIME=1"
if /I "%A%"=="clean" set "CLEAN=1"
if /I "%A:~0,4%"=="out=" set "OUTDIR=%A:~4%"
exit /b 0

:IS_TOP_OPTION
set "OPT=%~1"
if "%OPT%"=="" exit /b 1
if /I "%OPT%"=="duration" exit /b 0
if /I "%OPT%"=="small" exit /b 0
if /I "%OPT%"=="large" exit /b 0
if /I "%OPT%"=="notime" exit /b 0
if /I "%OPT%"=="clean" exit /b 0
exit /b 1

:RUN_DURATION_FOLDER
setlocal EnableDelayedExpansion
set "COUNT=0"
for /r "%TARGET%" %%F in (*.mp4) do set /a COUNT+=1
if "!COUNT!"=="0" (
    echo %C_WARN%No MP4 files found.%C_RESET%
    endlocal & exit /b 0
)
set "IDX=0"
set "TOTAL_SEC=0"
set "LASTDIR="
for /r "%TARGET%" %%F in (*.mp4) do call :DURATION_FOLDER_ITEM "%%~fF"
set /a TH=!TOTAL_SEC!/3600
set /a TM=(!TOTAL_SEC! %% 3600)/60
set /a TS=!TOTAL_SEC! %% 60
if !TH! LSS 10 set "TH=0!TH!"
if !TM! LSS 10 set "TM=0!TM!"
if !TS! LSS 10 set "TS=0!TS!"
echo.
echo %C_OK%Total duration:%C_RESET% !TH!:!TM!:!TS!
endlocal & exit /b 0

:DURATION_FOLDER_ITEM
set "FILE=%~1"
set /a IDX+=1
for %%D in ("%FILE%") do set "THISDIR=%%~dpD" & set "CURRNAME=%%~nxD"
if /I not "!THISDIR!"=="!LASTDIR!" (
    echo.
    for %%D in ("!THISDIR!." ) do call :PRINT_BLUE "%%~nxD"
    set "LASTDIR=!THISDIR!"
)
set "DURATION="
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$p = $env:FILE; $fp = $env:FFPROBE; & $fp -v error -show_entries 'format=duration' -of 'default=noprint_wrappers=1:nokey=1' -- $p"`) do set "DURATION=%%A"
if not defined DURATION (
    echo   %C_ERR%[!IDX!/!COUNT!] !CURRNAME!   Failed%C_RESET%
    exit /b 0
)
for /f "delims=." %%A in ("!DURATION!") do set "SEC=%%A"
if not defined SEC set "SEC=0"
set /a TOTAL_SEC+=SEC
set /a FH=SEC/3600
set /a FM=(SEC %% 3600)/60
set /a FS=SEC %% 60
if !FH! LSS 10 set "FH=0!FH!"
if !FM! LSS 10 set "FM=0!FM!"
if !FS! LSS 10 set "FS=0!FS!"
echo   %C_INFO%[!IDX!/!COUNT!]%C_RESET% !CURRNAME!   %C_OK%!FH!:!FM!:!FS!%C_RESET%
exit /b 0

:RUN_TRANSCRIBE_FOLDER
setlocal EnableDelayedExpansion
set "ROOT=%TARGET%"
if "!ROOT:~-1!"=="\" set "ROOT=!ROOT:~0,-1!"
set "COUNT=0"
for /r "%TARGET%" %%F in (*.mp4) do set /a COUNT+=1
if "!COUNT!"=="0" (
    echo %C_WARN%No MP4 files found.%C_RESET%
    endlocal & exit /b 0
)
set "IDX=0"
set "LASTDIR="
for /r "%TARGET%" %%F in (*.mp4) do call :TRANSCRIBE_FOLDER_ITEM "%%~fF"
set "RC=!errorlevel!"
echo.
echo %C_OK%All files done.%C_RESET%
endlocal & exit /b %RC%

:TRANSCRIBE_FOLDER_ITEM
set "FILE=%~1"
set /a IDX+=1
for %%D in ("%FILE%") do set "THISDIR=%%~dpD" & set "CURRNAME=%%~nxD"
if /I not "!THISDIR!"=="!LASTDIR!" (
    echo.
    for %%D in ("!THISDIR!." ) do call :PRINT_BLUE "%%~nxD"
    set "LASTDIR=!THISDIR!"
)
set "RELDIR=!THISDIR:%ROOT%\=!"
if "!RELDIR!"=="!THISDIR!" set "RELDIR="
if "!RELDIR:~-1!"=="\" set "RELDIR=!RELDIR:~0,-1!"
if "!RELDIR!"=="" (
    set "FILE_OUTDIR=%OUTDIR%"
) else (
    set "FILE_OUTDIR=%OUTDIR%\!RELDIR!"
)
call "%SCRIPT%" __one__ "%FILE%" !IDX! !COUNT! "!FILE_OUTDIR!" "%MODEL_ARG%" "%NOTIME_ARG%" "%CLEAN_ARG%"
exit /b !errorlevel!

:ONE_FILE
setlocal EnableDelayedExpansion
set "INPUT=%~2"
set "IDX=%~3"
set "TOT=%~4"
set "OUTDIR=%~5"
set "MODEL_ARG="
set "NOTIME=0"
set "CLEAN=0"

if "!OUTDIR!"=="" set "OUTDIR=%BASE%\output"
if /I "!OUTDIR!"=="small" set "OUTDIR=%BASE%\output"
if /I "!OUTDIR!"=="large" set "OUTDIR=%BASE%\output"
if /I "!OUTDIR!"=="notime" set "OUTDIR=%BASE%\output"
if /I "!OUTDIR!"=="clean" set "OUTDIR=%BASE%\output"

for %%A in ("%~5" "%~6" "%~7" "%~8" "%~9") do (
    if /I "%%~A"=="small" set "MODEL_ARG=small"
    if /I "%%~A"=="large" set "MODEL_ARG=large"
    if /I "%%~A"=="notime" set "NOTIME=1"
    if /I "%%~A"=="clean" set "CLEAN=1"
)

if /I "!MODEL_ARG!"=="small" (
    set "MODEL=%BASE%\models\ggml-small-q8_0.bin"
) else (
    set "MODEL=%BASE%\models\ggml-large-v3-turbo.bin"
)

set "NAME=%~n2"
set "CURRNAME=%~nx2"
set "WAV=%BASE%\temp\%NAME%.wav"
set "TIMEDTXT=!OUTDIR!\%NAME%_timed.txt"
set "PLAINTXT=!OUTDIR!\%NAME%.txt"
if not exist "!OUTDIR!" mkdir "!OUTDIR!"

echo   %C_INFO%[!IDX!/!TOT!]%C_RESET% !CURRNAME!

if exist "!TIMEDTXT!" (
    for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format 'HHmmss'"`) do set "TS=%%T"
    set "TIMEDTXT=!OUTDIR!\%NAME%_timed_!TS!.txt"
    set "PLAINTXT=!OUTDIR!\%NAME%_!TS!.txt"
)

set "DURATION="
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$p = $env:INPUT; $fp = $env:FFPROBE; & $fp -v error -show_entries 'format=duration' -of 'default=noprint_wrappers=1:nokey=1' -- $p"`) do (
    set "DURATION=%%A"
)
if not defined DURATION (
    echo   %C_ERR%Duration parse failed:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)
for /f "delims=." %%A in ("!DURATION!") do set "DURATION_INT=%%A"
if not defined DURATION_INT (
    echo   %C_ERR%Duration parse failed:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)
set /a HH=!DURATION_INT!/3600
set /a MM=(!DURATION_INT! %% 3600)/60
set /a SS=!DURATION_INT! %% 60
if !HH! LSS 10 set "HH=0!HH!"
if !MM! LSS 10 set "MM=0!MM!"
if !SS! LSS 10 set "SS=0!SS!"
set "TOTAL_TIME=!HH!:!MM!:!SS!"

"%FFMPEG%" -i "%INPUT%" -ar 16000 -ac 1 -c:a pcm_s16le "!WAV!" -y >nul 2>&1
if errorlevel 1 (
    echo   %C_ERR%ffmpeg failed:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)

del /q "!TIMEDTXT!" 2>nul

"%WHISPER%" -m "!MODEL!" -f "!WAV!" -l zh -t 12 2>&1 ^
| powershell -NoProfile -Command ^
  "$timed = $env:TIMEDTXT;" ^
  "$totalText = $env:TOTAL_TIME;" ^
  "$refreshSec = [int]$env:REFRESH_SEC;" ^
  "$enc = [System.Text.UTF8Encoding]::new($true);" ^
  "$sw = [System.IO.StreamWriter]::new($timed, $false, $enc);" ^
  "$lastShown = -1;" ^
  "try {" ^
  "  foreach($line in $input) {" ^
  "    if ($line -match '^\[([0-9]{2}):([0-9]{2}):([0-9]{2})\.[0-9]{3}\s+-->\s+[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}\]\s*(.+)$') {" ^
  "      $h = [int]$matches[1]; $m = [int]$matches[2]; $s = [int]$matches[3];" ^
  "      $body = $matches[4];" ^
  "      if ($body.Trim().Length -gt 0) { $sw.WriteLine($line) };" ^
  "      $curSec = $h * 3600 + $m * 60 + $s;" ^
  "      if ($refreshSec -lt 1) { $refreshSec = 1 };" ^
  "      if ($lastShown -lt 0 -or ($curSec - $lastShown) -ge $refreshSec) {" ^
  "        $lastShown = $curSec;" ^
  "        $curText = ('{0:D2}:{1:D2}:{2:D2}' -f $h, $m, $s);" ^
  "        $n=$env:CURRNAME; if($n.Length -gt 40){$n=$n.Substring(0,40)+'...'}; [Console]::Write(\"`r  \" + $n + ' | ' + $curText + ' / ' + $totalText + '      ');" ^
  "      };" ^
  "    };" ^
  "  }" ^
  "} finally {" ^
  "  $sw.Close();" ^
  "  Write-Host '';" ^
  "}"
if errorlevel 1 (
    echo   %C_ERR%whisper failed:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)
if not exist "!TIMEDTXT!" (
    echo   %C_ERR%timed txt not generated:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)

powershell -NoProfile -Command ^
  "$in = $env:TIMEDTXT; $out = $env:PLAINTXT;" ^
  "Get-Content -LiteralPath $in | Where-Object { $_ -match '^[[]' } | ForEach-Object { $_ -replace '^[[][^]]+[]]\s*','' } | Set-Content -LiteralPath $out -Encoding UTF8"
if errorlevel 1 (
    echo   %C_ERR%plain txt generation failed:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)
if not exist "!PLAINTXT!" type nul > "!PLAINTXT!"
if not exist "!PLAINTXT!" (
    echo   %C_ERR%plain txt not generated:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)

if "!CLEAN!"=="1" (
    call :ENHANCE_CLEAN_PRO "!PLAINTXT!"
) else (
    call :ENHANCE_CLEAN_TXT "!PLAINTXT!"
)
if errorlevel 1 (
    echo   %C_ERR%enhance clean failed:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)


if "!NOTIME!"=="1" (
    for %%F in ("!OUTDIR!\%NAME%_timed*.txt") do (
        del /f /q "%%~F" >nul 2>&1
    )
)

if exist "!WAV!" del "!WAV!"
echo   %C_OK%Finished:%C_RESET% !CURRNAME!
echo   %C_INFO%Output files:%C_RESET%
if exist "!TIMEDTXT!" echo     !TIMEDTXT!
echo     !PLAINTXT!
endlocal & exit /b 0

:ENHANCE_CLEAN_TXT
setlocal DisableDelayedExpansion
set "CLEAN_FILE=%~1"
if "%CLEAN_FILE%"=="" (
    endlocal & exit /b 1
)

powershell -NoProfile -Command ^
  "$p = $env:CLEAN_FILE;" ^
  "$lines = Get-Content -LiteralPath $p -Encoding UTF8;" ^
  "$out = New-Object System.Collections.Generic.List[string];" ^
  "$prev = '';" ^
  "foreach($raw in $lines) {" ^
  "  $line = [string]$raw;" ^
  "  $line = $line -replace '\uFEFF','';" ^
  "  $line = $line -replace '\s+',' ';" ^
  "  $line = $line.Trim();" ^
  "  if([string]::IsNullOrWhiteSpace($line)) { continue }" ^
  "  if($line -eq $prev) { continue }" ^
  "  $out.Add($line);" ^
  "  $prev = $line;" ^
  "}" ^
  "[System.IO.File]::WriteAllLines($p, $out, [System.Text.UTF8Encoding]::new($true))"
set "RC=%errorlevel%"
endlocal & exit /b %RC%

:ENHANCE_CLEAN_PRO
setlocal DisableDelayedExpansion
set "CLEAN_FILE=%~1"
if "%CLEAN_FILE%"=="" (
    endlocal & exit /b 1
)

powershell -NoProfile -Command ^
  "$p = $env:CLEAN_FILE;" ^
  "$lines = Get-Content -LiteralPath $p -Encoding UTF8;" ^
  "$out = New-Object System.Collections.Generic.List[string];" ^
  "$prev = '';" ^
  "foreach($raw in $lines) {" ^
  "  $line = [string]$raw;" ^
  "  $line = $line -replace '\uFEFF','';" ^
  "  $line = $line -replace '\s+',' ';" ^
  "  $line = $line.Trim();" ^
  "  if([string]::IsNullOrWhiteSpace($line)) { continue }" ^
  "  $line = $line -replace '^(啊|嗯|呃|额)[，,。\s]*','';" ^
  "  $line = $line -replace '[\s，,。]*(啊|嗯|呃|额)$','';" ^
  "  if([string]::IsNullOrWhiteSpace($line)) { continue }" ^
  "  if($line -eq $prev) { continue }" ^
  "  if($line -notmatch '[。！？!?]$') { $line += '。' }" ^
  "  $out.Add($line);" ^
  "  $prev = $line;" ^
  "}" ^
  "[System.IO.File]::WriteAllLines($p, $out, [System.Text.UTF8Encoding]::new($true))"
set "RC=%errorlevel%"
endlocal & exit /b %RC%

:DURATION_ONE_FILE
setlocal EnableDelayedExpansion
set "INPUT=%~2"
set "IDX=%~3"
set "TOT=%~4"
set "CURRNAME=%~nx2"
echo   %C_INFO%[!IDX!/!TOT!]%C_RESET% !CURRNAME!
set "DURATION="
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$p = $env:INPUT; $fp = $env:FFPROBE; & $fp -v error -show_entries 'format=duration' -of 'default=noprint_wrappers=1:nokey=1' -- $p"`) do (
    set "DURATION=%%A"
)
if not defined DURATION (
    echo   %C_ERR%Duration parse failed:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)
for /f "delims=." %%A in ("!DURATION!") do set "DURATION_INT=%%A"
if not defined DURATION_INT (
    echo   %C_ERR%Duration parse failed:%C_RESET% !CURRNAME!
    endlocal & exit /b 1
)
set /a FH=!DURATION_INT!/3600
set /a FM=(!DURATION_INT! %% 3600)/60
set /a FS=!DURATION_INT! %% 60
if !FH! LSS 10 set "FH=0!FH!"
if !FM! LSS 10 set "FM=0!FM!"
if !FS! LSS 10 set "FS=0!FS!"
echo      !FH!:!FM!:!FS!
endlocal & exit /b 0


:PRINT_BLUE
setlocal DisableDelayedExpansion
set "TXT=%~1"
powershell -NoProfile -Command "Write-Host $env:TXT -ForegroundColor Blue"
endlocal & exit /b 0

:USAGE
echo Usage:
echo   transcribe.bat "file_or_folder" "output_folder" [small^|large^|duration] [notime] [clean]
echo   transcribe.bat "file_or_folder" [small^|large^|duration] [notime] [clean]
exit /b 1