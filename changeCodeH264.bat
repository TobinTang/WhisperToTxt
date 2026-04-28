@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion

set "BASE=%~dp0"
if "%BASE:~-1%"=="\" set "BASE=%BASE:~0,-1%"

set "SCRIPT=%~f0"
set "FFMPEG=%BASE%\ffmpeg.exe"

set "ARG1=%~1"
if /I "%ARG1%"=="__one__" goto ONE_FILE

:: ============================================================
:: changeCodeH264.bat
:: Usage:
::   changeCodeH264.bat "source_file_or_folder" [output_folder] [jobs]
::
:: Rules:
::   1) source is a single file + no output folder:
::        output next to source file
::   2) source is a single file + output folder:
::        output to output_folder\file_TV.mp4
::   3) source is a folder + no output folder:
::        output next to each source file
::   4) source is a folder + output folder:
::        keep source folder name and all subfolders under output_folder
::        source: D:\A\B\video.mp4
::        cmd   : changeCodeH264.bat "D:\A" "D:\OUT"
::        output: D:\OUT\A\B\video_TV.mp4
:: ============================================================

set "TARGET=%~1"
set "OUTROOT=%~2"
set "MAXJOBS=%~3"
call :TRIM_VAR TARGET
call :TRIM_VAR OUTROOT
call :TRIM_VAR MAXJOBS
if "%MAXJOBS%"=="" set "MAXJOBS=3"

:: Dedicated env vars for PowerShell, avoid pollution from external TARGET/OUTROOT/MAXJOBS
set "CH_TARGET=%TARGET%"
set "CH_OUTROOT=%OUTROOT%"
set "CH_MAXJOBS=%MAXJOBS%"

if "%TARGET%"=="" goto USAGE

if not exist "%FFMPEG%" (
    echo ffmpeg.exe not found:
    echo %FFMPEG%
    exit /b 1
)

if not "%OUTROOT%"=="" (
    if not exist "%OUTROOT%" mkdir "%OUTROOT%"
    if errorlevel 1 (
        echo Output folder create failed:
        echo %OUTROOT%
        exit /b 1
    )
)

echo ========================================
echo Target: "%TARGET%"
if "%OUTROOT%"=="" (
    echo Output: same folder as source
) else (
    echo Output: "%OUTROOT%"
    echo Mode  : keep source folder structure
)
echo Codec : H.264 / AVC, AAC, yuv420p
echo Scale : 1920:-2, fps=30
echo Jobs  : %MAXJOBS%
echo Log   : folder mode uses parent progress / ffmpeg silent
echo Name  : output folder specified = no _TV suffix
echo Skip  : existing output is skipped only when duration matches
echo Error : failed ffmpeg stderr saved to output\_logs
echo ========================================

if exist "%TARGET%" (
    if not exist "%TARGET%\*" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command ^
          "$file=(Resolve-Path -LiteralPath $env:CH_TARGET).Path;" ^
          "$rel='';" ^
          "& $env:SCRIPT '__one__' $file '1' '1' $env:CH_OUTROOT $rel"
        echo.
        echo All files done.
        exit /b %errorlevel%
    )
)

if not exist "%TARGET%\*" (
    echo Path not found.
    exit /b 1
)

goto RUN_FOLDER

