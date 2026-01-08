use strict;
use Bio::P3::Workspace::WorkspaceClientExt;
use P3AuthToken;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Pod::Usage;

=head1 Show disk usage for workspace paths

    p3-du [options] path [path...]

=head1 Usage synopsis

    p3-du path                    # Show disk usage for path
    p3-du -h path                 # Show human-readable sizes
    p3-du -s path                 # Show summary only (total)
    p3-du --no-recursive path     # Don't recurse into subdirectories
    p3-du --children path         # Show disk usage for each child of path

=cut

my $token = P3AuthToken->new();
if (!$token->token())
{
    die "You must be logged in to PATRIC via the p3-login command to use p3-du.\n";
}

my($opt, $usage) =
    describe_options("%c %o path [path...]",
		     ["Show disk usage for workspace paths"],
		     [],
		     ["human-readable|h", "Print sizes in human readable format (e.g., 1K 234M 2G)"],
		     ["summarize|s", "Display only a total for each argument"],
		     ["children|c", "Show disk usage for each child of the given path"],
		     ["no-recursive", "Do not include subdirectories in the count"],
		     ["administrator|A", "Run as administrator (if user has those privileges)"],
		     ["url=s", "Use this workspace URL instead of the default"],
		     [],
		     ["help", "Show this help message"],
		    );
print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV == 0;

my $ws = Bio::P3::Workspace::WorkspaceClientExt->new($opt->url);

my @paths = @ARGV;
my @admin = $opt->administrator ? (adminmode => 1) : ();

# If --children flag is set, expand each path to its children first
if ($opt->children) {
    my @child_paths;
    for my $path (@paths) {
	eval {
	    my $dir = $ws->ls({ paths => [$path], @admin });
	    my $files = $dir->{$path};
	    if (ref($files) eq 'ARRAY') {
		for my $entry (@$files) {
		    # entry->[2] is the full path, entry->[0] is the name
		    my $child_path = $entry->[2];
		    # Remove trailing slash if present
		    $child_path =~ s/\/$//;
		    push(@child_paths, $child_path);
		}
	    }
	};
	if ($@) {
	    my $err = $@;
	    if ($err =~ /_ERROR_(.*?)!?_ERROR_/) {
		print STDERR "$path: $1\n";
	    } else {
		print STDERR "$path: $err\n";
	    }
	}
    }
    @paths = @child_paths;
}

if (@paths == 0) {
    exit 0;
}

# Build API call parameters
my %params = (
    paths => \@paths,
    recursive => $opt->no_recursive ? 0 : 1,
);
$params{adminmode} = 1 if $opt->administrator;

my $results;
eval {
    $results = $ws->du(\%params);
};
if ($@) {
    my $err = $@;
    if ($err =~ /_ERROR_(.*?)!?_ERROR_/) {
	die "Error: $1\n";
    } else {
	die "Error: $err\n";
    }
}

# Display results
for my $result (@$results) {
    my ($path, $total_size, $file_count, $dir_count, $error) = @$result;

    if ($error) {
	print STDERR "$path: $error\n";
	next;
    }

    my $size_str;
    if ($opt->human_readable) {
	$size_str = format_size($total_size);
    } else {
	$size_str = $total_size;
    }

    if ($opt->summarize) {
	print "$size_str\t$path\n";
    } else {
	print "$size_str\t$path ($file_count files, $dir_count directories)\n";
    }
}

sub format_size {
    my ($bytes) = @_;

    return "0" if !defined($bytes) || $bytes == 0;

    my @units = ('B', 'K', 'M', 'G', 'T', 'P');
    my $unit_index = 0;
    my $size = $bytes;

    while ($size >= 1024 && $unit_index < $#units) {
	$size /= 1024;
	$unit_index++;
    }

    if ($unit_index == 0) {
	return sprintf("%d%s", $size, $units[$unit_index]);
    } else {
	return sprintf("%.1f%s", $size, $units[$unit_index]);
    }
}
