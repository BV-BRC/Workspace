
use strict;
use Bio::P3::Workspace::ScriptHelpers;
use Bio::P3::Workspace::Utils;

=head1 NAME

ws-mkdir

=head1 SYNOPSIS

ws-mkdir path [path ...]

=head1 DESCRIPTION

Create a directory in the workspace.

=head1 COMMAND-LINE OPTIONS


=cut

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o <path> [<path> ...]",[
	["permission|p", "Permissions for folders created"],
]);
my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths([@ARGV]);
my $input = {
	objects => [],
	permission => $opt->permission,
	overwrite => 0
};
for my $path (@ARGV)
{
    push(@{$input->{objects}},[$path, "folder"]);
}
my $res = Bio::P3::Workspace::ScriptHelpers::wscall("create",$input);
print "Folders created:\n";
Bio::P3::Workspace::ScriptHelpers::print_wsmeta_table($res);
