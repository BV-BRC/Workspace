#
# Create an archive of a set of workspace files and folders.
#

use Archive::Zip qw(:CONSTANTS);
use Bio::P3::Workspace::WSFileMember;
use Bio::P3::Workspace::WSNewFileMember;
use File::Basename;

use Bio::P3::Workspace::WorkspaceClientExt;

use Data::Dumper;
use strict;
use Getopt::Long::Descriptive;


my($opt, $usage) = describe_options("%c %o path [path ...]",
				    ["output|o=s", "Write to this file (default to stdout)"],
				    ["auth-token=s", "Use this authorization token"],
				    ["max-size=i", "Only archive files smaller than this size"],
				    ["prefix=s", "Prefix to remove from paths before archiving"],
				    ["uncompressed", "Disable compression"],
				    ["log-stderr=s", "Redirect stderr to this file before executing."],
				    ["carp", "carp always"],
				    ["help|h", "Show this help message."]);
print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV == 0;

require Carp::Always if $opt->carp;

$ENV{KB_AUTH_TOKEN} = $opt->auth_token if $opt->auth_token;

my $ws = Bio::P3::Workspace::WorkspaceClientExt->new;

my @paths = @ARGV;

if ($opt->log_stderr)
{
    open(STDERR, ">", $opt->log_stderr) or die "Cannot write " . $opt->log_stderr . ": $!";
}

my $path_info = $ws->get({objects => \@paths, metadata_only => 1});
my $dir_info = $ws->ls({paths => \@paths, excludeDirectories => 1, recursive => 1 });

my $total_size = 0;
my @to_zip;

my $errors;

#
# Cache workspace metadata to reduce calls.
#
my $meta_cache = {};

for my $info (@$path_info)
{
    my($meta, $data) = @$info;
    my($name, $type, $path, $created, $oid, $owner, $size, $umeta, $ameta, $user_perm, $global_perm, $url, $error)
	= @$meta;
    my $fpath = $path . $name;

    $meta_cache->{$fpath} = $meta;

    if ($ameta->{is_folder} || $type eq 'folder')
    {
	print STDERR "Expand $fpath\n";

	my $exp = $dir_info->{$fpath};
	if (!$exp)
	{
	    warn "Path info not found for $fpath\n";
	    $errors++;
	}

	$exp = $dir_info->{$fpath};
	for my $ent (@$exp)
	{
	    my($name, $type, $path, $ts, $oid, $owner, $size, $usermeta, $autometa,
	       $user_perm, $global_perm, $shockurl) = @$ent;


	    my $fname = $path . $name;
	    $meta_cache->{$fname} = $ent;
	    
	    next if ($opt->max_size && $size > $opt->max_size);
	    push(@to_zip, $fname);
	}
    }
    else
    {
	push(@to_zip, $fpath);
    }
}

if ($errors)
{
    die "Exiting due to errors\n";
}

my $prefix = $opt->prefix;
if (!$prefix)
{
    if (@paths == 1)
    {
	$prefix = dirname($paths[0]);
    }
    else
    {
	#
	# Build longest common prefix.
	#

	my @sets = map { $_ = [ split("/", $_) ]; shift @$_; $_ } @paths;
	my @cur;
    OUTER:
	while (1)
	{
	    my $c;
	    for my $s (@sets)
	    {
		my $x = shift @$s;
		if (defined($c) && $x ne $c)
		{
		    last OUTER;
		}
		$c = $x;
	    }
	    push(@cur, $c);
	}
	# die Dumper(\@sets, \@cur);
	
	$prefix = "/" . join("/", @cur);
    }
}

my $z = Archive::Zip->new();

for my $path (@to_zip)
{
    my $name = $path;
    $name =~ s/^$prefix//;

    $name =~ s,^/+,,;

    # print STDERR "$path\t$name\n";
    my $m = Bio::P3::Workspace::WSNewFileMember->_newFromFileNamed($path, $name, $meta_cache, $ws);
    if ($opt->uncompressed)
    {
	$m->desiredCompressionMethod(COMPRESSION_STORED);
    }
	    
    $z->addMember($m);
}

my $outfh;

if (!$opt->output  || $opt->output eq '-')
{
    $outfh = \*STDOUT;
}
else
{
    open($outfh, ">", $opt->output) or die "Cannot write " . $opt->output . ": $!";
}

$z->writeToFileHandle($outfh);

