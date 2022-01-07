@echo off
rem ###### GITPUSH ###
rem #
rem # SYNOPIS:
rem #     gitpush
rem #
rem # Automated push of current branch to server repository.
rem # When the current branch is in sync with the remote repository it merges the current branch into
rem # your local master branch, then does a push and afterwards returns to your current branch.
rem # HINT: Will fail if master branch is not syncable with origin/master!
rem
rem ###### AUTHOR LIST ###
rem #
rem # MM    Moldmann
rem
rem ###### VERSION HISTORY ###
rem #
rem # v1.0  MM  2011/12/15  First Version
rem # v1.1  MM  2012/01/19  Windows PowerShell compatibility
rem # v1.2  MM  2012/09/26  Fetch remote reference after push
rem # v1.3  MM  2012/11/28  Fetch remote reference before & after push

echo gitpush - Automated push of current branch to server repository
echo.

rem Determine current branch
FOR /F "usebackq" %%i IN (`git symbolic-ref -q HEAD`) DO SET CURRENT=%%i
if "%CURRENT%"=="" (
    echo ERROR: Cannot determine current branch!
    goto End
)

rem Extract branch name from symbolic-ref
for /f "tokens=3 delims=//" %%a in ("%CURRENT%") do (
    set BRANCH=%%a
)

if "%BRANCH%" NEQ "master" (
    call git checkout master
    call git merge %BRANCH%
)

rem Update origin/master reference to position before push
call git fetch origin master > NUL

call git push origin master

rem Update origin/master reference to position after push
call git fetch origin master > NUL

if "%BRANCH%" NEQ "master" (
    call git checkout %BRANCH%
)

set BRANCH=
set CURRENT=
