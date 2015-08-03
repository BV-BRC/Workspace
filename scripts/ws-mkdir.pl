
use strict;
use Bio::P3::Workspace::ScriptHelpers;

=head1 NAME

ws-mkdir

=head1 SYNOPSIS

ws-mkdir path [path ...]

=head1 DESCRIPTION

Create a directory in the workspace.

=head1 COMMAND-LINE OPTIONS

rast-annotate-proteins-kmer-v2 [-io] [long options...] < input > output
	-i --input      file from which the input is to be read
	-o --output     file to which the output is to be written
	--help          print usage message and exit
	--min-hits      minimum number of Kmer hits required for a call to be
	                made
	--max-gap       maximum size of a gap allowed for a call to be made

=cut

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o <path> [<path> ...]",[
	["permission|p:s", "Permissions for folders created"]
]);
my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths([@ARGV]);
my $input = {
	objects => [],
	permission => $opt->permission,
	overwrite => 0
};
for (my $i=0; $i < @{$paths}; $i++) {
	push(@{$input->{objects}},[$paths->[$i],"folder",{}]);
}
my $res = Bio::P3::Workspace::ScriptHelpers::wscall("create",$input);
print "Folders created:\n";
Bio::P3::Workspace::ScriptHelpers::print_wsmeta_table($res);
