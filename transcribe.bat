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

set "ARG1=%~1"

if /I "%ARG1%"=="__one__" goto ONE_FILE
if /I "%ARG1%"=="__duration_one__" goto DURATION_ONE_FILE

:: top-level args: any order / any position
set "TARGET=%~1"
set "MODE=TRANSCRIBE"
set "MODEL_ARG="
set "NOTIME=0"
set "NOTIME_ARG="
set "CLEAN=0"
set "CLEAN_ARG="

if "%TARGET%"=="" goto USAGE

for %%A in ("%~2" "%~3" "%~4" "%~5" "%~6" "%~7" "%~8" "%~9") do (
    if /I "%%~A"=="duration" set "MODE=DURATION"
    if /I "%%~A"=="small" set "MODEL_ARG=small"
    if /I "%%~A"=="large" set "MODEL_ARG=large"
    if /I "%%~A"=="notime" set "NOTIME=1"
    if /I "%%~A"=="clean" set "CLEAN=1"
)

if "%NOTIME%"=="1" set "NOTIME_ARG=notime"
if "%CLEAN%"=="1" set "CLEAN_ARG=clean"

if /I "%MODEL_ARG%"=="small" (
    set "MODEL=%BASE%\models\ggml-small-q8_0.bin"
) else (
    set "MODEL=%BASE%\models\ggml-large-v3-turbo.bin"
)

echo ========================================
echo Target: "%TARGET%"
echo Mode  : %MODE%
if /I not "%MODE%"=="DURATION" echo Model : %MODEL%
echo ========================================

if not exist "%FFPROBE%" (
    echo ffprobe.exe not found:
    echo %FFPROBE%
    exit /b 1
)

if /I not "%MODE%"=="DURATION" (
    if not exist "%WHISPER%" (
        echo whisper-cli.exe not found:
        echo %WHISPER%
        exit /b 1
    )
    if not exist "%MODEL%" (
        echo model not found:
        echo %MODEL%
        exit /b 1
    )
    if not exist "%FFMPEG%" (
        echo ffmpeg.exe not found:
        echo %FFMPEG%
        exit /b 1
    )
    if not exist "%BASE%\temp" mkdir "%BASE%\temp"
    if not exist "%BASE%\output" mkdir "%BASE%\output"
)

if exist "%TARGET%" (
    if not exist "%TARGET%\*" (
        if /I "%MODE%"=="DURATION" (
            call "%SCRIPT%" __duration_one__ "%TARGET%" 1 1
        ) else (
            call "%SCRIPT%" __one__ "%TARGET%" 1 1 "%MODEL_ARG%" "%NOTIME_ARG%" "%CLEAN_ARG%"
            echo.
            echo All files done.
        )
        exit /b %errorlevel%
    )
)

if not exist "%TARGET%\*" (
    echo Path not found.
    exit /b 1
)

if /I "%MODE%"=="DURATION" goto RUN_DURATION_FOLDER
goto RUN_TRANSCRIBE_FOLDER

:RUN_DURATION_FOLDER
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$folder=$env:TARGET;" ^
  "$root=(Resolve-Path -LiteralPath $folder).Path;" ^
  "$mp4s=Get-ChildItem -LiteralPath $root -Filter *.mp4 -File -Recurse | Sort-Object DirectoryName, Name;" ^
  "if(($mp4s | Measure-Object).Count -eq 0){ Write-Host 'No MP4 files found.'; exit 0 };" ^
  "$total=0; $i=0; $lastDir='';" ^
  "foreach($f in $mp4s){" ^
  "  if($f.DirectoryName -ne $lastDir){ if($lastDir -ne ''){ Write-Host '' }; $dirName=Split-Path $f.DirectoryName -Leaf; Write-Host $dirName -ForegroundColor Cyan; $lastDir=$f.DirectoryName };" ^
  "  $i++;" ^
  "  try {" ^
  "    $d=& $env:FFPROBE -v quiet -show_entries format=duration -of csv=p=0 -- $f.FullName;" ^
  "    $sec=[int][math]::Floor([double]$d);" ^
  "    $total+=$sec;" ^
  "    $h=[int]($sec/3600); $m=[int](($sec%%3600)/60); $s=$sec%%60;" ^
  "    $t='{0:D2}:{1:D2}:{2:D2}' -f $h,$m,$s;" ^
  "    Write-Host ('  ['+$i+'/'+$mp4s.Count+'] '+$f.Name+'   '+$t)" ^
  "  } catch {" ^
  "    Write-Host ('  ['+$i+'/'+$mp4s.Count+'] '+$f.Name+'   Failed')" ^
  "  }" ^
  "};" ^
  "Write-Host '';" ^
  "$th=[int]($total/3600); $tm=[int](($total%%3600)/60); $ts=$total%%60;" ^
  "$tt='{0:D2}:{1:D2}:{2:D2}' -f $th,$tm,$ts;" ^
  "Write-Host ('Total duration: ' + $tt)"
exit /b %errorlevel%