:RUN_FOLDER
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$folder=$env:CH_TARGET;" ^
  "$root=(Resolve-Path -LiteralPath $folder).Path.TrimEnd('\');" ^
  "$rootLeaf=Split-Path -Leaf $root;" ^
  "$ffmpeg=$env:FFMPEG;" ^
  "$outRoot=$env:CH_OUTROOT;" ^
  "$maxJobs=[int]$env:CH_MAXJOBS; if($maxJobs -lt 1){ $maxJobs=3 };" ^
  "$tmpRoot=Join-Path $env:TEMP ('h264_progress_' + [guid]::NewGuid().ToString()); New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null;" ^
  "$logRoot=if([string]::IsNullOrWhiteSpace($outRoot)){ Join-Path $tmpRoot 'logs' } else { Join-Path $outRoot '_logs' }; New-Item -ItemType Directory -Path $logRoot -Force | Out-Null;" ^
  "function QuoteArg([string]$s){ return '\"' + ($s -replace '\"','\\\"') + '\"' }" ^
  "function GetDurationUs([string]$path){ $txt=& $ffmpeg -hide_banner -i $path 2>&1 | Out-String; $m=[regex]::Match($txt,'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)'); if(!$m.Success){ return 0 }; return [int64](([int]$m.Groups[1].Value*3600+[int]$m.Groups[2].Value*60+[double]$m.Groups[3].Value)*1000000) }" ^
  "function GetProgressPct([string]$progress,[int64]$dur){ if($dur -le 0 -or !(Test-Path -LiteralPath $progress)){ return 0 }; $line=Get-Content -LiteralPath $progress -ErrorAction SilentlyContinue | Where-Object { $_ -like 'out_time_ms=*' -and $_ -notlike '*N/A*' } | Select-Object -Last 1; if(!$line){ return 0 }; $raw=($line -replace 'out_time_ms=',''); $v=0; if(-not [int64]::TryParse($raw,[ref]$v)){ return 0 }; $p=[math]::Floor(($v*100.0)/$dur); if($p -gt 100){$p=100}; return $p }" ^
  "function BuildOutput($f,$relDir){ if([string]::IsNullOrWhiteSpace($outRoot)){ $outDir=$f.DirectoryName; $suffix='_TV' } else { $suffix=''; if([string]::IsNullOrWhiteSpace($relDir)){ $outDir=$outRoot } else { $outDir=Join-Path $outRoot $relDir } }; $outName=[IO.Path]::GetFileNameWithoutExtension($f.Name) + $suffix + '.mp4'; return Join-Path $outDir $outName }" ^
  "$mp4s=Get-ChildItem -LiteralPath $root -Filter *.mp4 -File -Recurse | Where-Object { $_.Name -notmatch '_TV(_\d{6})?\.mp4$' } | Sort-Object DirectoryName, Name;" ^
  "$total=($mp4s | Measure-Object).Count; if($total -eq 0){ Write-Host 'No MP4 files found.'; exit 0 };" ^
  "$queue=New-Object System.Collections.Queue; $idx=0; $lastDir='';" ^
  "foreach($f in $mp4s){ $idx++; if($f.DirectoryName -ne $lastDir){ if($lastDir -ne ''){ Write-Host '' }; $show=$f.DirectoryName.Substring($root.Length).TrimStart('\'); if([string]::IsNullOrWhiteSpace($show)){ $show=$rootLeaf }; Write-Host $show -ForegroundColor Cyan; $lastDir=$f.DirectoryName }; $relDir=''; if($outRoot){ $sub=$f.DirectoryName.Substring($root.Length).TrimStart('\'); if([string]::IsNullOrWhiteSpace($sub)){ $relDir=$rootLeaf } else { $relDir=Join-Path $rootLeaf $sub } }; $outFile=BuildOutput $f $relDir; $srcDur=GetDurationUs $f.FullName; if($srcDur -le 0){ Write-Host ('  ['+$idx+'/'+$total+'] Skip unreadable/invalid duration: '+$f.Name); continue }; if(Test-Path -LiteralPath $outFile){ $outDur=GetDurationUs $outFile; if($srcDur -gt 0 -and $outDur -gt 0 -and [math]::Abs($srcDur-$outDur) -lt 1000000){ Write-Host ('  ['+$idx+'/'+$total+'] Skip existing duration OK: '+$f.Name); continue } else { Write-Host ('  ['+$idx+'/'+$total+'] Re-encode duration mismatch: '+$f.Name); Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue } }; $dur=$srcDur; $queue.Enqueue([pscustomobject]@{File=$f;Idx=$idx;RelDir=$relDir;OutFile=$outFile;Dur=$dur}) }" ^
  "$running=@(); $failed=0;" ^
  "try {" ^
  "while($queue.Count -gt 0 -or ($running | Where-Object { -not $_.Proc.HasExited }).Count -gt 0){" ^
  "  while($queue.Count -gt 0 -and ($running | Where-Object { -not $_.Proc.HasExited }).Count -lt $maxJobs){ $t=$queue.Dequeue(); $outDir=Split-Path -Parent $t.OutFile; if(!(Test-Path -LiteralPath $outDir)){ New-Item -ItemType Directory -Path $outDir -Force | Out-Null }; $progress=Join-Path $tmpRoot ('p_'+$t.Idx+'.txt'); $logFile=Join-Path $logRoot ('ffmpeg_'+$t.Idx+'.log'); $args=@('-hide_banner','-loglevel','error','-nostats','-progress',$progress,'-i',$t.File.FullName,'-vf','scale=1920:-2,fps=30','-c:v','libx264','-pix_fmt','yuv420p','-profile:v','high','-level','4.1','-preset','medium','-crf','23','-c:a','aac','-b:a','160k',$t.OutFile); $argLine=($args | ForEach-Object { QuoteArg $_ }) -join ' '; Write-Host ('  ['+$t.Idx+'/'+$total+'] Start: '+$t.File.Name); Write-Host ('     Output: '+$t.OutFile); $psi=New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName=$ffmpeg; $psi.Arguments=$argLine; $psi.UseShellExecute=$false; $psi.RedirectStandardError=$true; $psi.CreateNoWindow=$true; $proc=[System.Diagnostics.Process]::Start($psi); $running += [pscustomobject]@{Proc=$proc;Task=$t;Progress=$progress;Log=$logFile} };" ^
  "  foreach($r in @($running)){ if($r.Proc.HasExited){ Write-Progress -Id $r.Task.Idx -Activity ('Transcoding ['+$r.Task.Idx+'/'+$total+']') -Completed; $err=''; try { $err=$r.Proc.StandardError.ReadToEnd() } catch {}; if($err){ Set-Content -LiteralPath $r.Log -Value $err -Encoding UTF8 }; if($r.Proc.ExitCode -eq 0 -and (Test-Path -LiteralPath $r.Task.OutFile)){ Write-Host ('  ['+$r.Task.Idx+'/'+$total+'] Finished: '+$r.Task.File.Name); if(Test-Path -LiteralPath $r.Log){ Remove-Item -LiteralPath $r.Log -ErrorAction SilentlyContinue } } else { Write-Host ('  ['+$r.Task.Idx+'/'+$total+'] FAILED: '+$r.Task.File.Name); if($r.Log){ if((Test-Path -LiteralPath $r.Log) -and ((Get-Item -LiteralPath $r.Log).Length -gt 0)){ Write-Host ('     Error log: '+$r.Log) } else { Write-Host ('     Error log empty; ffmpeg may not have started correctly or was interrupted.') } }; $failed=1 }; Remove-Item -LiteralPath $r.Progress -ErrorAction SilentlyContinue } };" ^
  "  $running=$running | Where-Object { -not $_.Proc.HasExited };" ^
  "  foreach($r in $running){ $pct=GetProgressPct $r.Progress $r.Task.Dur; Write-Progress -Id $r.Task.Idx -Activity ('Transcoding ['+$r.Task.Idx+'/'+$total+']') -Status ($pct.ToString()+' percent - '+$r.Task.File.Name) -PercentComplete $pct };" ^
  "  Start-Sleep -Milliseconds 800" ^
  "}" ^
  "} finally { foreach($r in @($running)){ if($r -and $r.Proc -and -not $r.Proc.HasExited){ try { taskkill /PID $r.Proc.Id /T /F 2>$null | Out-Null } catch {} } }; Remove-Item -LiteralPath $tmpRoot -Recurse -Force -ErrorAction SilentlyContinue }" ^
  "exit $failed"
