#!/usr/bin/perl
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Chris Kearney and the SiliconForest contributors

use strict;
use warnings;
use Archive::Tar;
use Digest::SHA qw(sha256_hex);
use File::Temp qw(tempfile);

my ($slot, $destination) = @ARGV;
die "usage: $0 SLOT FIRMWARE_DIRECTORY\n" unless @ARGV == 2;
my $header_size = 4096;
my $slot_size = 32 * 1024 * 1024;
open my $input, '<:raw', $slot or die "open firmware slot: $!";
die "wrong firmware slot size\n" unless -s $input == $slot_size;
my $header;
die "short firmware header\n" unless read($input, $header, $header_size) == $header_size;
exit 3 if $header eq "SFFWSLOT1\n" . ("\0" x ($header_size - 10));
my ($length, $digest) = $header =~ /\ASFFWSLOT1\nlength=([1-9][0-9]{0,7})\nsha256=([0-9a-f]{64})\n\0+\z/;
die "invalid firmware header\n" unless defined $length && $length <= $slot_size - $header_size;
my $data;
die "short firmware payload\n" unless read($input, $data, $length) == $length;
die "firmware payload digest mismatch\n" unless sha256_hex($data) eq $digest;
open my $payload, '<', \$data or die "open firmware payload: $!";
my $archive = Archive::Tar->new;
$archive->read($payload, 0) or die "invalid firmware archive\n";

# Validate the whole archive before touching the destination. Resolve hard links
# to earlier archive members in memory. Never extract tar paths or links directly.
my %contents;
for my $member ($archive->get_files) {
    my $name = $member->full_path;
    die "invalid firmware path: $name\n"
        unless $name =~ m{\A(?:brcm/|apple/(?:dfrmtfw-|tpmtfw-))[A-Za-z0-9_+.(),@ -]+\z}
        && $name !~ m{/\.{1,2}\z};
    die "duplicate firmware path: $name\n" if exists $contents{$name};
    if ($member->is_file) {
        $contents{$name} = $member->get_content;
    } elsif ($member->is_hardlink && exists $contents{$member->linkname}) {
        $contents{$name} = $contents{$member->linkname};
    } else {
        die "unsupported firmware archive member: $name\n";
    }
}
die "empty firmware archive\n" unless keys %contents;

die "unsafe firmware directory\n" if -l $destination || !-d $destination;
for my $subdir ('apple', 'brcm') {
    my $path = "$destination/$subdir";
    die "unsafe firmware subdirectory: $path\n" if -l $path || !-d $path;
}
for my $name (sort keys %contents) {
    my ($subdir) = split('/', $name);
    my ($file, $temporary) = tempfile('.sf-firmware-XXXXXXXX',
        DIR => "$destination/$subdir", UNLINK => 1);
    binmode $file;
    print {$file} $contents{$name} or die "write $name: $!";
    close $file or die "close $name: $!";
    chmod 0644, $temporary or die "chmod $name: $!";
    rename $temporary, "$destination/$name" or die "install $name: $!";
}
print "Installed ", scalar(keys %contents), " firmware files\n";
