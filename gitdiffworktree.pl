#!/usr/bin/perl

###### GITDIFFWORKTREE ###
#
# SYNOPIS:
#     gitdiffworktree <Ref>
#     gitdiffworktree <Ref1> <Ref2>
#     gitdiffworktree <Ref1> <Ref2> -debug
#
# Call gitdiffworktree with one or two refs.
# The different refs will be checked out on seperate repository worktree's and a visual diff tool will be launched.
# gitdiffworktree will be faster than gitdiffall for 20+ different files and you have the possibility to
# make changes on both sides and commit them to different branches.
# Even though git has in the meantime learned to compare folders as well it will always operate on temporary folders
# for all comparisons, while this script will always compare against the working dir if possible.
#
# HINTS:
# * Override the default diff tool by setting the environment variable %COMPARE_TOOL
# * Change the default diff tool in the script below
# * Install the fd file search tool so the script will automatically find the diff tool directory (https://tinyurl.com/y6eos2q4)

###### AUTHOR LIST ###
#
# MM    Max Moldmann

###### VERSION HISTORY ###
#
# v1.0  MM  2010-05-11  First Version
# v1.1  MM  2011-08-31  Support <Ref1>..<Ref2> syntax / Support commits which have no refs entry
# v1.2  MM  2011-11-14  Fix: Correct grep problem in rare cases
# v1.3  MM  2012-03-21  Fix: Also work without GIT_HOME env variable
# v1.4  MM  2012-09-14  Change Beyond Compare Path for Win 7 support
# v1.5  MM  2013-06-17  Remove potentially modified files in Clone repo (using "git reset --hard")
# v1.6  MM  2015-01-15  Automatically create missing diff repos
# v1.7  MM  2015-01-26  Allows comparison of uncommitted working dir changes
# v1.8  MM  2015-01-29  Use clone option --separate-git-dir automatically
# v1.9  MM  2015-12-03  Swap pre and post if necessary
# v2.0  MM  2016-06-17  Gifdiffclone is now Gitdiffworktree using worktree's instead of clones
# v2.1  MM  2017-09-08  Fix: Commit ancestor detection
# v2.2  MM  2020-09-29  Fix: Windows 10 shell compatibility
# v2.3  MM  2020-10-02  Utilize fd to quickly locate diff tool
# v2.4  MM  2021-01-25  Add Linux support; limit different file list output
# v2.5  MM  2021-06-10  Fix: Linux command output redirect; Suppress git merge-base output

use warnings;
use strict;

my $cmd = "uname";
my $platform = `$cmd`;
my $DIFF_TOOL_NAME = "BCompare.exe";
my $DIFF_TOOL_PATH = "C:/Program Files/Beyond Compare 4";
my $TO_NULL = "2>nul";
if ($platform =~ "Linux")
{
    print "Platform: $platform";
    $DIFF_TOOL_NAME = "bcompare";
    $DIFF_TOOL_PATH = "/usr/bin/";
    $TO_NULL = "2>/dev/null";
}
my $DEBUG_LEVEL = 0;
my $git;
my @cmd_list;
my $sepDirCmd;
my $retVal;
my ($head, $head_sha1);
my ($pre,  $pre_sha1);
my ($post, $post_sha1);
my ($head_dir, $pre_dir, $post_dir);
my $self;   # This repo name
my $options = "-q ";
my @exactmatch_list;
my $separateGitDir;

