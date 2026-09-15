#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Temp;

# Offline transformer only: use a stopped prefix's BACKUP as SOURCE.
# Never starts Wine, edits SOURCE, or installs the result into a prefix.
@ARGV == 2 or die "usage: perl $0 SOURCE NEW_OUTPUT\n";
my ($source, $destination) = @ARGV;
-f $source && !-l $source or die "source must be a regular, non-symlink file\n";
!(-e $destination || -l $destination) or die "output already exists; refusing overwrite\n";
open my $input, '<:raw', $source or die "open source: $!\n";
my $header = <$input>;
defined($header) && $header =~ /\AWINE REGISTRY Version 2\r?\n\z/
    or die "not a Wine REGISTRY Version 2 file\n";

# Keep incomplete output private; publish only after validation, without overwrite.
my $output = File::Temp->new(
    TEMPLATE => '.winebth-clean-XXXXXXXX', DIR => dirname($destination), UNLINK => 1,
);
binmode $output or die "binmode: $!\n";
print {$output} $header or die "write header: $!\n";
my ($skip, $service, $removed_keys, $removed_bytes, $starts) = (0) x 5;
my $kept = length $header;
my $bluetooth = lc 'System\\ControlSet001\\Enum\\WINEBTH';
my $service_key = lc 'System\\ControlSet001\\Services\\winebth';
# Wine's on-disk key names escape each backslash as two backslashes.
$bluetooth =~ s/\\/\\\\/g;
$service_key =~ s/\\/\\\\/g;

while (my $line = <$input>) {
    if ($line =~ /^\[/) {
        $line =~ /^\[(.*)\](?: [0-9]+)?\r?\n?\z/
            or die "malformed section header; no output installed\n";
        my $key = lc $1;
        $skip = $key eq $bluetooth || index($key, $bluetooth . '\\\\') == 0;
        $service = $key eq $service_key;
        $removed_keys++ if $skip;
    }
    if ($skip) {
        $removed_bytes += length $line;
        next;
    }
    if ($service && $line =~ /^"Start"\s*=/i) {
        $line =~ /^"Start"=dword:[0-9a-fA-F]{8}(\r?\n|\z)/i
            or die "unexpected winebth Start format; no output installed\n";
        my $ending = $1;
        $line =~ s/dword:[0-9a-fA-F]{8}\Q$ending\E\z/dword:00000004$ending/i;
        $starts++;
    }
    print {$output} $line or die "write: $!\n";
    $kept += length $line;
}
eof($input) or die "read source: $!\n";
close $input or die "close input: $!\n";
$starts == 1 or die "expected exactly one winebth service Start value (found $starts)\n";
close $output or die "close output: $!\n";
link($output->filename, $destination) or die "publish output without overwrite: $!\n";
printf "Removed %d WINEBTH sections (%d bytes); winebth Start=4; retained %d bytes\n",
    $removed_keys, $removed_bytes, $kept;