:RUN_TRANSCRIBE_FOLDER
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$folder=$env:TARGET;" ^
  "$root=(Resolve-Path -LiteralPath $folder).Path;" ^
  "$script=$env:SCRIPT;" ^
  "$modelArg=$env:MODEL_ARG;" ^
  "$notimeArg=$env:NOTIME_ARG;" ^
  "$cleanArg=$env:CLEAN_ARG;" ^
  "$mp4s=Get-ChildItem -LiteralPath $root -Filter *.mp4 -File -Recurse | Sort-Object DirectoryName, Name;" ^
  "if(($mp4s | Measure-Object).Count -eq 0){ Write-Host 'No MP4 files found.'; exit 0 };" ^
  "$i=0; $lastDir='';" ^
  "foreach($f in $mp4s){" ^
  "  if($f.DirectoryName -ne $lastDir){ if($lastDir -ne ''){ Write-Host '' }; $dirName=Split-Path $f.DirectoryName -Leaf; Write-Host $dirName -ForegroundColor Cyan; $lastDir=$f.DirectoryName };" ^
  "  $i++;" ^
  "  $args = @('__one__', $f.FullName, [string]$i, [string]$mp4s.Count);" ^
  "  if($modelArg){ $args += $modelArg };" ^
  "  if($notimeArg){ $args += $notimeArg };" ^
  "  if($cleanArg){ $args += $cleanArg };" ^
  "  & $script @args;" ^
  "  if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE };" ^
  "}"
echo.
echo All files done.
exit /b %errorlevel%

:ONE_FILE
setlocal EnableDelayedExpansion
set "INPUT=%~2"
set "IDX=%~3"
set "TOT=%~4"
set "MODEL_ARG="
set "NOTIME=0"
set "CLEAN=0"

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
set "TIMEDTXT=%BASE%\output\%NAME%_timed.txt"
set "PLAINTXT=%BASE%\output\%NAME%.txt"

echo   [!IDX!/!TOT!] !CURRNAME!

if exist "!TIMEDTXT!" (
    for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format 'HHmmss'"`) do set "TS=%%T"
    set "TIMEDTXT=%BASE%\output\%NAME%_timed_!TS!.txt"
    set "PLAINTXT=%BASE%\output\%NAME%_!TS!.txt"
)

set "DURATION="
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$p = $env:INPUT; $fp = $env:FFPROBE; & $fp -v error -show_entries 'format=duration' -of 'default=noprint_wrappers=1:nokey=1' -- $p"`) do (
    set "DURATION=%%A"
)
if not defined DURATION (
    echo   Duration parse failed: !CURRNAME!
    endlocal & exit /b 1
)
for /f "delims=." %%A in ("!DURATION!") do set "DURATION_INT=%%A"
if not defined DURATION_INT (
    echo   Duration parse failed: !CURRNAME!
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
    echo   ffmpeg failed: !CURRNAME!
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
    echo   whisper failed: !CURRNAME!
    endlocal & exit /b 1
)
if not exist "!TIMEDTXT!" (
    echo   timed txt not generated: !CURRNAME!
    endlocal & exit /b 1
)

powershell -NoProfile -Command ^
  "$in = $env:TIMEDTXT; $out = $env:PLAINTXT;" ^
  "Get-Content -LiteralPath $in | Where-Object { $_ -match '^[[]' } | ForEach-Object { $_ -replace '^[[][^]]+[]]\s*','' } | Set-Content -LiteralPath $out -Encoding UTF8"
if errorlevel 1 (
    echo   plain txt generation failed: !CURRNAME!
    endlocal & exit /b 1
)

if "!CLEAN!"=="1" (
    call :ENHANCE_CLEAN_PRO "!PLAINTXT!"
) else (
    call :ENHANCE_CLEAN_TXT "!PLAINTXT!"
)
if errorlevel 1 (
    echo   enhance clean failed: !CURRNAME!
    endlocal & exit /b 1
)


if "!NOTIME!"=="1" (
    for %%F in ("%BASE%\output\%NAME%_timed*.txt") do (
        del /f /q "%%~F" >nul 2>&1
    )
)

if exist "!WAV!" del "!WAV!"
echo   Finished: !CURRNAME!
echo   Output files:
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
echo   [!IDX!/!TOT!] !CURRNAME!
set "DURATION="
for /f "usebackq delims=" %%A in (`powershell -NoProfile -Command "$p = $env:INPUT; $fp = $env:FFPROBE; & $fp -v error -show_entries 'format=duration' -of 'default=noprint_wrappers=1:nokey=1' -- $p"`) do (
    set "DURATION=%%A"
)
if not defined DURATION (
    echo   Duration parse failed: !CURRNAME!
    endlocal & exit /b 1
)
for /f "delims=." %%A in ("!DURATION!") do set "DURATION_INT=%%A"
if not defined DURATION_INT (
    echo   Duration parse failed: !CURRNAME!
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

:USAGE
echo Usage:
echo   transcribe.bat "file_or_folder" [small^|large^|duration] [notime] [clean]
exit /b 1