echo.
echo All files done.
exit /b %errorlevel%

:TRIM_VAR
setlocal EnableDelayedExpansion
set "_v=!%~1!"
:TRIM_VAR_LEAD
if defined _v if "!_v:~0,1!"==" " set "_v=!_v:~1!" & goto TRIM_VAR_LEAD
:TRIM_VAR_TAIL
if defined _v if "!_v:~-1!"==" " set "_v=!_v:~0,-1!" & goto TRIM_VAR_TAIL
endlocal & set "%~1=%_v%"
exit /b 0

:TRIM_VAR_DELAYED
set "_v=!%~1!"
:TRIM_VAR_DELAYED_LEAD
if defined _v if "!_v:~0,1!"==" " set "_v=!_v:~1!" & goto TRIM_VAR_DELAYED_LEAD
:TRIM_VAR_DELAYED_TAIL
if defined _v if "!_v:~-1!"==" " set "_v=!_v:~0,-1!" & goto TRIM_VAR_DELAYED_TAIL
set "%~1=!_v!"
set "_v="
exit /b 0

:ONE_FILE
setlocal EnableDelayedExpansion
set "INPUT=%~2"
set "IDX=%~3"
set "TOT=%~4"
set "OUTROOT=%~5"
set "RELDIR=%~6"
call :TRIM_VAR_DELAYED OUTROOT
call :TRIM_VAR_DELAYED RELDIR

