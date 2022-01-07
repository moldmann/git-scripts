#!perl.exe -w

###### codesys-import - Auto import latest EXP changes since last commit
#
# Can be invoked after a git fetch or rebase of a CoDeSys-design project in order to automatically import the newly
# changed or merged EXP files into the CoDeSys project
#
#   SYNTAX: codesys-import <all|export>
#
# When called with no parameters all EXP files which have changed since the last commit are being imported.
# When no local changes are present then all new changes from origin/dev are being imported.
#
# Parameter:
#   all    - import all files from the exp\ folder
#   export - only export the project into the exp\ folder
#
# Hints:
#  - The tool is searching and storing the location of the Codesys.exe file automatically
#  - The tool is searching for the *.pro file automatically
#  - It is advisable to store the EXP files but only an empty *.pro file in the Git repository. This way the *.exp files
#    and the *.pro file can never be out of sync.

###### Author List
#
# MM    Max Moldmann

###### Version History
#
# v1.0  MM  2015-09-30  First Version
# v1.1  MM  2016-04-27  Find Codesys.exe location automatically (using File::Find::Rule module). Add <all> parameter.
# v1.2  MM  2016-05-09  Faster search for Codesys.exe (limit directory depth of search and search at prominent locations first)
# v1.3  MM  2016-05-20  Import many *.exp files in slices (Importing a large number of files seems to be buggy)
# v1.4  MM  2016-05-24  Faster import by using one glob command instead of one import command per exp file
# v1.5  MM  2016-06-09  Add <export> parameter. Fix problem caused by not importing the Codesys Excel export files last
# v1.6  MM  2016-06-24  Faster search for Codesys.exe using Windows builtin 'where' command (Programs subfolders in 1 second, whole disk in 10 seconds)
# v1.7  MM  2016-10-24  Add support for *empty.pro files. Default to import all mode (using the empty project) and use Git mode only as default if there is no empty project file

use warnings;
use strict;
# get path containing script
use FindBin qw($Bin $Script);
# search for perl modules in the include & lib directory (if they are not installed via ppm)
use lib "$Bin/lib", "$Bin/include", "$Bin/../include", "/c/perl516/Perl64/site/lib";
use Path::Tiny;

my $DEBUG_LEVEL = 0;
my $cmd;
my @cmd_res_list;
my $out_file;
my $input;
my @files_find;
my @program_list;
my (@files_removed, @files_exist);
my $git_mode = 0;     # Default mode is "import all EXP files into an empty project" rather than "import only changed EXP files"
my $export_mode = 0;
my $tmp_dir;
my @codesys_config_para;
my @codesys_config_error;
my $COMMAND_TEMPLATE;
my $res;

