use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);

sub read_file {
    open my $fh, '<:raw', $_[0] or die $!;
    local $/;
    return <$fh>;
}
sub write_file {
    my ($path, $data) = @_;
    open my $fh, '>:raw', $path or die $!;
    print {$fh} $data or die $!;
    close $fh or die $!;
}

chdir "$FindBin::Bin/.." or die $!;
my $doc = read_file('docs/troubleshooting.md');
my @blocks = $doc =~ /^```bash\n(.*?)^```/msg;
my @apply = grep { /mv -T .*system\.reg/ } @blocks;
is(scalar @apply, 1, 'exactly one documented install block');
@apply == 1 or BAIL_OUT('cannot identify install block');
my $block = $apply[0];
# Only target paths and the Wine-server binary are replaced; the actual
# documented validation, generation, comparison and installation are exercised.
is(($block =~ s/^bottle=.*$/bottle="\$1"/m), 1, 'replace live prefix with test argument');
is(($block =~ s/^backup_dir=.*$/backup_dir="\$2"/m), 1, 'replace backup with test argument');
is(($block =~ s/^wineserver_bin=.*$/wineserver_bin="\/usr\/bin\/true"/m), 1, 'stub Wine shutdown');
$block !~ /\$HOME|\.local\/share\/bottles/ or BAIL_OUT('live path remains in test');

my $original = <<'REG';
WINE REGISTRY Version 2

[System\\ControlSet001\\Enum\\WINEBTH] 123
"Cached"="remove this"

[System\\ControlSet001\\Services\\winebth] 123
"Start"=dword:00000003

[Software\\Keep] 123
"Data"="preserve this"
REG
my $cleaned = <<'REG';
WINE REGISTRY Version 2

[System\\ControlSet001\\Services\\winebth] 123
"Start"=dword:00000004

[Software\\Keep] 123
"Data"="preserve this"
REG
my $different = $cleaned;
$different =~ s/preserve this/incorrect value/;
my $invalid = "WINE REGISTRY Version 2\n\n[Software\\\\Keep] 123\n";

for my $case (
    ['valid candidate', $original, $original, $cleaned, 1],
    ['empty candidate', $original, $original, '', 0],
    ['truncated candidate', $original, $original, substr($cleaned, 0, 40), 0],
    ['valid but different candidate', $original, $original, $different, 0],
    ['original changed since backup', $original . "\n;changed\n", $original, $cleaned, 0],
    ['regeneration fails', $invalid, $invalid, $cleaned, 0],
) {
    my ($name, $current, $backup_data, $candidate, $success) = @$case;
    subtest $name => sub {
        my $dir = tempdir('kakaotalk-apply-XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
        my $prefix = "$dir/bottle with spaces";
        my $backup = "$dir/backup with spaces";
        make_path($prefix, "$backup/KakaoTalk");
        write_file("$prefix/system.reg", $current);
        write_file("$backup/KakaoTalk/system.reg", $backup_data);
        write_file("$backup/system.reg.cleaned", $candidate);
        my $error = gensym;
        my $pid = open3(undef, my $out, $error, 'bash', '-c', $block, 'review', $prefix, $backup);
        my ($stdout, $stderr);
        { local $/; $stdout = <$out> // ''; $stderr = <$error> // ''; }
        waitpid($pid, 0);
        my $status = $?;
        if ($success) {
            is($status, 0, 'installation succeeds') or diag "$stdout$stderr";
            is(read_file("$prefix/system.reg"), $cleaned, 'installs correct regenerated content');
            is((stat("$prefix/system.reg"))[2] & 0777, 0600, 'installed registry is private');
        } else {
            isnt($status, 0, 'installation refused');
            is(read_file("$prefix/system.reg"), $current, 'live-path fixture unchanged');
        }
        is(read_file("$backup/KakaoTalk/system.reg"), $backup_data, 'backup unchanged');
        is(read_file("$backup/system.reg.cleaned"), $candidate, 'reviewed candidate unchanged');
        opendir my $dh, $prefix or die $!;
        my @staging = grep { /^\.system\.reg\.winebth-/ } readdir $dh;
        closedir $dh;
        is(scalar @staging, 0, 'staging directory cleaned');
        done_testing;
    };
}
done_testing;
