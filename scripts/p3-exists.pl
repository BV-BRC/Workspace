use strict;
use Bio::P3::Workspace::WorkspaceClientExt;
use P3AuthToken;
use Getopt::Long::Descriptive;

=head1 Check if workspace paths exist

    p3-exists [options] ws-path [ws-path...]

=head1 Usage synopsis

    p3-exists path1 path2 path3
    p3-exists -q /user@example.org/home/myfile.txt && echo "exists"

Checks whether the specified workspace paths exist.
Returns exit code 0 if all paths exist, 1 if any do not exist.

=cut

my $token = P3AuthToken->new();
if (!$token->token())
{
    die "You must be logged in to PATRIC via the p3-login command to use p3-exists.\n";
}

my($opt, $usage) = describe_options("%c %o path [path...]",
                                    ["quiet|q" => "Quiet mode - only set exit code, no output"],
                                    ["admin|A" => "Run in admin mode"],
                                    ["help|h" => "Show this help message"]);
print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV == 0;

my $ws = Bio::P3::Workspace::WorkspaceClientExt->new();

# Normalize paths
my @paths = map { s/^ws://r } @ARGV;

# Call the exists API
my $results = $ws->exists({
    objects => \@paths,
    ($opt->admin ? (adminmode => 1) : ()),
});

my $all_exist = 1;

for my $result (@$results) {
    my ($path, $exists, $error) = @$result;

    if ($error) {
        print STDERR "Error checking $path: $error\n" unless $opt->quiet;
        $all_exist = 0;
    } elsif ($exists) {
        print "$path: exists\n" unless $opt->quiet;
    } else {
        print "$path: does not exist\n" unless $opt->quiet;
        $all_exist = 0;
    }
}

exit($all_exist ? 0 : 1);
