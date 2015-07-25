
use strict;
use Bio::P3::Workspace::ScriptHelpers;

=head1 NAME

ws-cp

=head1 SYNOPSIS

ws-cp file ws:<workspace-path>

ws-cp ws:<workspace-path> file

=head1 DESCRIPTION

Copy a file into or out of the workspace.

=head1 COMMAND-LINE OPTIONS

ws-cp [-h] [long options...]
	--url       Service URL
	-h --help   Show this usage message
=cut

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o <source> <destination>",[
	["overwrite|o", "Overwirte existing destination object"],
	["recursive|r", "Copy all directory contents"],
	["move|m", "Perform a move rather than a copy"]
]);
my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths([$ARGV[0],$ARGV[1]]);
my $res = Bio::P3::Workspace::ScriptHelpers::wscall("copy",{
	objects => [$paths],
	overwrite => $opt->overwrite,
	recursive => $opt->recursive,
	move => $opt->move
});
print "Files copied to new destinations:\n";
Bio::P3::Workspace::ScriptHelpers::print_wsmeta_table($res);