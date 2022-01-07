Moldmann
rem
rem ###### VERSION HISTORY ###
rem #
rem # v1.0  MM  15.12.2011  First Version
rem # v1.1  MM  19.01.2012  Windows PowerShell compatibility
rem # v1.2  MM  20.01.2012  Workaround for gitk origin/master update problem
rem # v1.3  MM  29.04.2013  Also support branches like "user/name"

echo gitsync - Automatic rebase/sync of current local branch to server repository
echo.

rem Determine current branch
FOR /F "usebackq" %%i IN (`git symbolic-ref -q HEAD`) DO SET CURRENT=%%i
if "%CURRENT%"=="" (
    echo ERROR: Cannot determine current branch!
    goto End
)

rem Fetch the latest changes
echo Fetch the latest changes...
call git fetch origin master

if "%CURRENT%" NEQ "refs/heads/master" (
    call git checkout master
)

rem Do the pull rebase
echo Rebase master branch...
call git pull --rebase origin master

rem Extract branch name from symbolic-ref (remove "refs/heads/" part )
set BRANCH=%CURRENT:~11,255%

if "%BRANCH%" NEQ "master" (
    call git checkout %BRANCH%
    echo Rebase current branch...
    call git rebase master
)

rem Workaround in case the origin/master ref gets not updated in gitk: execute git fetch
call git fetch origin master > NUL

set BRANCH=
set CURRENT=

rem * HINT: `git pull --rebase` by default
rem * If you want git pull to add in --rebase every time,
rem * you can set the branch.autosetuprebase configuration option.
rem * From the docs (for git-config):
rem *     When a new branch is created with git-branch or git-checkout that tracks another branch,
rem *     this variable tells git to set up pull to rebase instead of merge (see "branch..rebase").
rem *     When never, rebase is never automatically set to true.
rem *     When local, rebase is set to true for tracked branches of other local branches.
rem *     When remote, rebase is set to true for tracked branches of remote branches.
rem *     When always, rebase will be set to true for all tracking branches.
rem *     See "branch.autosetupmerge" for details on how to set up a branch to track another branch.
rem *     This option defaults to never.
rem * To set:
rem *     git config branch.autosetuprebase always
rem * Of course, you can override this with --no-rebase.
