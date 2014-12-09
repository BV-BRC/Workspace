
use Try::Tiny;
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
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
    my($wsname, $user, $path);
    if ($fullpath =~ m,^/([^/]+)/([^/]+)(.*),)
    {
	($user, $wsname, $path) = ($1, $2, $3);
	print "wsname=$wsname user=$user path=$path\n";
    }
    elsif ($fullpath !~ m,^/,)
    {
	warn "ws-mkdir $fullpath: Currently all paths must be absolute\n";
	next;
    }
    elsif ($fullpath =~ m,^([^/]+)(.*),)
    {
	($wsname, $path) = ($1, $2);
	print "rel: wsname=$wsname path=$path\n";
    }
    else
    {
	warn "ws-mkdir $fullpath: Cannot parse path\n";
	next;
    }

    if (!$wsutil->workspace_exists("/$user/$wsname"))
    {
	if ($wsutil->username() ne $user)
	{
	    warn "ws-mkdir $fullpath: Cannot create workspace for another user\n";
	    next;
	}
	
	my $m = $ws->create_workspace({ workspace => $wsname });
	print Dumper($m);
    }

    $path =~ s,^/,,;
    if ($path)
    {
	my $curpath = "/$user/$wsname";
	my @parts = split(m!/!, $path);
	for my $part (@parts)
	{
	    $curpath .= "/$part";
	    try {
		my $x = $ws->create_workspace_directory({ directory => $curpath});
		print Dumper($x);
	    } catch {
		if (!/already exists/)
		{
		    die "Create $curpath failed: $_\n";
		}
	    };
	    
	}
    }	 
}
