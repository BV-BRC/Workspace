use strict;
use Bio::P3::Workspace::WorkspaceClientExt;
use P3AuthToken;
use Getopt::Long::Descriptive;
use Data::Dumper;
use File::Basename;
use Pod::Usage;

=head1 Remove a file

    
=cut

my $token = P3AuthToken->new();
if (!$token->token())
{
    die "You must be logged in to PATRIC via the p3-login command to use p3-rmdir.\n";
}
my @paths;

my($opt, $usage) =
    describe_options("%c %o path [path...]",
		     ["Remove one or more files in the workspace"],
		     [],
		     ["url=s", "Use this workspace URL instead of the default"],
		     ["help|h", "Show this help message"],
		    );
print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV == 0;

my $ws = Bio::P3::Workspace::WorkspaceClientExt->new($opt->url);

my @paths = @ARGV;

for my $path (@paths)
{
    my $cur = eval { $ws->get( { objects => [$path], metadata_only => 1 } ); };
    if (!$cur || @$cur == 0)
    {
	print STDERR "Not removing $path: file does not exist\n";
	next;
    }
    $cur = $cur->[0]->[0];
    if ($cur->[1] eq 'folder' || $cur->[1] eq 'modelfolder' || $cur->[8]->{is_folder})
    {
	print STDERR "Not removing $path: is a directory\n";
	next;
    }

    eval {
	my $res = $ws->delete({ objects => [$path], deleteDirectories => 0 });
    };
    if (my $err = $@)
    {
        if ($err =~ /_ERROR_(.*?)!?_ERROR_/)
        {
	    print STDERR "Error removing file $path: $1\n";
        }
        else
        {
	    print STDERR "Error removing file $path: $@\n";
        }
    }
}

	  
