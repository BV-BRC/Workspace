
use strict;
use Bio::P3::Workspace::ScriptHelpers;
use LWP::UserAgent;
use P3AuthToken;

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

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o path [path...]",[
	["shock", "Retrieve data stored in Shock"]
]);
my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths([@ARGV]);
my $res = Bio::P3::Workspace::ScriptHelpers::wscall("get",{ objects => $paths });

my $cb;
my $ua;

if ($opt->shock)
{
    $cb = sub {
	my($data) = @_;
	print $data;
    };
    $ua = LWP::UserAgent->new();
}

my $token = P3AuthToken->new();

for my $ent (@$res)
{
    my($meta, $data) = @$ent;

    if ((my $url = $meta->[11]) && $opt->shock)
    {
	my $res = $ua->get("$url?download",
			   Authorization => "OAuth " . $token->token(),
			   ':content_cb' => $cb);
    }
    else
    {
	print $data."\n";
    }
}
