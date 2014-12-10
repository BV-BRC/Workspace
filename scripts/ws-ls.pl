
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::ScriptHelpers;
use Text::Table;

=head1 NAME

ws-ls

=head1 SYNOPSIS

ws-ls path [path...]

=head1 DESCRIPTION

List the contents of a workspace directory.

=head1 COMMAND-LINE OPTIONS

ws-ls path [long options...]
	--url      URL to use for workspace service
	--help     print usage message and exit

=cut

my @options = (["url=s", 'Service URL'],
	       ["help|h", "Show this usage message"]);

my($opt, $usage) = describe_options("%c %o path",
				    @options);

print($usage->text), exit if $opt->help;

my $ws = Bio::P3::Workspace::ScriptHelpers::wsClient($opt->url);

my $path = $ARGV[0];

my $tbl = [];
if (defined($path) && $path =~ /\/[^\/]+\/[^\/]+\/*/) {
	my $objs = $ws->list_workspace_contents({
		directory => $path,
		includeSubDirectories => 1,
		excludeObjects => 0,
		Recursive => 0
	});
 	for (my $i=0; $i < @{$objs}; $i++) {
 		my $obj = $objs->[$i];
 		if ($obj->[2] eq "Directory") {
 			push(@{$tbl},[$obj->[1],$obj->[5],$obj->[2],$obj->[3],$obj->[9],"?","?"]);
 		}
 	}
 	for (my $i=0; $i < @{$objs}; $i++) {
 		my $obj = $objs->[$i];
 		if ($obj->[2] ne "Directory") {
 			push(@{$tbl},[$obj->[1],$obj->[5],$obj->[2],$obj->[3],$obj->[9],"?","?"]);
 		}
 	}
} else {
	my $wslist = $ws->list_workspaces({});
	my $user;
	if ($path =~ /\/([^\/]+)\/*/) {
 		print "Listing workspaces owned by $user\n";
 		$user = $1;
	} else {
		print "Listing all accessible workspaces\n";
	}
 	for (my $i=0; $i < @{$wslist}; $i++) {
 		my $obj = $wslist->[$i];
 		
 		if (!defined($user) || $user eq $obj->[2]) {
 			push(@{$tbl},[$obj->[1],$obj->[2],"Workspace",$obj->[3],$obj->[4],$obj->[5],$obj->[6]]);
 		}
 	}
}
my $table = Text::Table->new(
	"Name","Owner","Type","Moddate","Size","User perm","Global perm",
);
$table->load(@{$tbl});
print $table."\n";