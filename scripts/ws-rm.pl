
use strict;
use Bio::P3::Workspace::ScriptHelpers;
=head1 NAME

ws-create

=head1 SYNOPSIS

ws-create ws-name

=head1 DESCRIPTION

Create a workspace

=head1 COMMAND-LINE OPTIONS

ws-rm path [long options...]
	--url      URL to use for workspace service
	--help     print usage message and exit
	
=cut

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o <path>",[
	["recursive|r", "Delete directories recursively"],
	["force|f", "Delete directories"]
]);

if (@ARGV == 0)
{
    exit;
}

my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths(\@ARGV);
my $res = Bio::P3::Workspace::ScriptHelpers::wscall("delete",{
	objects => $paths,
	force => $opt->force,
	deleteDirectories => $opt->recursive
});
print "Files deleted:\n";
Bio::P3::Workspace::ScriptHelpers::print_wsmeta_table($res);
