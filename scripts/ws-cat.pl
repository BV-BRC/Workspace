
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::ScriptHelpers;
use Text::Table;
use Bio::KBase::AuthToken;
use LWP::UserAgent;

=head1 NAME

ws-cat

=head1 SYNOPSIS

ws-cat path [path...]

=head1 DESCRIPTION

Dump the contents of the given path to stdout. If the --shock flag is given,
retrieve the contents of shock-based files.

=head1 COMMAND-LINE OPTIONS

ws-cat.pl [-h] [long options...] path [path...]
	--url       Service URL
	--shock     Retrieve data stored in Shock
	-h --help   Show this usage message
=cut

my @options = (["url=s", 'Service URL'],
	       ["shock", "Retrieve data stored in Shock"],
	       ["help|h", "Show this usage message"]);

my($opt, $usage) = describe_options("%c %o path [path...]",
				    @options);

print($usage->text), exit if $opt->help;

my $ws = Bio::P3::Workspace::ScriptHelpers::wsClient($opt->url);

my @paths = @ARGV;

my $res = $ws->get({ objects => \@paths });

my $token;
my $cb;
my $ua;

if ($opt->shock)
{
    $token = Bio::KBase::AuthToken->new();

    $cb = sub {
	my($data) = @_;
	print $data;
    };
    $ua = LWP::UserAgent->new();
}

for my $ent (@$res)
{
    my($meta, $data) = @$ent;

    if ((my $url = $meta->[11]) && $opt->shock)
    {
	my $res = $ua->get("$url?download",
			   Authorization => "OAuth " . $token->token,
			   ':content_cb' => $cb);
    }
    else
    {
	print $data;
    }
}