sub rtrim { my $s = shift; $s =~ s/\s+$//; return $s };

# change list separator
$" = "\n";

# Find name of *.pro files
my @pro_file = glob("*.pro");
if (scalar(@pro_file) == 2)
{
  # In case an empty project is existing then put the *empty.pro into variable '$pro_file[0]'
  if ($pro_file[1] =~ /.+empty.pro/)
  {
    my $pro_temp = $pro_file[1];
    $pro_file[1] = $pro_file[0];
    $pro_file[0] = $pro_temp;
  }
  if ($pro_file[0] !~ /.+empty.pro/)
  {
    print @pro_file;
    print "\nCannot determine correct *.pro file!";
    exit 1;
  }
}
elsif (scalar(@pro_file) != 1)
{
 print @pro_file;
 print "\nCannot determine *.pro file!";
 exit 1;
}
else
{
  if ($pro_file[0] =~ /(.+?)[-_]*empty.pro/)
  {
    $pro_file[1] = "$1.pro";
  }
}

# If there is no empty project file default to Git mode
if ($pro_file[0] !~ /.+empty.pro/)
{
  $git_mode = 1;
}

# Eval Parameter
if ($#ARGV >= 0)
{
  $git_mode = 1 if ($ARGV[0] =~ m/^git$/i);
  $git_mode = 0 if ($ARGV[0] =~ m/^all$/i);
  $export_mode = 1 if ($ARGV[0] =~ m/^export$/i);
}

#
# Find codesys.exe
#

my $file_name = "Codesys.exe";
print "Codesys location:\n";
# Try to use Codesys environment variable
my $codesysfile = rtrim($ENV{CODESYS}) . "\\Codesys.exe";
$codesysfile =~ s/ /\\ /g;
if (-e $codesysfile)
{
  print "Using CODESYS environment variable: " . rtrim($ENV{CODESYS}) . "\n";
}
else
{
  # Try to use last stored location
  if (-e "codesysimport.dat")
  {
    local $/ = undef;
    open FILE, "codesysimport.dat" or die "Couldn't open file: $!";
    binmode FILE;
    $input = <FILE>;
    close FILE;
    chomp($input);
  }
  if (defined($input) && -e $input)
  {
    print "Stored location: $input\n";
    $codesysfile = $input;
  }
  else
  {
    # Search on drive C:\
    print "Search for Codesys on C:\\ ...\n";
    # First try to find in Tools folder
    if (-d "C:\\Tools")
    {
      $cmd = "where /R \"C:\\Tools\" \"$file_name\" 2>&1";
      print "$cmd\n" if ($DEBUG_LEVEL);
      @files_find = `$cmd`;
      @files_find = grep !/^INFO:/, @files_find ;
    }

    # Secondly try to find in Programs folders
    if (scalar @files_find == 0)
    {
      # Get list of folders on C:\
      $cmd = 'cmd /c dir /B /AD C:\\';
      @cmd_res_list = `$cmd`;
      chomp(@cmd_res_list);

      # Extract Program Files folders
      @program_list = grep { /program/i } @cmd_res_list;
      # Ignore ProgramData folder
      @program_list = grep { !/ProgramData/i } @program_list;

      # Prepend C:\ to each dir entry
      @program_list = map "C:\\$program_list[$_]", 0..$#program_list ;
      print "@program_list\n" if ($DEBUG_LEVEL);

      foreach my $folder (@program_list)
      {
        if (scalar @files_find == 0)
        {
          if (-d "$folder")
          {
            $cmd = "where /R \"$folder\" \"$file_name\" 2>&1";
            print "$cmd\n" if ($DEBUG_LEVEL);
            @files_find = `$cmd`;
            @files_find = grep !/^INFO:/, @files_find ;
          }
        }
      }
    }
    # Search on C:\
    if (scalar @files_find == 0)
    {
      $cmd = 'where /R C:\\ \"$file_name\" 2>&1';
      print "$cmd\n" if ($DEBUG_LEVEL);
      @files_find = `$cmd`;
      @files_find = grep !/^INFO:/, @files_find ;
    }

    chomp(@files_find);
    @files_find = sort @files_find;


    # change list separator
    $" = "\n";

    if (scalar @files_find == 0)
    {
      print "\nERROR:\n";
      print "Could not find Codesys.exe within the path provided by the CODESYS environment variable\n";
      print "Could not find Codesys.exe on drive C:\\ \n\n";
      exit(2);
    }
    else
    {
      print "@files_find\n" if (scalar @files_find > 1);
      # Use last found file (which is probably the latest version due to sort)
      print "Using: $files_find[$#files_find]\n";
      $codesysfile = $files_find[$#files_find];

      # Open codesysimport.dat file and write Codesys.exe file path
      open($out_file, "> :crlf", "codesysimport.dat") or die $!;
      print $out_file $codesysfile;
      close $out_file;
    }
  }
}

if ($git_mode && !$export_mode)
{
  # get list of changed files which have been changed in the work tree since the latest commit (HEAD)
  # (used to import changes coming from the Codesys Excel export)
  print("List of changed EXP files: ");
  $cmd = 'git diff --name-status HEAD -- exp/';
  @cmd_res_list = `$cmd`;
  # one or more files in the list
  if (scalar(@cmd_res_list) >= 1)
  {
    print("against HEAD: ");
  }
  # no changed files --> compare against origin/dev
  # (these are the changed EXP files resulting from the rebase)
  else
  {
    print("against origin/dev: ");
    $cmd = 'git diff --name-status origin/dev -- exp/';
    @cmd_res_list = `$cmd`;
    if (scalar(@cmd_res_list) == 0)
    {
      print "\nNo changed EXP files found!";
      exit 1;
    }
  }

  # Replace slash by backslash in git diff output
  s/\//\\/ for @cmd_res_list;
  # Remove files with status 'deleted' - there is no macro command to delete objects
  for (@cmd_res_list)
  {
    $_ =~ /^(\w)\s+(.*)/;
    if ($1 eq "D")
    {
      push @files_removed, $2;
    } else {
      push @files_exist, $2;
    }
  }
  @cmd_res_list = @files_exist;
  print "Found " . scalar @cmd_res_list . " files\n\n@cmd_res_list\n";
  foreach (@files_removed)
  {
    print "Warning: File has been removed! Please manually delete objects from: $_\n";
  }
}
elsif (!$export_mode)
{
  # import all mode: import whole exp\ folder
  print("Get list of EXP files: ");
  $cmd = 'cmd /c dir /B exp\\*.exp';
  @cmd_res_list = `$cmd`;
  if (scalar(@cmd_res_list) == 0)
  {
    print "No EXP files found in ./exp/ !\n";
    exit(1);
  }
  # remove newlines from file list
  chomp(@cmd_res_list);
  # add directory "exp\" in front of each line
  s/^/exp\\/ for @cmd_res_list;
  print "\n\n@cmd_res_list\n\nFound " . scalar @cmd_res_list . " files";
}

if (!$export_mode)
{
  # Check for "*_para.exp" and "*_error.exp"
  # (PRM_TS.EXP or PRM_E.EXP would e.g. otherwise overwrite changes coming from the Codesys Excel file in *_para.exp)
  # Remove potential _para.exp
  @codesys_config_para = grep { $_ =~ /_para.exp$/ } @cmd_res_list;
  $codesys_config_para[0] = "" if (!defined $codesys_config_para[0]);
  @cmd_res_list = grep { $_ !~ /_para.exp$/ } @cmd_res_list;
  $codesys_config_para[0] = "project import " . $codesys_config_para[0] if ($codesys_config_para[0] ne "");
  # Remove potential _para.exp
  @codesys_config_error = grep { $_ =~ /_error.exp$/ } @cmd_res_list;
  $codesys_config_error[0] = "" if (!defined $codesys_config_error[0]);
  @cmd_res_list = grep { $_ !~ /_error.exp$/ } @cmd_res_list;
  $codesys_config_error[0] = "project import " . $codesys_config_error[0] if ($codesys_config_error[0] ne "");
}

# Determine right *.pro file to use
my $project_file = $pro_file[0];

if (scalar(@pro_file) == 2)
{
  # In case of Git mode use the full project file for the update process
  if ($git_mode || $export_mode)
  {
    $project_file = $pro_file[1];
  }
  else
  {
    # Create backup of empty project file
    if ($project_file =~ /.+empty.pro/)
    {
      #print "copy \"$project_file\" \"$project_file.bak\"";
      $res = system "copy \"$project_file\" \"$project_file.bak\" >nul";
    }
  }
  # Make backup copy of original project file
  #print "copy \"$pro_file[1]\" \"$pro_file[1].bak\"";
  $res = system "copy \"$pro_file[1]\" \"$pro_file[1].bak\" >nul";
}
else
{
  # Make backup copy of original project file
  #print "copy \"$pro_file[0]\" \"$pro_file[0].bak\"";
  $res = system "copy \"$pro_file[0]\" \"$pro_file[0].bak\" >nul";
}

# (Note: Parameter "/batch" makes the call to Codesys.exe invisible)
#$cmd = '"' . $codesysfile . '" ' . $project_file . " /noinfo /cmd codesysimport.lst";
#$cmd = '"' . $codesysfile . '" ' . $project_file . " /noinfo /cmd codesysimport.lst /show icon";
$cmd = '"' . $codesysfile . '" ' . $project_file . " /cmd codesysimport.lst /batch";

print("\nCommand line: $cmd\n");

# While loop to import EXP files in smaller slices because of a potential Codesys bug
print("\nCalling CoDeSys ...");

my $export_chunk_size = 200;
my $initial_size = scalar @cmd_res_list;
my @import_list;
my $import_running = 1;
while (((scalar @cmd_res_list > 0) && $import_running) || $export_mode)
{
  if ($export_mode)
  {
    # prepare codesysimport.lst file template
    $COMMAND_TEMPLATE = qq|project expmul exp/|;
    # end while loop after export
    $export_mode = 0;
  }
  else
  {
    # git mode and all mode

    if ($git_mode || ($export_chunk_size < $initial_size))
    {
      # Import in smaller chunks:
      # Create temporary dir
      $tmp_dir = Path::Tiny->tempdir( CLEANUP => 1, TEMPLATE => "exp-import-XXXX" );
      # Slice a part of the file list
      @import_list = splice @cmd_res_list, 0, $export_chunk_size;
      # Copy EXP files to temporary folder
      foreach (@import_list)
      {
        path($_)->copy("$tmp_dir/");
      }
    }
    else
    {
      @import_list = @cmd_res_list;
      $import_running = 0;
    }
    # prepare codesysimport.lst file template
    $COMMAND_TEMPLATE = qq|; save import log ;(only possible when not called in /batch mode)
file close
file open $project_file
;;out open bdimport.log
;;out clear
replace yesall
<project import FILELIST>
<project import PARA>
<project import ERROR>
;;project rebuild
; close import log file
;;out close
file save
project expmul exp/
file quit|;

    # insert import statements into file template
    if ($git_mode || ($export_chunk_size < $initial_size))
    {
      $COMMAND_TEMPLATE =~ s/<project import FILELIST>/project import $tmp_dir\\*.exp/;
    }
    else
    {
      $COMMAND_TEMPLATE =~ s/<project import FILELIST>/project import exp\\*.exp/;
    }
    # insert Bodas-config parameter import statement into file template
    $COMMAND_TEMPLATE =~ s/<project import PARA>/$codesys_config_para[0]/;
    # insert Bodas-config error import statement into file template
    $COMMAND_TEMPLATE =~ s/<project import ERROR>/$codesys_config_error[0]/;
    # export only in last step
    if (scalar @cmd_res_list > $export_chunk_size)
    {
      $COMMAND_TEMPLATE =~ s/project expmul exp\//;project expmul exp\//;
    }
  }

  # Delete macro file and then write a new fresh file
  unlink "codesysimport.lst" if (-e "codesysimport.lst");
  # Open codesysimport.lst file and write macro code
  open($out_file, "> :crlf", "codesysimport.lst") or die $!;
  print $out_file $COMMAND_TEMPLATE;
  close $out_file;

  #
  # call CoDeSys with project name and macro file
  #
  print("_");
  # (Note: 'exec' ends after call, 'system' waits until call ends)
  #my $res = system "cmd /C $cmd";
  $res = system "$cmd";
  print("\b.");
}

# display hint
print("\n\nCreated EXP files.\n");

# Restore empty project file from backup
if (!($git_mode || $export_mode))
{
  if ($project_file =~ /.+empty.pro/)
  {
    # Copy imported file to replace original project file
    #print "copy \"$project_file\" \"$pro_file[1]\"";
    $res = system "copy \"$project_file\" \"$pro_file[1]\" >nul";
    # Restore empty project file
    #print "copy \"$project_file.bak\" \"$project_file\"";
    $res = system "copy \"$project_file.bak\" \"$project_file\" >nul";
    # Delete empty project file backup
    #print "del \"$project_file.bak\"";
    $res = system "del \"$project_file.bak\" >nul";
  }
}
