# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors
# Read-only metadata listing of a root filesystem, for release/image/tools/classify.py. One walk,
# lstat only, no file contents read; stays on the root device; extra directories to skip are
# given in SF_LIST_PRUNE (colon-separated). Runs on the Perl of a SiliconForest root:
#   ssh <machine> 'nice -n 15 perl -' < list-meta.pl > meta.tsv
# type<TAB>mode<TAB>uid<TAB>gid<TAB>size<TAB>mtime<TAB>nlink<TAB>ino<TAB>path<TAB>link target
use strict; use File::Find;
my %prune = map { $_ => 1 } ('/dev', split(/:/, $ENV{SF_LIST_PRUNE} // ''));
sub esc { my $s = shift; $s =~ s/([\\\t\n\r])/sprintf("\\x%02x", ord($1))/ge; $s }
my $rootdev = (lstat('/'))[0];
find({ no_chdir => 1, wanted => sub {
  my $p = $File::Find::name; my @s = lstat($p); return unless @s;
  my $t = -l _ ? 'l' : -d _ ? 'd' : -f _ ? 'f' : -p _ ? 'p' : -S _ ? 's' : -b _ ? 'b' : -c _ ? 'c' : '?';
  my $l = $t eq 'l' ? readlink($p) : '';
  if ($prune{$p} || ($t eq 'd' && $s[0] != $rootdev)) { $File::Find::prune = 1; $t = 'D'; }
  printf "%s\t%04o\t%d\t%d\t%d\t%d\t%d\t%d\t%s\t%s\n", $t, $s[2] & 07777, $s[4], $s[5], $s[7], $s[9], $s[3], $s[1], esc($p), esc($l);
} }, '/');
