
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
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

my @options = (["help|h", "Show this usage message"]);

my($opt, $usage) = describe_options("%c %o url",
				    @options);

print($usage->text), exit if $opt->help;

Bio::P3::Workspace::ScriptHelpers::wsURL($ARGV[0]);
print "Reset URL to:\n".Bio::P3::Workspace::ScriptHelpers::wsURL()."\n";