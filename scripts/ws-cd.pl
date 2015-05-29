
use strict;
use Bio::P3::Workspace::ScriptHelpers;

=head1 NAME

ws-url

=head1 SYNOPSIS

ws-url path [path...]

=head1 DESCRIPTION

List the contents of a workspace directory.

=head1 COMMAND-LINE OPTIONS

ws-url url [long options...]
	--help          print usage message and exit

=cut

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o <directory>",[]);
if (!defined($ARGV[0])) {
	print "Current directory:\n".Bio::P3::Workspace::ScriptHelpers::directory()."\n";
	exit();
}
my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths([$ARGV[0]]);
my $dir = Bio::P3::Workspace::ScriptHelpers::directory($paths->[0]);
print "Reset current workspace directory to:\n".$dir."\n";