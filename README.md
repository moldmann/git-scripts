# Versatile Git scripts

## Diff entire checkouts instead of single files
**gitdiffall** was built before Git learned to diff entire checkouts.
This script still has the advantage that it will compare against your worktree if possible.
Once temporary files have been created it launches a comparison tool like Beyond Compare.

**gitdiffworktree** is the more advanced comparison script to compare two versions of a repo.
It is using the Git worktree feature, which is the fastest way to checkout the repo at another version.

## Find and list large commits that blow up the repository size
Use **git-find-large-commits** to find large commits so they can be eliminated.

## Create fast incremental automatic backups of your local repositories to a network folder
This **git-auto-backup** script is using rsync and can even create backups of the files that are not yet committed.

## Git Push helper
**gitpush** provides an automated push of current branch to server repository.
When the current branch is in sync with the remote repository it merges the current branch
into your local master branch, then does a push and afterwards returns to your current branch.
NOTE: This will intentionally fail if the master branch is not in sync with origin/master!

## Interactive Rebase Helper
Interactive rebase is an indispensable tool to create nicely reviewable change sets.
**gitrbi** automatically detects where your current branch is branching off of another branch
and starts the interactive rebase process, so you don't have to think about at which older commit
your interactive rebase session should start.

## Sync with master branch
Automatic rebase/sync of current local branch to server repository
gitsync

## Git Remove helper script for Windows
When using git status, the file paths in the output contain forward slashes.
This limits the usefulness of the output for copy/paste.
Using **grm** instead of the **del** command will convert the slashes and then delete all the files given as parameter.

## Start a local Git repository server on your PC
In the event that a Git repository server can't be used, spawn your own local Git repository server,
that can also be accessed from other people in the network using the **gitdaemon** script.

## Git support for CoDeSys projects
The **codesys-import** script makes it possible to use the Git Version Control for Codesys projects.
Git stores just an empty project file and all of the exported EXP files of a full project.
This script can auto update a project file with the latest changes from Git,
or it can recreate a full project file by importing all EXP files into a empty project file copy.
