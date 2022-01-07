#!perl.exe -w

###### GITDIFFALL ###
#
# SYNOPIS:
#     gitdiffall <Ref> [-- path filter]
#     gitdiffall <Ref1> <Ref2> [-- path filter]
#
# Call gitdiffall with one or two refs and optional path filters.
# All different files between <Ref1> and <Ref2>, or between <Ref> and the current HEAD
# will be copied to a temporary folder and a visual diff tool will be launched.
# Even though git has in the meantime learned this capability as well it will always operate on temporary folders
# for all comparisons, while this script will always compare against the working dir if possible.
#
# HINTS:
# o  You can override Beyond Compare as default diff tool by setting the environment variable %COMPARE_TOOL
# o  In Windows PowerShell you have to write "--" instead of just -- in order to apply path filters

###### AUTHOR LIST ###
#
# MM    Moldmann

###### VERSION HISTORY ###
#
# v1.0  MM  2010-04-19  First Version
# v1.1  MM  2011-07-27  Fix: Support for files only existing in one commit
#                                  Fix: Also checkout files on the root level
#                                  Support <Ref1>..<Ref2> syntax
# v1.2  MM  2011-09-01  Several improvements and fixes
# v1.3  MM  2011-10-05  Support optional path filter syntax [-- path filter]
# v1.4  MM  2011-11-14  Fix: Support repositories located in path with spaces
# v1.5  MM  2011-11-28  Can show the diff between HEAD and <Ref> and between <Ref> and HEAD
# v1.6  MM  2012-03-21  Fix: Also work without GIT_HOME env variable
#                                  Fix: Multiple path filters working again
# v1.7  MM  2012-07-06  Fix: Better exit message in case of identical files
# v1.8  MM  2012-09-14  Change Beyond Compare Path for Win 7 support
# v1.9  MM  2012-09-26  Fix: path filter was not applied in rare cases
# v2.0  MM  2013-01-25  Support tags as References
# v2.1  MM  2015-01-30  Will show uncommitted differences if the given <Ref>'s are identical
# v2.2  MM  2015-12-03  Swap pre and post if necessary

use warnings;
use strict;
use File::Path;
use File::Temp qw/ tempfile tempdir /;

my $DEBUG_LEVEL = 0;    # Set to '1' to see debug messages
my $git;
my @opt_pathfilter = ();
my ($tmp_dir, $tmp_root_dir, $fh, $filelist, $suffix, $template);
my $cmd;
my @cmd;
my @cmd_list;
my $retVal;
my $file;
my ($my_count, $my_max_count);
my ($head, $head_sha1);
my ($pre,  $pre_sha1);
my ($post, $post_sha1);
my $temp;
my ($head_dir, $pre_dir, $post_dir, $temp_dir);
my @exactmatch_list;

# Determine console width
# my ($col_max, $row_max);
# {
  # my $data = `stty -a`;
  # if ($data =~ /rows (\d+)\; columns (\d+)/) {
     # ($row_max, $col_max) = ($1, $2);
     # #print("$row_max, $col_max\n");
  # } else {
     # #print "Cannot determine console width.\n";
     # # Use default values
     # ($row_max, $col_max) = (25, 80);
  # }
# }
# geek&poke: Honor the dead

# Set temp root directory
$tmp_root_dir = $ENV{TEMP};
$tmp_root_dir = $ENV{TMP} if (not defined $tmp_root_dir);

# Set file suffix
$suffix = '.tmp';

# Set temp file name template
$template = 'gitdiff-XXXX';

# Create Tempdir
$tmp_dir = tempdir( $template,
                DIR => $tmp_root_dir,
                CLEANUP =>  1 );

# # Create Tempfile
# $template = 'tmp_XXXX';

# ($fh, $filelist) = tempfile( $template,
                             # DIR => $tmp_dir,
                             # SUFFIX => $suffix,
                           # );

$tmp_dir =~ s/\\/\//g;
# print "Dir: $tmp_dir\n";
# print "File: $filelist\n";

