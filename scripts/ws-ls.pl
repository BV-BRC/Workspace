
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
        --shock    Include Shock URLs
	--help     print usage message and exit

=cut

my @options = (["url=s", 'Service URL'],
	       ['shock', 'Include Shock URLs'],
	       ["help|h", "Show this usage message"]);

my($opt, $usage) = describe_options("%c %o path",
				    @options);

print($usage->text), exit if $opt->help;

my $ws = Bio::P3::Workspace::ScriptHelpers::wsClient($opt->url);

my @paths = @ARGV;

my $res = $ws->ls({ paths => \@paths });


for my $p (@paths)
{
    my $x = $res->{$p};
    print "$p:\n" if @paths > 1;
    my $tbl = [];
    
    for my $file (@$x)
    {
	my($name, $type, $path, $created, $id, $owner, $size, $user_meta, $auto_meta, $user_perm,
	   $global_perm, $shockurl) = @$file;
	push(@$tbl, [$name, $owner, $type, $created, $size, $user_perm, $global_perm, ($opt->shock ? $shockurl  : ())]);
    }
    my $table = Text::Table->new(
				 "Name","Owner","Type","Moddate","Size","User perm","Global perm", ($opt->shock ? "Shock URL" : ())
				);
    $table->load(@{$tbl});
    print $table."\n";
}
