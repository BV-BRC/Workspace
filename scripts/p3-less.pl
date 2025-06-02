use strict;
use Bio::P3::Workspace::WorkspaceClientExt;
use P3AuthToken;
use Getopt::Long::Descriptive;
use Data::Dumper;
use File::Basename;
use Pod::Usage;
use IO::Pager;

=head1 View a workspace file using a pager

    p3-less [options] ws-path

=head1 Usage synopsis

    p3-less [options] ws-path
    
=cut

my $admin;

my @sources;
my $dest;


my $token = P3AuthToken->new();
if (!$token->token())
{
    die "You must be logged in to PATRIC via the p3-login command to use p3-less.\n";
}
my @paths;

my($opt, $usage) = describe_options("%c %o path [path...]",
				    ["admin|A" => "Run in admin mode"],
				    ["help|h" => "Show this help message"]);
print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV == 0;

my $ws = Bio::P3::Workspace::WorkspaceClientExt->new();

my $pager = $ENV{PAGER} // "less";

my $opts;
$opts->{admin} = 1 if $opt->admin;

for my $path (@ARGV)
{
    $path =~ s/ws://;

    my $pager = IO::Pager->new(\*STDOUT);

    $ws->copy_files_to_handles(1, $token->token(), [[$path, \*STDOUT]], $opts);
}
