use inc::Module::Install;

abstract('Service Level Agreements for RT');
RTx ('RT-Extension-SLA');
all_from('lib/RT/Extension/SLA.pm');
license('gpl2');

build_requires('Test::More');

requires('Business::Hours');
auto_install();

my ($lp) = ($INC{'RT.pm'} =~ /^(.*)[\\\/]/);
my $lib_path = join( ' ', "$RT::LocalPath/lib", $lp );
my $sbin_path = $RT::SbinPath || "$RT::BasePath/sbin" || "/opt/rt3/sbin";
my $bin_path = $RT::BinPath || "$RT::BasePath/bin" || "/opt/rt3/bin";

substitute(
    {
        RT_LIB_PATH  => $lib_path,
        RT_BIN_PATH  => $bin_path,
        RT_SBIN_PATH => $sbin_path,
    },
    qw(t/utils.pl),
);

WriteAll();
