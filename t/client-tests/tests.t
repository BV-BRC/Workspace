use FindBin qw($Bin);
use Bio::P3::Workspace::WorkspaceTests;

my $tester = Bio::P3::Workspace::WorkspaceTests->new($bin);
$tester->run_tests();