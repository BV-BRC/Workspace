
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
=head1 NAME

ws-create

=head1 SYNOPSIS

ws-create ws-name

=head1 DESCRIPTION

Create a workspace

=head1 COMMAND-LINE OPTIONS

rast-annotate-proteins-kmer-v2 [-io] [long options...] < input > output
	-i --input      file from which the input is to be read
	-o --output     file to which the output is to be written
	--help          print usage message and exit
	--min-hits      minimum number of Kmer hits required for a call to be
	                made
	--max-gap       maximum size of a gap allowed for a call to be made

=cut

my @options = (["url", 'Service URL'],
	       ["help|h", "Show this usage message"],
	      );

my($opt, $usage) = describe_options("%c %o ws-name",
				    @options);

my $name = shift;

print($usage->text), exit if $opt->help;

my $ws = Bio::P3::Workspace::WorkspaceClient->new($opt->url);

my $r = $ws->create_workspace({ workspace => $name });
print Dumper($r);
