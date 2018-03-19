use strict;
use Bio::P3::Workspace::WorkspaceClientExt;
use Bio::P3::Workspace::FileListing qw(show_pretty_ls);
use P3AuthToken;
use Getopt::Long::Descriptive;
use Data::Dumper;
use File::Basename;
use Pod::Usage;

=head1 List files.

    
=cut

my $token = P3AuthToken->new();
if (!$token->token())
{
    die "You must be logged in to PATRIC via the p3-login command to use p3-ls.\n";
}
my $ws = Bio::P3::Workspace::WorkspaceClientExt->new();

my @paths;

my($opt, $usage) =
    describe_options("%c %o path [path...]",
		     ["List one or more workspace paths"],
		     [],
		     ["long||l", "Show file details"],
		     ["time|t", "Sort by creation time"],
		     ["reverse|r", "Reverse sort order"],
		     ["shock", "Show shock node IDs in long listing"],
		     ["full-shock", "Show full shock URLs in long listing"],
		     ["help|h", "Show this help message"],
		    );
print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV == 0;

my @paths = @ARGV;

for my $path (@paths)
{
    eval {
	show_pretty_ls($ws, $path, $opt);
    };
    if (my $err = $@)
    {
	if ($err =~ /_ERROR_(.*?)!?_ERROR_/)
	{
	    print STDERR "$path: $1\n";
	}
	else
	{
	    print STDERR "$path: $@\n";
	}
    }
}
	  
