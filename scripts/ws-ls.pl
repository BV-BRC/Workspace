
use strict;
use Bio::P3::Workspace::ScriptHelpers;

=head1 NAME

ws-ls

=head1 SYNOPSIS

ws-ls path [path...]

=head1 DESCRIPTION

List the contents of a workspace directory.

=head1 COMMAND-LINE OPTIONS

ws-ls path [long options...]
	--url      URL to use for workspace service
        --shock    Include Shock URLs
	--help     print usage message and exit

=cut

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o <path>",[
	["recursive|r", "Recursively list subdirectory contents"],
	["shock|s", "Include shock URLs"],
]);
my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths([@ARGV]);
my $res = Bio::P3::Workspace::ScriptHelpers::wscall("ls",{
	paths => $paths,
	recursive => $opt->recursive
});
for my $p (@{$paths}) {
    my $x = $res->{$p};
    print "\n$p:\n" if @{$paths} > 1;
    Bio::P3::Workspace::ScriptHelpers::print_wsmeta_table($x,$opt->shock);
}