# Trim whitespace on the right
sub rtrim { my $s = shift; $s =~ s/\s+$//; return $s };

#
# Eval arguments
#
if (not (defined $ARGV[0]) and not (defined $ARGV[1]))
{
    # No arguments given
    $0 =~ m/([^\\\/]+)\.pl/;
    print("SYNOPIS:                                                                 [version 2.5]\n" .
          "    $1 <Ref>\n" .
          "    $1 <Ref1> <Ref2>\n" .
          "    $1 <Ref1>..<Ref2>\n" .
          "    $1 <params> [-debug]\n\n" .
          "Need one or two refs/commits as argument; use HEAD to compare against the working dir!\n");
    exit(1);
}

# Eval Debug
if (defined $ARGV[$#ARGV])
{
    if ($ARGV[$#ARGV] =~ m/-debug/i)
    {
        $DEBUG_LEVEL = 1;
        pop(@ARGV);
    }
}

if (defined $ARGV[0] and not (defined $ARGV[1]))
{
  # handle COMMIT1..COMMIT2 syntax
  if (($ARGV[0] =~ m/(\w+)\.\.(\w+)/) and defined($1) and defined($2))
  {
    $ARGV[0] = $1;
    $ARGV[1] = $2;
  }
}

$pre  = "$ARGV[0]" if (defined $ARGV[0]);
$post = "$ARGV[1]" if (defined $ARGV[1]);
# Default to current branch
if (not defined $post)
{
  $post = `git rev-parse --abbrev-ref HEAD $TO_NULL`;
  chomp($post);
}

#
# Read git SHA1's
#
print "\nSearching for git...\n";
if (defined($ENV{GIT_PATH}) && -e "$ENV{GIT_PATH}\\cmd\\git.cmd")
{
  $git = "$ENV{GIT_PATH}\\cmd\\git.cmd";
}
else
{
  $git = "git";
  $cmd = "git --version";
  @cmd_list = `$cmd`;
  if (not defined($cmd_list[0]))
  {
    print("[ERROR] Cannot find git!\n" .
          "        Add ..\\git\\bin and ..\\git\\cmd folders to your PATH variable.\n" .
          "        Alternatively you can set the environment variable GIT_PATH.\n");
    exit(1);
  }
}
print("$cmd_list[0]");
$separateGitDir = 1 if (! -d "./.git");
print "Prepare diff:\n";
print("..Get git SHA1's\n");
# Info: git rev-parse --verify <Ref>
# Get SHA1 of <Ref> if possible
$head_sha1 = `git rev-parse --verify HEAD $TO_NULL`;
$pre_sha1  = `git rev-parse --verify $pre $TO_NULL`  if (defined $pre);
$post_sha1 = `git rev-parse --verify $post $TO_NULL` if (defined $post);
# remove whitespace from SHA
chomp($head_sha1);
chomp($pre_sha1) if (defined $pre);
chomp($post_sha1) if (defined $post);
if ($DEBUG_LEVEL > 0)
{
  print("> \$head_sha1 = $head_sha1\n");
  print("> \$pre_sha1  = $pre_sha1\n")  if (defined $pre);
  print("> \$post_sha1 = $post_sha1\n") if (defined $post);
}
`$git merge-base --is-ancestor $pre_sha1 $post_sha1 $TO_NULL`;   # requires Git v1.8
if ($? >= 1)    # Not an ancestor if errorcode = 1
{
  # post is the merge-base and thus the parent of pre -> Swap pre and post
  my $temp = $pre_sha1;
  $pre_sha1 = $post_sha1;
  $post_sha1 = $temp;
  $temp = $pre;
  $pre = $post;
  $post = $temp;
}

#
# Get Git ref for HEAD
#
print("..Get git refs\n");
#$cmd = "$git show-ref --heads --tags | grep \"$head_sha1\"";
$cmd = "$git show-ref | grep \"$head_sha1\"";
print "> $cmd\n" if ($DEBUG_LEVEL > 0);
@cmd_list = `$cmd -- 2>&1`;
print @cmd_list if ($DEBUG_LEVEL > 0);
if (not defined($cmd_list[0]))
{
  print("[ERROR] Cannot find git repository!\n");
  exit(1);
}
$cmd_list[0] =~ m/^([0-9a-f]+) refs\/[^\/]+\/(.+)/;
if (not defined($1) and not defined($2))
{
  print("[PROBLEM] grepping SHA1 and name from git show-ref: ");
  print @cmd_list;
  exit(1);
}
$head = $2;

#
# Get Git ref name for $post
#
if (defined $post)
{
  #
  # Check existence of commitish <Ref2> in repo (git-cat-file -t identifies the type as 'commit')
  #
  $cmd = "git cat-file -t \"$post_sha1\"";
  print "> $cmd\n" if ($DEBUG_LEVEL > 0);
  @cmd_list = `$cmd 2>&1`;
  $retVal = $? >> 8;
  if ($retVal != 0)
  {
    print("No commit named $post is existing.\n");
    print @cmd_list if ($DEBUG_LEVEL > 0);
    exit(0);
  }
  elsif ($cmd_list[0] !~ m/commit/)
  {
    print("[PROBLEM] Given <Ref2> ($post) is not of type 'commit': \n");
    print @cmd_list;
    exit(1);
  }
  #
  # commit is existing -> look for a symbolic ref name
  #
  $cmd = "$git show-ref | grep \"$post\$\"";
  print "> $cmd\n" if ($DEBUG_LEVEL > 0);
  @cmd_list = `$cmd -- 2>&1`;
  print @cmd_list if ($DEBUG_LEVEL > 0);
  if ($#cmd_list > 0)
  {
    # look for exact name matches
    if ($#cmd_list >= 1)
    {
      @exactmatch_list = grep { /\/${pre}$/ } @cmd_list;
      $cmd_list[0] = $exactmatch_list[0] if scalar(@exactmatch_list) > 0;
    }
    # grep SHA1 and ref name from show-ref output
    $cmd_list[0] =~ m/^([0-9a-f]+) refs\/[^\/]+\/(.+)/;
    if (not defined($1) and not defined($2))
    {
      print("[PROBLEM] Grepping SHA1 and ref name from git show-ref: ");
      print @cmd_list;
      exit(1);
    }
    $post = $2;
  }
}
else
{
  $post_sha1 = $head_sha1;
  $post = $head;
}

#
# Get Git ref name for $pre
#
if (defined $pre)
{
  #
  # Check existence of commitish <Ref1> in repo (git-cat-file -t identifies the type as 'commit')
  #
  $cmd = "git cat-file -t \"$pre_sha1\"";
  print "> $cmd\n" if ($DEBUG_LEVEL > 0);
  @cmd_list = `$cmd 2>&1`;
  $retVal = $? >> 8;
  if ($retVal != 0)
  {
    print("No commit named $pre is existing.\n");
    print @cmd_list if ($DEBUG_LEVEL > 0);
    exit(0);
  }
  elsif ($cmd_list[0] !~ m/commit/)
  {
    print("[PROBLEM] Given <Ref1> ($pre) is not of type 'commit': \n");
    print @cmd_list;
    exit(1);
  }
  #
  # commit is existing -> look for a symbolic ref name
  #
  $cmd = "$git show-ref | grep \"$pre\$\"";
  print "> $cmd\n" if ($DEBUG_LEVEL > 0);
  @cmd_list = `$cmd -- 2>&1`;
  print @cmd_list if ($DEBUG_LEVEL > 0);
  if ($#cmd_list > 0)
  {
    # look for exact name matches
    if ($#cmd_list >= 1)
    {
      @exactmatch_list = grep { /\/${pre}$/ } @cmd_list;
      $cmd_list[0] = $exactmatch_list[0] if scalar(@exactmatch_list) > 0;
    }
    # grep SHA1 and ref name from show-ref output
    $cmd_list[0] =~ m/^([0-9a-f]+) refs\/[^\/]+\/(.+)/;
    if (not defined($1) and not defined($2))
    {
      print("[PROBLEM] Grepping SHA1 and ref name from git show-ref: ");
      print @cmd_list;
      exit(1);
    }
    $pre = $2;
  }
}
else
{
  $pre_sha1 = $head_sha1;
  $pre = $head;
}

#
# Determine repo directories
#
$cmd = "$git rev-parse --show-toplevel 2>&1";
print "> $cmd\n" if ($DEBUG_LEVEL > 0);
@cmd_list = `$cmd`;
if (not @cmd_list)
{
  print("Cannot determine Git toplevel directory: \n");
  print @cmd_list;
  exit(1);
}
$head_dir = $cmd_list[0];
chomp($head_dir);
$head_dir =~ m/(.*[\\\/])(.*)/;
$self = $2;
print("> Master Git directory: $self in $1\n") if ($DEBUG_LEVEL > 0);
$pre_dir  = $head_dir . ".diff_pre";
$post_dir = $head_dir . ".diff_post";

#
# Print diff summary
#
print("\nDiff summary:\n");
if (($head_sha1 eq $pre_sha1) && ($head_sha1 eq $post_sha1) && ($pre eq "HEAD"))
{
  # Swap pre and post
  # so that pre can be used to checkout the current branch and the working directory shows the uncommitted differences
  ($pre, $post) = ($post, $pre);
  ($pre_sha1, $post_sha1) = ($post_sha1, $pre_sha1);
}
print("  PRE <Ref1> '$pre':\n");
$cmd = "$git log --abbrev-commit --pretty=oneline -1 $pre_sha1";
print "> $cmd\n" if ($DEBUG_LEVEL > 0);
@cmd_list = `$cmd -- | tee 2>&1`;
print("  @cmd_list");
print("vs.\n");
print("  POST <Ref2> '$post':\n");
$cmd = "$git log --abbrev-commit --pretty=oneline -1 $post_sha1";
print "> $cmd\n" if ($DEBUG_LEVEL > 0);
@cmd_list = `$cmd -- | tee 2>&1`;
print("  @cmd_list\n");

#
# Print file differences
#
$cmd = "$git diff --name-status \"$pre\" \"$post\"";
print "> $cmd\n" if ($DEBUG_LEVEL > 0);
@cmd_list = `$cmd -- | tee 2>&1`;
if (not @cmd_list)
{
  print("'$pre' and '$post' are identical.\n");
  print("(Note: Specify 'HEAD' if you want to compare against the current working tree)\n");
  exit(0) if (not (($pre eq 'HEAD') || ($post eq 'HEAD')));
  # Check for local uncommitted changes
  @cmd_list = `git diff --name-status HEAD -- 2>&1`;
  exit(0) if (not @cmd_list);
  print("Comparing against uncommitted changes in the working dir...\n");
}
if ($cmd_list[0] =~ m/^fatal: /)
{
  print("[ERROR] git diff: ");
  print @cmd_list;
  exit(1);
}
my $file_ct = scalar(@cmd_list);
my @file_list = ();
if ($file_ct > 200)
{
    # Filter out Added/Deleted files
    @file_list = grep(!/^D\s/, @cmd_list);
    if (scalar(@file_list) > 200)
    {
        @file_list = grep(!/^(A|D)\s/, @cmd_list);
    }
    my $num_ct = 200;
    $num_ct = scalar(@file_list) if (scalar(@file_list) < 200);
    if ($num_ct > 0)
    {
        print("Shortened list of different files:\n");
        print " @file_list[0..$num_ct]";
    }
}
else
{
    print("Different files:\n");
    print " @cmd_list";
}
print("Number of different files: $file_ct\n\n");

#######################################################################################
# --git-dir=<path>
# Set the path to the repository. This can also be controlled by setting the GIT_DIR environment variable. It can be an absolute path or relative path to current working directory.
#
# --work-tree=<path>
# Set the path to the working tree. The value will not be used in combination with repositories found automatically in a .git directory (i.e. $GIT_DIR is not set). This can also be controlled by setting the GIT_WORK_TREE environment variable and the core.worktree configuration variable. It can be an absolute path or relative path to the directory specified by --git-dir or GIT_DIR. Note: If --git-dir or GIT_DIR are specified but none of --work-tree, GIT_WORK_TREE and core.worktree is specified, the current working directory is regarded as the top directory of your working tree.
#######################################################################################

#
# Prepare $pre worktree
#
if (($head_sha1 eq $pre_sha1) && !(($head_sha1 eq $post_sha1) && ($post eq "HEAD")))
{
  print("..Using current repo\n");
  $pre_dir = $head_dir;
}
else
{
  print "Prepare checkout of PRE repository";
  print " at <Ref1> '$pre'" if ($DEBUG_LEVEL > 0);
  print ":\n";
  # Check existence of worktree
  if ((not -e "$pre_dir\/.git") && (not -e "$pre_dir\/..\/${self}.git.diff_pre\/"))
  {
    print("\n[INFO] Git worktree is not existing ($pre_dir)!\n" .
          "..Creating new worktree\n");

    $cmd = "$git worktree add --no-checkout -b diff_pre ..//${self}.diff_pre";
    print "> $cmd\n" if ($DEBUG_LEVEL > 0);
    # Create worktree
    @cmd_list = `$cmd -- 2>&1`;
    print @cmd_list if ($DEBUG_LEVEL > 0);
  }
  # Check again if worktree folder has been created
  if ((not -e "$pre_dir\/.git") && (not -d "$pre_dir\/..\/${self}.git.diff_pre\/"))
  {
      print @cmd_list if ($DEBUG_LEVEL == 0);
      exit(1);
  }

  print("..Checkout diff branch\n");
  $cmd = "$git --git-dir=$pre_dir/.git --work-tree=$pre_dir checkout -f -B diff_pre ${options}$pre_sha1";
  print "> $cmd\n" if ($DEBUG_LEVEL > 0);
  @cmd_list = `$cmd -- | tee 2>&1`;
  print @cmd_list;

  print("..Clean working dir\n");
  $cmd = "$git --git-dir=$pre_dir/.git --work-tree=$pre_dir clean -fd";
  print "> $cmd\n" if ($DEBUG_LEVEL > 0);
  @cmd_list = `$cmd -- | tee 2>&1`;
  print @cmd_list;
  print "\n";
}

#
# Prepare $post worktree
#
if ($head_sha1 eq $post_sha1)
{
  print("..Using current repo\n");
  $post_dir = $head_dir;
}
else
{
  print "Prepare checkout of POST repository";
  print " at <Ref2> '$post'" if ($DEBUG_LEVEL > 0);
  print ":\n";
  # Check existence of worktree
  if ((not -e "$post_dir\/.git") && (not -d "$post_dir\/..\/${self}.git.diff_post\/"))
  {
    print("\n[INFO] Git worktree is not existing ($post_dir)!\n" .
          "..Creating new worktree\n");

    $cmd = "$git worktree add --no-checkout -b diff_post ..//${self}.diff_post";
    print "> $cmd\n" if ($DEBUG_LEVEL > 0);
    # Create worktree
    @cmd_list = `$cmd -- 2>&1`;
    print @cmd_list if ($DEBUG_LEVEL > 0);
  }
  # Check again if worktree folder has been created
  if ((not -e "$post_dir\/.git") && (not -d "$post_dir\/..\/${self}.git.diff_post\/"))
  {
    print @cmd_list if ($DEBUG_LEVEL == 0);
    exit(1);
  }

  print("..Checkout diff branch\n");
  $cmd = "$git --git-dir=$post_dir/.git --work-tree=$post_dir checkout -f -B diff_post ${options}$post_sha1";
  print "> $cmd\n" if ($DEBUG_LEVEL > 0);
  @cmd_list = `$cmd -- | tee 2>&1`;
  print @cmd_list;

  print("..Clean working dir\n");
  $cmd = "$git --git-dir=$post_dir/.git --work-tree=$post_dir clean -fd";
  print "> $cmd\n" if ($DEBUG_LEVEL > 0);
  @cmd_list = `$cmd -- | tee 2>&1`;
  print @cmd_list;
  print "\n";
}

#
# Launch compare tool
#
if (($head_sha1 eq $pre_sha1) && ($head_sha1 eq $post_sha1))
{
    $post = "HEAD (Working tree differences)";
}
else
{
    if ($post_sha1 eq $head_sha1)
    {
      $post = "$post (Working tree)";
    }
    elsif ($pre_sha1 eq $head_sha1)
    {
      $pre = "$pre (Working tree)";
    }
}

# Find Diff tool
my $file_name = $DIFF_TOOL_NAME;
# Try to use default location
my $file_path = "${DIFF_TOOL_PATH}/${DIFF_TOOL_NAME}";
# Replace backslash with slash
$file_path =~ s/\\/\//g;
print "> Locate diff tool\n" if ($DEBUG_LEVEL > 0);
print "> Try to use default diff tool $file_path\n" if ($DEBUG_LEVEL > 0);
my $env_path = $ENV{COMPARE_TOOL};
if ((not -e $file_path) && defined($env_path))
{
  # Try to use environment variable
  $file_path = rtrim($env_path);
  print "> Try to use default environment variable COMPARE_TOOL $file_path\n" if ($DEBUG_LEVEL > 0);
}
my $input;
my @files_find;
my @program_list;
my @cmd_res_list;
my $out_file;
if (not -e $file_path)
{
  # Try to use last stored location
  print "> Try to use last stored location (difftool.bak)\n" if ($DEBUG_LEVEL > 0);
  if (-e "difftool.bak")
  {
    local $/ = undef;
    open FILE, "difftool.bak" or die "Couldn't open file: $!";
    binmode FILE;
    $input = <FILE>;
    close FILE;
    chomp($input);
  }
  if (defined($input) && -e $input)
  {
    $file_path = $input;
  }
  else
  {
    if ($platform =~ "Linux")
    {
      $file_path = "${DIFF_TOOL_PATH}/${DIFF_TOOL_NAME}";
      if (! -e $file_path)
      {
        print "\nERROR:\n";
        print "Could not find diff tool using the COMPARE_TOOL environment variable\n\n";
        print "Either set the COMPARE_TOOL variable or change the default tool in the script:\n";
        print "${file_path}\n\n";
        exit(2);
      }
    }
    else
    {
      # Platform Windows
      # Search on drive C:
      $cmd = "where fd.exe";
      print "> Locate fd file search tool in the environment PATH\n" if ($DEBUG_LEVEL);
      print "> $cmd\n" if ($DEBUG_LEVEL);
      @files_find = `$cmd`;
      # Remove INFO line if file cannot be found in the path
      @files_find = grep !/^INFO:/, @files_find ;
      print "> @files_find\n" if ($DEBUG_LEVEL);

      if (scalar @files_find == 0)
      {
        $file_path = "${DIFF_TOOL_PATH}/${DIFF_TOOL_NAME}";
        # Replace backslash with slash
        $file_path =~ s/\\/\//g;
        print "\nERROR:\n";
        print "Could not find diff tool using the COMPARE_TOOL environment variable\n\n";
        print "Either set the COMPARE_TOOL variable or change the default tool in the script:\n";
        print "${file_path}\n\n";
        print "TIP: Install the fd tool from https://github.com/sharkdp/fd \n";
        print "If installed and in the PATH the script will use fd to quickly locate the default diff tool\n";
        print "($DIFF_TOOL_NAME)\n\n";
        exit(2);
      }

      $cmd = "fd \^${file_name}\$ c:\\";

      print "Search for $DIFF_TOOL_NAME ...\n";
      $file_name =~ s/\./\\\./g;
      print "> $cmd\n" if ($DEBUG_LEVEL);
      @files_find = `$cmd`;
      chomp(@files_find);
      @files_find = sort @files_find;
      # change list separator from space to newline
      $" = "\n";
      # print list of found diff tool versions by line
      print "> @files_find\n" if ($DEBUG_LEVEL);

      if (scalar @files_find == 0)
      {
        $file_path = "${DIFF_TOOL_PATH}/${DIFF_TOOL_NAME}";
        # Replace backslash with slash
        $file_path =~ s/\\/\//g;
        print "\nERROR:\n";
        print "Could not find diff tool using the COMPARE_TOOL environment variable\n";
        print "Could not find diff tool ($DIFF_TOOL_NAME) on drive C:\\ \n\n";
        print "Either set the COMPARE_TOOL variable or change the default tool in the script:\n";
        print "${file_path}\n\n";
        exit(2);
      }
      else
      {
        if (scalar @files_find > 1)
        {
          # Use last found file (which is probably the latest version due to sort)
          print "Using diff tool: $files_find[$#files_find]\n";
          $file_path = $files_find[$#files_find];
        }
        else
        {
          $file_path = $files_find[0];
        }

        # Open difftool.bak file and write diff tool file path
        open($out_file, "> :crlf", "difftool.bak") or die $!;
        print $out_file $file_path;
        close $out_file;
      }
    }
  }
}

print("Running compare tool:\n'$pre' vs. '$post'\n[$pre_dir] <=> [$post_dir]\n");
$cmd = "\"$file_path\" \"$pre_dir\" \"$post_dir\" &";
print "> $cmd\n" if ($DEBUG_LEVEL > 0);
exec "$cmd";
