use strict;

=head1 Copy files between local computer and PATRIC workspace

    p3-cp [options] source dest
    p3-cp [options] source... directory
    p3-cp [options] -t directory source...

Copy source to dest, or multiple source(s) to directory.

Source and destination file and directories may either be files local 
to the current computer or in the PATRIC workspace. Names in the workspace
are denoted with a ws: prefix.

=head1 Usage synopsis

    p3-cp [options] source dest
    p3-cp [options] source... directory
    p3-cp [options] -t directory source...

Copy source to dest, or multiple source(s) to directory.

Source and destination file and directories may either be files local 
to the current computer or in the PATRIC workspace. Names in the workspace
are denoted with a ws: prefix.

The following options may be provided:

    -r or --recursive	           If source is a directory, copies the directory and its contents.
				   If source ends in /, copy the contents of the directory.
    --workspace-path-prefix STR	   Prefix for relative workspace pathnames specified with ws: 
    -f or --overwrite		   If a file to be uploaded already exists, overwrite it.
    
=cut

my($opt, $usage) = describe_options("%c %o source dest",
	["overwrite|f", "Overwrite existing destination object"],
	["recursive|r", "Copy all directory contents"],
    
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