if not exist "!INPUT!" (
    echo   File not found: !INPUT!
    endlocal & exit /b 1
)

set "NAME=%~n2"
set "CURRNAME=%~nx2"
set "SRC_DIR=%~dp2"

if "!OUTROOT!"=="" (
    set "OUTDIR=!SRC_DIR!"
) else (
    if "!RELDIR!"=="" (
        set "OUTDIR=!OUTROOT!"
    ) else (
        set "OUTDIR=!OUTROOT!\!RELDIR!"
    )
    if not exist "!OUTDIR!" mkdir "!OUTDIR!"
    if errorlevel 1 (
        echo   Output folder create failed: !OUTDIR!
        endlocal ^& exit /b 1
    )
)

if "!OUTROOT!"=="" (
    set "SUFFIX=_TV"
) else (
    set "SUFFIX="
)

set "OUTFILE=!OUTDIR!\!NAME!!SUFFIX!.mp4"

if exist "!OUTFILE!" (
    set "DURCHECK="
    for /f "usebackq delims=" %%D in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "$ff=$env:FFMPEG; function D($p){ $txt=& $ff -hide_banner -i $p 2>&1 ^| Out-String; $m=[regex]::Match($txt,'Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)'); if(!$m.Success){ return 0 }; return [int64](([int]$m.Groups[1].Value*3600+[int]$m.Groups[2].Value*60+[double]$m.Groups[3].Value)*1000000) }; $a=D $env:INPUT; $b=D $env:OUTFILE; if($a -gt 0 -and $b -gt 0 -and [math]::Abs($a-$b) -lt 1000000){ 'OK' } else { 'BAD' }"`) do set "DURCHECK=%%D"

    if "!DURCHECK!"=="OK" (
        echo   [!IDX!/!TOT!] Skip existing duration OK: !CURRNAME!
        endlocal & exit /b 0
    ) else (
        echo   Existing output duration mismatch, re-encode: !CURRNAME!
        del /f /q "!OUTFILE!" >nul 2>nul
    )
)

echo   [!IDX!/!TOT!] !CURRNAME!
echo      Output: !OUTFILE!

"%FFMPEG%" -hide_banner -loglevel error -stats -i "!INPUT!" ^
-vf "scale=1920:-2,fps=30" ^
-c:v libx264 -pix_fmt yuv420p -profile:v high -level 4.1 -preset medium -crf 23 ^
-c:a aac -b:a 160k ^
"!OUTFILE!"

if errorlevel 1 (
    echo   ffmpeg failed: !CURRNAME!
    endlocal & exit /b 1
)

if not exist "!OUTFILE!" (
    echo   output file not generated: !CURRNAME!
    endlocal & exit /b 1
)

echo   Finished: !CURRNAME!
endlocal & exit /b 0

:USAGE
echo Usage:
echo   changeCodeH264.bat "file_or_folder" [output_folder] [jobs]
echo.
echo Examples:
echo   changeCodeH264.bat "D:\Videos\a.mp4"
echo   changeCodeH264.bat "D:\Videos\a.mp4" "D:\Videos_TV"
echo   changeCodeH264.bat "D:\Videos" "D:\Videos_TV" 3
echo.
echo Folder example with structure:
echo   Source: D:\Videos\A\b.mp4
echo   Output: D:\Videos_TV\Videos\A\b.mp4
echo.
echo Single file example:
echo   Source: D:\Videos\A\b.mp4
echo   Output: D:\Videos_TV\b.mp4
exit /b 1
