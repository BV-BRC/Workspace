use FindBin qw($Bin);
use Bio::ModelSEED::ProbModelSEED::ProbModelSEEDTests;

my $tester = Bio::P3::Workspace::WorkspaceTests->new($bin);
$tester->run_tests();