use strict;
use Bio::P3::Workspace::WorkspaceClientExt;
use P3AuthToken;
use Getopt::Long::Descriptive;
use Data::Dumper;
use File::Basename;
use Pod::Usage;

=head1 Remove a directory

    
=cut

my $token = P3AuthToken->new();
if (!$token->token())
{
    die "You must be logged in to PATRIC via the p3-login command to use p3-rmdir.\n";
}
my $ws = Bio::P3::Workspace::WorkspaceClientExt->new();

my @paths;

my($opt, $usage) =
    describe_options("%c %o path [path...]",
		     ["Remove one or more directories in the workspace"],
		     [],
		     ["help|h", "Show this help message"],
		    );
print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV == 0;

my @paths = @ARGV;

for my $path (@paths)
{
    my $cur = eval { $ws->get( { objects => [$path], metadata_only => 1 } ); };
    if (!$cur || @$cur == 0)
    {
	print STDERR "Not removing $path: directory does not exist\n";
	next;
    }
    $cur = $cur->[0]->[0];
    if ($cur->[1] ne 'folder')
    {
	print STDERR "Not removing $path: is not a directory\n";
	next;
    }

    #
    # We do an ls here to both ensure this really is a folder and that it is empty.
    #
     
    my $cur = eval { $ws->ls( { paths => [$path] } ); };

    my $meta = $cur->{$path};
    my $n = ref($meta) eq 'ARRAY' ? @$meta : 0;
    if ($n > 0)
    {
	print STDERR "Not removing $path: directory is not empty\n";
	next;
    }
    eval {
	my $res = $ws->delete({ objects => [$path], deleteDirectories => 1 });
    };
    if (my $err = $@)
    {
        if ($err =~ /_ERROR_(.*?)!?_ERROR_/)
        {
	    print STDERR "Error removing directory $path: $1\n";
        }
        else
        {
	    print STDERR "Error removing directory $path: $@\n";
        }
    }
}

	  
