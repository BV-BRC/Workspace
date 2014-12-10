
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::ScriptHelpers;
use Text::Table;
=head1 NAME

ws-create

=head1 SYNOPSIS

ws-create ws-name

=head1 DESCRIPTION

Create a workspace

=head1 COMMAND-LINE OPTIONS

ws-create workspace [long options...]
	--url      URL to use for workspace service
	--help     print usage message and exit
	
=cut

my @options = (["url=s", 'Service URL'],
	       ["help|h", "Show this usage message"]);

my($opt, $usage) = describe_options("%c %o ws-name",
				    @options);

my $name = shift;

print($usage->text), exit if $opt->help;

my $ws = Bio::P3::Workspace::ScriptHelpers::wsClient($opt->url);

my $wslist = $ws->create_workspace({ workspace => $name });
my $table = Text::Table->new(
	"Name","Owner","Type","Moddate","Size","User perm","Global perm",
);
my $tbl = [[$wslist->[1],$wslist->[2],"Workspace",$wslist->[3],$wslist->[4],$wslist->[5],$wslist->[6]]];
$table->load(@{$tbl});
print $table."\n";
