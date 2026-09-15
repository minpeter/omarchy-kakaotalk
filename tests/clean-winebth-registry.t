use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);

my $dir = tempdir(CLEANUP => 1);
my $script = "$FindBin::Bin/../tools/clean-winebth-registry.pl";
my $counter = 0;
sub write_file {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die $!;
    print {$fh} $data or die $!;
    close $fh or die $!;
}
sub read_file {
    open my $fh, '<:raw', $_[0] or die $!;
    local $/;
    return <$fh>;
}
sub run_cleaner {
    my ($source, $destination) = @_;
    my $error = gensym;
    my $pid = open3(undef, my $out, $error, $^X, $script, $source, $destination);
    local $/;
    my $stdout = <$out> // '';
    my $stderr = <$error> // '';
    waitpid($pid, 0);
    return ($? >> 8, $stdout . $stderr);
}
my $before = <<'REG';
WINE REGISTRY Version 2
;; All keys relative to \\Machine

[Software\\Keep] 123
"Text"="WINEBTH should stay in a value"

REG
my $removed = <<'REG';
[System\\ControlSet001\\Enum\\WINEBTH] 123
"Value"="remove root"

[System\\ControlSet001\\Enum\\WINEBTH\\Device\\Properties] 123
"Data"=hex:01,02,\
  03,04

REG
my $after = <<'REG';
[System\\ControlSet001\\Enum\\WINEBTH_OTHER] 123
"Keep"="lookalike"

[System\\ControlSet002\\Enum\\WINEBTH] 123
"Keep"="different control set"

[System\\ControlSet001\\Services\\winebth] 123
"Start"=dword:00000003
"Other"="preserved"

[Software\\Last] 123
"Start"=dword:00000002
REG
my $original = $before . $removed . $after;
my $expected = $before . $after;
$expected =~ s/dword:00000003/dword:00000004/;

for my $crlf (0, 1) {
    my ($input, $want) = ($original, $expected);
    if ($crlf) { s/\n/\r\n/g for ($input, $want); }
    my $source = "$dir/source-" . ++$counter;
    my $dest = "$dir/output-$counter";
    write_file($source, $input);
    my ($status, $message) = run_cleaner($source, $dest);
    is($status, 0, "successful cleanup (CRLF=$crlf)");
    like($message, qr/Removed 2 WINEBTH sections/, 'counts removed sections');
    is(read_file($dest), $want, 'only intended tree and service value changed');
    is(read_file($source), $input, 'source unchanged');
    is((stat($dest))[2] & 0777, 0600, 'output private');
    is((run_cleaner($dest, "$dest-again"))[0], 0, 'already-clean input accepted');
    is(read_file("$dest-again"), $want, 'idempotent result');
    isnt((run_cleaner($source, $dest))[0], 0, 'existing output refused');
    is(read_file($dest), $want, 'existing output preserved');
    isnt((run_cleaner($source, $source))[0], 0, 'in-place editing refused');
    is(read_file($source), $input, 'in-place refusal preserves source');
}

my $bad_start = $original;
$bad_start =~ s/"Start"=dword:00000003/"Start"="3"/;
my $duplicate = $original;
$duplicate =~ s/"Start"=dword:00000003/"Start"=dword:00000003\n"Start"=dword:00000002/;
my $missing = $original;
$missing =~ s/"Start"=dword:00000003\n//;
for my $case (
    ['wrong file type', "REGEDIT4\n$original"],
    ['missing service value', $missing],
    ['malformed service value', $bad_start],
    ['duplicate service value', $duplicate],
    ['malformed header in removed tree', $before . $removed . "[bad header\n" . $after],
) {
    my ($name, $input) = @$case;
    my $source = "$dir/source-" . ++$counter;
    my $dest = "$dir/output-$counter";
    write_file($source, $input);
    isnt((run_cleaner($source, $dest))[0], 0, "$name rejected");
    ok(!-e $dest, "$name leaves no destination");
    is(read_file($source), $input, "$name preserves source");
}
my $source = "$dir/source-symlink-test";
write_file($source, $original);
symlink($source, "$dir/source-link") or die $!;
isnt((run_cleaner("$dir/source-link", "$dir/link-result"))[0], 0, 'source symlink refused');
symlink("$dir/nonexistent", "$dir/dangling") or die $!;
isnt((run_cleaner($source, "$dir/dangling"))[0], 0, 'dangling output symlink refused');
ok(-l "$dir/dangling", 'output symlink preserved');
isnt((run_cleaner("$dir/missing", "$dir/missing-result"))[0], 0, 'missing source refused');
isnt((run_cleaner($source, "$dir/missing-directory/output"))[0], 0, 'missing output directory refused');
my @leftovers = glob "$dir/.winebth-clean-*";
is(scalar @leftovers, 0, 'no partial temporary files remain');
done_testing;
