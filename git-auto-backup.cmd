@echo off
title Backup - Git Repos
REM ---DESCRIPTION---
REM
REM Run this script as a daily windows job
REM It will rsync your local .git Repo folder to an external backup drive
REM and it also stores a Zip copy of every modified uncommitted file
REM
REM Needs:
REM   program cwRsync
REM   program Perl
REM   file '.rsync_filter_git' (specify git repo folders to backup here)
REM   file 'sleep.pl'
REM
REM ---TODO---
REM Needs to work on SET variables instead of hardcoded paths everywhere

REM Backup Modified files in zip file
REM (Copy and adapt this structure for all your repositories)

SET ZIP7=C:\PROGRA~1\7-Zip\7z.exe

echo.
SET SRC=C:\Scripts
SET TRG=U:\600_Backup\Scripts
echo Backup Modified files of repo Scripts in zip file
mkdir %TRG% 2>nul
del %TRG%\ModifiedFiles.zip 2> nul
pushd %SRC%
echo [ git status -s ^| grep -E "^( A| M|\?\?)" ^| cut -d ' ' -f 3 ^| xargs %ZIP7% a -tzip %TRG%\ModifiedFiles.zip ]
git status -s | grep -E "^( A| M| D|\?\?)" && git status -s | grep -E "^( A| M|\?\?)" | cut -d ' ' -f 3 | xargs %ZIP7% a -tzip %TRG%\ModifiedFiles.zip 2> nul
popd

echo.
SET SRC=C:\workspace\projects\ICE\src
SET TRG=U:\600_Backup\projects\ICE
echo Backup Modified files of repo ICE in zip file
mkdir %TRG% 2>nul
del %TRG%\ModifiedFiles.zip 2> nul
pushd %SRC%
echo [ git status -s ^| grep -E "^( A| M|\?\?)" ^| cut -d ' ' -f 3 ^| xargs %ZIP7% a -tzip %TRG%\ModifiedFiles.zip ]
git status -s | grep -E "^( A| M| D|\?\?)" && git status -s | grep -E "^( A| M|\?\?)" | cut -d ' ' -f 3 | xargs %ZIP7% a -tzip %TRG%\ModifiedFiles.zip 2> nul
popd

set STARTTIME=%TIME%
echo.
echo Start Rsync ...
REM * Rsync
REM * Put the copy on a private or better public drive so that your team can easily access your code if necessary
rsync.exe --progress --stats --filter='. /cygdrive/c/Scripts/Git/.rsync_filter_git' -rltvz -k -L --del /cygdrive/c/workspace/ /cygdrive/u/600_Backup/
echo START %STARTTIME%
echo END   %TIME%

if not errorlevel 0 goto Error

echo.
C:\Scripts\sleep.pl 5
goto End

:Error
echo.
echo ERROR DURING EXECUTION OF %0
echo.
echo 
pause

:End
SET ZIP7=
SET SRC=
SET TRG=