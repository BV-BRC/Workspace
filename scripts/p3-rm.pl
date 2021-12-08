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
 		     ["recursive|r", "Recursively remove the given path"],
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
	if (!$opt->recursive)
	{
	    print STDERR "Not removing $path: is a directory\n";
	    next;
	}
	#
	# Recursively remove folder.
	#

	my $files = $ws->ls({paths => [$path], recursive => 1});
	$files = $files->{$path};
	my @to_del;
	for my $file (@$files)
	{
	    my($name, $type, $path) = @$file;
	    my $objpath = "$path$name";
	    push(@to_del, $objpath);
	}
	push(@to_del, $path);
	my $res = eval { $ws->delete({ objects => \@to_del, deleteDirectories => 1, force => 1}) };
	if (my $err = $@)
	{
	    if ($err =~ /_ERROR_(.*?)!?_ERROR_/)
	    {
		print STDERR "Error in recursive remove: $1\n";
	    }
	    else
	    {
		print STDERR "Error in recursive remove: $@\n";
	    }
	}
    }
    else
    {
	#
	# Single file
	#
	
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
}    
    
