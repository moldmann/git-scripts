@echo off

rem ###### GITRBI ###
rem #
rem # SYNOPIS:
rem #     gitrbi [merge-base-ref]
rem #
rem # The current branch and its merge base is determined automatically and an interactive rebase (git rebase -i) 
rem # is started for all the commits which are only on the current branch but not on origin/dev. 
rem # Alternatively another merge base can be selected by specifying 'merge-base-ref'.
rem
rem ###### AUTHOR LIST ###
rem #
rem # MM    Max Moldmann
rem
rem ###### VERSION HISTORY ###
rem #
rem # v1.0  MM  2011/12/22  First Version
rem # v1.1  MM  2015/10/15  Look for merge base with origin/dev per default


echo gitrbi - Interactive Rebase of current branch
echo.
if "%1"=="" (
    SET MERGEBRANCH=origin/dev
) else (
    SET MERGEBRANCH=%*
)
rem Determine current branch
FOR /F "usebackq" %%i IN (`git rev-parse --abbrev-ref HEAD`) DO SET MYBRANCH=%%i
if "%MYBRANCH%"=="" (
    echo Warning: Cannot determine current branch!
    set MYBRANCH="--current"
    echo Determining common ancestor of current branch and %MERGEBRANCH%:
) else (
    echo Determining common ancestor of branch %MYBRANCH% and %MERGEBRANCH%:
)

echo.
FOR /F "usebackq" %%i IN (`git show-branch --merge-base %MYBRANCH% %MERGEBRANCH%`) DO SET MYANCESTOR=%%i
echo Common Ancestor: %MYANCESTOR%
echo.

echo Starting interactive rebase from %MYANCESTOR% ...
git rebase %MYANCESTOR% --interactive

set MYANCESTOR=
set MYBRANCH=
set MERGEBRANCH=
:End