#
# Eval arguments
#
if ($#ARGV == -1)
{
  # No arguments given
  $0 =~ m/([^\\\/]+)\.pl/;
  print("SYNOPIS: $1 <Refs> [-- path filter]\n" .
        "    $1 <Ref>\n" .
        "    $1 <Ref1> <Ref2>\n" .
        "    $1 <Ref1>..<Ref2>\n" .
        "Mandatory: Need one or two refs/commits as argument\n" .
        "Optional:  List of path names where diff should be applied\n");
  exit(1);
}

# Eval arguments
my $i = 0;
foreach $i (0..$#ARGV)
{
  # Eval Debug
  if ($ARGV[$i] =~ m/-debug/i)
  {
    $DEBUG_LEVEL = 1;
    print("> Debug mode enabled\n");
    # remove debug argument from @ARGV
    print("> Debug mode: ARGV <@ARGV> => <@ARGV[0..($i-1)]>\n");
    @ARGV = @ARGV[0..($i-1)];
  }
}
foreach $i (0..$#ARGV)
{
  # Eval path filter
  if ($ARGV[$i] eq "--")
  {
    # store path filter arguments
    @opt_pathfilter = @ARGV[$i+1..$#ARGV];
    print("> Path filter: <@opt_pathfilter> from ARGV <@ARGV>\n") if ($DEBUG_LEVEL);
    # remove path filter arguments from @ARGV
    @ARGV = @ARGV[0..($i-1)];
    last;
  }
}

# DEBUG: switch to unbuffered stdout/stderr
$| = 1 if ($DEBUG_LEVEL > 0);

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

#
# Read git SHA1's
#
if (defined($ENV{GIT_PATH}) && -e "$ENV{GIT_PATH}\\cmd\\git.cmd")
{
  $git = "$ENV{GIT_PATH}\\cmd\\git.cmd";
}
else
{
  $git = "git";
  print "Environment variable GIT_PATH not set.\nSearching for git:\n";
  print `git --version`;
}
print "Prepare diff:\n";
print("..Get git SHA1's\n");
# Info: git rev-parse --verify <Ref>
# Get SHA1 of <Ref> if possible
$head_sha1 = `$git rev-parse --verify HEAD`;
$pre_sha1  = `$git rev-parse --verify $pre`  if (defined $pre);
$post_sha1 = `$git rev-parse --verify $post` if (defined $post);
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
my $mergebase = `$git merge-base $pre_sha1 $post_sha1`;
if ($mergebase eq $post_sha1)
{
  # post is the merge-base and thus the parent of pre -> Swap pre and post
  $temp = $pre_sha1;
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
$cmd_list[0] =~ m/^([0-9a-f]+) refs\/[^\/]+\/(.+)/;
if (not defined($1) and not defined($2))
{
  print("[PROBLEM] grepping SHA1 and name from git show-ref: ");
  print @cmd_list;
  exit(1);
}
$head = $2;

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
  elsif ($cmd_list[0] !~ m/commit|tag/)
  {
    print("[PROBLEM] Given <Ref1> ($pre) is not of type 'commit' or 'tag': \n");
    print @cmd_list;
    exit(1);
  }
  #
  # commit is existing -> look for a symbolic ref name
  #
  $cmd = "$git show-ref | grep \"$pre\"";
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
  $pre = $head;
  $pre_sha1 = $head_sha1;
}

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
  elsif ($cmd_list[0] !~ m/commit|tag/)
  {
    print("[PROBLEM] Given <Ref1> ($pre) is not of type 'commit' or 'tag': \n");
    print @cmd_list;
    exit(1);
  }
  #
  # commit is existing -> look for a symbolic ref name
  #
  $cmd = "$git show-ref | grep \"$post\"";
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
  $post = $head;
  $post_sha1 = $head_sha1;
  # As no second comittish was given use HEAD.
  # This means PRE is head and POST shall be the given comittish.
  # Therefore now swap PRE and POST:
  ($pre, $post) = ($post, $pre);
  ($pre_sha1, $post_sha1) = ($post_sha1, $pre_sha1);
}

#
# Determine repo directory
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
print("> Master Git directory: $head_dir\n") if ($DEBUG_LEVEL > 0);
# Prepare $pre_dir and $post_dir
$pre_dir = "$tmp_dir/$pre";
$post_dir = "$tmp_dir/$post";

#
# Print diff summary
#
print("\nDiff summary:\n");
# PRE ref name and SHA1:
print("  PRE <Ref1> '$pre':\n");
$cmd = "$git log --abbrev-commit --pretty=oneline -1 $pre_sha1";
print "> $cmd\n" if ($DEBUG_LEVEL > 0);
@cmd_list = `$cmd -- | tee 2>&1`;
print("  @cmd_list");
# POST ref name and SHA1:
print("vs.\n");
print("  POST <Ref2> '$post':\n");
$cmd = "$git log --abbrev-commit --pretty=oneline -1 $post_sha1";
print "> $cmd\n" if ($DEBUG_LEVEL > 0);
@cmd_list = `$cmd -- | tee 2>&1`;
print("  @cmd_list\n");

if (!($pre_sha1 eq $head_sha1) && !($post_sha1 eq $head_sha1))
{
  # No Ref is identical to HEAD therefore we need a pre and a post temp dir.
  # Now check if $pre and $post are different:
  @cmd_list = `$git diff --name-only "$pre" "$post" -- @opt_pathfilter 2>&1`;
  if (not @cmd_list)
  {
    print("Files in $pre and $post are identical.\n");
    exit(0);
  }
  if ($cmd_list[0] =~ m/^fatal: /)
  {
    print("[ERROR] git diff: ");
    print @cmd_list;
    exit(1);
  }
  print("List of different files:\n");
  $my_count = 0;
  $my_max_count = scalar(@cmd_list);
  foreach $file (@cmd_list)
  {
    $my_count++;
    printf("%4d %s", $my_count, $file);
  }
  $my_count = 0;
  # Create root level directories
  mkpath([$pre_dir, $post_dir],0);
  foreach $file (@cmd_list)
  {
    $my_count++;
    chomp($file);
    printf("\r[%3d] Checking out to $tmp_dir/...", $my_count);

    # Check for file existence in repo
    # (git-cat-file -t exits with 0 in case of no error and returns 'blob' in case of a file)
    @cmd = `$git cat-file -t "$pre":"$file" 2>&1`;
    $retVal = $? >> 8;
    if (($retVal == 0) && ($cmd[0] =~ m/blob/))
    {
      #
      # In case file is existing create the path and do the checkout
      #
      # find filenames with directory prefix
      $file =~ m/(.*)?\/[^\/]+$/;
      if (defined $1)
      {
        # mkpath([list of dirs],boolean debug)
        mkpath(["$pre_dir/$1", "$post_dir/$1"],0);
      }
      @cmd = `$git show "$pre":"$file" > "$pre_dir/$file" 2>&1`;
      print @cmd;
    }

    # Check for file existence in repo
    # (git-cat-file -t exits with 0 in case of no error and returns 'blob' in case of a file)
    @cmd = `$git cat-file -t "$post":"$file" 2>&1`;
    $retVal = $? >> 8;
    if (($retVal == 0) && ($cmd[0] =~ m/blob/))
    {
      #
      # In case file is existing create the path and do the checkout
      #
      # find filenames with directory prefix
      $file =~ m/(.*)?\/[^\/]+$/;
      if (defined $1)
      {
        # mkpath([list of dirs],boolean debug)
        mkpath(["$pre_dir/$1", "$post_dir/$1"],0);
      }
      @cmd = `$git show "$post":"$file" > "$post_dir/$file" 2>&1`;
      print @cmd;
    }
  }
}
else
{
  # As one of the Ref's is equal to HEAD we need only one temp dir which shall be compared to
  # the Working tree.

  # Is a path filter enabled?
  if (scalar(@opt_pathfilter)>0)
  {
    $"="\n  ";
    print("Diff restricted to paths:\n  @opt_pathfilter\n\n");
    $"=" ";
  }

  my $head_compare;
  if ($pre_sha1 eq $head_sha1)
  {
    $head_compare = $post;
    $pre_dir = $head_dir;
    $temp = $post;
    $temp_dir = $post_dir;
  }
  else
  {
    $head_compare = $pre;
    $post_dir = $head_dir;
    $temp = $pre;
    $temp_dir = $pre_dir;
  }
  # Now check if $pre and HEAD are different:
  $cmd = "$git diff --name-status \"$head_compare\" HEAD -- @opt_pathfilter";
  print "> $cmd\n" if ($DEBUG_LEVEL > 0);
  @cmd_list = `$cmd 2>&1`;
  if (not @cmd_list)
  {
    print("Commits $head_compare and HEAD are identical.\n");
    # Check for local uncommitted changes
    @cmd_list = `git diff --name-status HEAD -- @opt_pathfilter 2>&1`;
    exit(0) if (not @cmd_list);
    print("Comparing against uncommitted changes in the working dir...\n");
  }
  if ($cmd_list[0] =~ m/^fatal: /)
  {
    print("[ERROR] git diff: ");
    print @cmd_list;
    exit(1);
  }

  $my_count = 0;
  $my_max_count = scalar(@cmd_list);
  print("(HINT: For many different files the 'gitdiffclone' command is recommended!)\n") if ($my_max_count >= 30);
  print("$my_max_count Different files:\n");
  foreach $file (@cmd_list)
  {
    $my_count++;
    printf("%4d %s", $my_count, $file);
    chomp($file);
    $file =~ s|.*?([\S]+)$|$1|g;
  }

  $my_count = 0;
  # Create root level directory
  mkpath([$temp_dir],0);
  foreach $file (@cmd_list)
  {
    $my_count++;
    printf("\r[%3d] Checking out to $temp_dir/...", $my_count);

    # Check for file existence in repo
    # (git-cat-file -t exits with 0 in case of no error and returns 'blob' in case of a file)
    @cmd = `$git cat-file -t "$temp":"$file" 2>&1`;
    $retVal = $? >> 8;
    if (($retVal == 0) && ($cmd[0] =~ m/blob/))
    {
      #
      # In case file is existing create the path and do the checkout
      #
      $file =~ m/(.*)?\/[^\/]+$/;
      if (defined $1)
      {
        # mkpath([list of dirs],boolean debug)
        mkpath(["$temp_dir/$1"],0);
      }
      $cmd = "$git show " . '"' . $temp . '":"' . $file . '" > "' . "$temp_dir/$file" .'"';
      print "> $cmd\n" if ($DEBUG_LEVEL > 0);
      @cmd = `$cmd 2>&1`;
      # @cmd = `$git show "$temp":"$file" > "$temp_dir/$file" 2>&1`;
      print @cmd;
    }
  }
}

if ($pre_sha1 eq $head_sha1)
{
  $pre = "$pre (Working tree)";
}
if ($post_sha1 eq $head_sha1)
{
  $post = "$post (Working tree)";
}
print("\r" . " " x 79 . "\r");
print("\nRunning compare tool:\n'$pre' vs. '$post'\n[$pre_dir] <=> [$post_dir]\n");
print("\n(Temp files will be deleted once you exit the Compare Tool)\n");
# Wait until exit of Compare tool, because temp files will be deleted afterwards
if (exists $ENV{COMPARE_TOOL})
{
  @cmd_list = `$ENV{COMPARE_TOOL} /solo "$pre_dir" "$post_dir" 2>&1`;
}
else
{
  @cmd_list = `C:\\PROGRA~1\\BEYOND~1\\BCompare.exe /solo "$pre_dir" "$post_dir" 2>&1`;
}
print @cmd_list;
