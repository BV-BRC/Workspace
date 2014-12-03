
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
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

my @options = (
	       ["url", 'Service URL'],
	       ["help|h", "Show this usage message"],
	      );

my($opt, $usage) = describe_options("%c %o",
				    @options);

print($usage->text), exit if $opt->help;

my $ws = Bio::P3::Workspace::WorkspaceClient->new($opt->url);

