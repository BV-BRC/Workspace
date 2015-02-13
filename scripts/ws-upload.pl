
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::ScriptHelpers;
use Text::Table;
use Bio::KBase::AuthToken;
use LWP::UserAgent;
use File::Slurp;
use HTTP::Request::Common;
use Cwd 'abs_path';

=head1 NAME

ws-upload

=head1 SYNOPSIS

ws-upload local-file workspace-file

=head1 DESCRIPTION

Upload a single file into the workspace. Place into Shock if the --shock flag is given.
    
=head1 COMMAND-LINE OPTIONS

ws-cat.pl [-h] [long options...] path [path...]
	--url       Service URL
	--shock     Retrieve data stored in Shock
	-h --help   Show this usage message
=cut

my @options = (["url=s", 'Service URL'],
	       ["shock", "Retrieve data stored in Shock"],
	       ["overwrite", "Overwrite existing files"],
	       ["help|h", "Show this usage message"]);

my($opt, $usage) = describe_options("%c %o local-file workspace-file",
				    @options);

print($usage->text), exit if $opt->help;
print($usage->text), exit 1 if (@ARGV != 2);

my $local_file = shift;
my $ws_file = shift;

my $ws = Bio::P3::Workspace::ScriptHelpers::wsClient($opt->url);

-f $local_file or die "Local file $local_file does not exist\n";
$local_file = abs_path($local_file);

if ($opt->shock)
{
    local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
    my $token = Bio::KBase::AuthToken->new();
    my $ua = LWP::UserAgent->new();

    my $res = $ws->create({ objects => [[$ws_file, 'unspecified', { original_file => $local_file } ]],
				overwrite => ($opt->overwrite ? 1 : 0),
				createUploadNodes => 1 });
    if (!ref($res) || @$res == 0)
    {
	die "Create failed";
    }
    $res = $res->[0];
    my $shock_url = $res->[11];
    $shock_url or die "Workspace did not reutrn shock url. Return object: " . Dumper($res);

    my $req = HTTP::Request::Common::POST($shock_url, 
					  Authorization => "OAuth " . $token->token,
					  Content_Type => 'multipart/form-data',
					  Content => [upload => [$local_file]]);
    $req->method('PUT');
    my $sres = $ua->request($req);
    print Dumper($sres->content);
}
else
{
    my $res = $ws->create({ objects => [[$ws_file, 'unspecified', { original_file => $local_file },
					scalar read_file($local_file)]] });
    print Dumper($res);
}
    
