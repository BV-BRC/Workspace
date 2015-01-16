
use Try::Tiny;
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::WorkspaceClientExt;
use Bio::P3::Workspace::Utils;

=head1 NAME

ws-mkdir

=head1 SYNOPSIS

ws-mkdir path [path ...]

=head1 DESCRIPTION

Create a directory in the workspace.

=head1 COMMAND-LINE OPTIONS

rast-annotate-proteins-kmer-v2 [-io] [long options...] < input > output
	-i --input      file from which the input is to be read
	-o --output     file to which the output is to be written
	--help          print usage message and exit
	--min-hits      minimum number of Kmer hits required for a call to be
	                made
	--max-gap       maximum size of a gap allowed for a call to be made

=cut

my @options = (["url=s", 'Service URL'],
	       ["help|h", "Show this usage message"],
	      );

my($opt, $usage) = describe_options("%c %o path [path ...]",
				    @options);

print($usage->text), exit if $opt->help;

my $ws = Bio::P3::Workspace::WorkspaceClient->new($opt->url);
my $wsutil = Bio::P3::Workspace::Utils->new($ws);

for my $fullpath (@ARGV)
{
    if ($fullpath !~ m,^/,)
    {
	warn "ws-mkdir $fullpath: Currently all paths must be absolute\n";
	next;
    }

    my $cur;
    eval {
	$cur = $ws->get({ objects => \@ARGV, metadata_only => 0 });
    };
    if ($@)
    {
	$cur = [];
    }
    $cur = $cur->[0]->[0];
    bless $cur, 'Bio::P3::Workspace::ObjectMeta';
    if (defined($cur->name))
    {
	warn "ws-mkdir $fullpath: path already exists\n";
	print Dumper($cur);
	next;
    }
    eval {
	$ws->create({ objects => [[$fullpath, 'folder']] });
    };
    if ($@)
    {
	warn "Error creating $fullpath\n$@\n";
    }

}
