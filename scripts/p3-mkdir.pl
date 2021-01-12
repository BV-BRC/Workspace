use strict;
use Bio::P3::Workspace::WorkspaceClientExt;
use P3AuthToken;
use Getopt::Long::Descriptive;
use Data::Dumper;
use File::Basename;
use Pod::Usage;

=head1 Create a directory

    
=cut

my $token = P3AuthToken->new();
if (!$token->token())
{
    die "You must be logged in to PATRIC via the p3-login command to use p3-mkdir.\n";
}
my @paths;

my($opt, $usage) =
    describe_options("%c %o path [path...]",
		     ["Create one or more directories in the workspace"],
		     ["url=s", "Use this workspace URL instead of the default"],
		     [],
		     ["help|h", "Show this help message"],
		    );
print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV == 0;

my $ws = Bio::P3::Workspace::WorkspaceClientExt->new($opt->url);

my @paths = @ARGV;

for my $path (@paths)
{
    my $cur = eval { $ws->get( { objects => [$path], metadata_only => 1 } ); };
    if ($cur && @$cur == 1)
    {
	my $meta = $cur->[0]->[0];
	if (defined($meta->[0]))
	{
	    print STDERR "$path already exists\n";
	    print STDERR Dumper($cur->[0]->[0]);
	    next;
	}
    }
    eval {
	my $res = $ws->create({ objects => [[$path, 'folder']] });
    };
    if (my $err = $@)
    {
	if ($err =~ /_ERROR_(.*?)!?_ERROR_/)
	{
	    print STDERR "Error creating direcotry $path: $1\n";
	}
	else
	{
	    print STDERR "Error creating directory $path: $@\n";
	}
    }
}
	  
