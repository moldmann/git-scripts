@REM GRM - Git Remove
@REM Delete path names copied from git status output containing forward slashes
@FOR /F "usebackq delims==" %%A IN (`echo %* ^| sed "s/\//\\\/g"`) DO del -f %%A