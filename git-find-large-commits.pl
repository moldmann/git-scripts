#!/usr/bin/perl
# Adapted from https://stackoverflow.com/questions/1314950/git-get-all-commits-and-blobs-they-created/1318854#1318854

foreach my $rev (`git rev-list --all --pretty=oneline`) {
  my $tot = 0;
  ($sha = $rev) =~ s/\s.*$//;
  foreach my $blob (`git diff-tree -r -c -M -C --no-commit-id $sha`) {
    $blob = (split /\s/, $blob)[3];
    next if $blob == "0000000000000000000000000000000000000000"; # Deleted
    my $size = `echo $blob | git cat-file --batch-check`;
    $size = (split /\s/, $size)[2];
    $tot += int($size);
  }
  # Show commits > 1MiB
  if ($tot > 1000000)
  {
    $tot /= 1000000;
    printf('%.1f MB %s', $tot, $rev);
  }
}