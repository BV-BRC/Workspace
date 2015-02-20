
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;

=head1 NAME

ws-update-metadata

=head1 SYNOPSIS

ws-update-metadata <filename> <script path> <data path> <url>

=head1 DESCRIPTION

Compute and load auto-metadata for object list

=head1 COMMAND-LINE OPTIONS

ws-update-metadata [-h] [long options...]
	-h --help   Show this usage message
	
=cut

my @options = (
	       ["help|h", "Show this usage message"],
	      );

my($opt, $usage) = describe_options("%c %o",
				    @options);

print($usage->text), exit if $opt->help;

my $directory = $ARGV[0];
my $scriptpath = $ARGV[1];
my $datapath = $ARGV[2];
my $url = $ARGV[3];

my $ws = Bio::P3::Workspace::WorkspaceClient->new($url);

open (my $fh,"<",$filename);
my $data;
while (my $line = <$fh>) {
	$data .= $line;	
}
close($fh);
my $JSON = JSON::XS->new->utf8(1);
$objs = $JSON->decode($data);

for (my $i=0; $i < @{$objs}; $i++) {
	if (-e $scriptpath."/ws-autometa-".$objs->[$i]->{type}.".pl") {
		if ($objs->[$i]->{shock} == 1) {
			
		} elsif ($objs->[$i]->{folder} == 0) {
			my $filename = $datapath."/".$objs->[$i]->{path}."/".$objs->[$i]->{name};
			system("cp \"".$filename."\" \"".$directory."/object.json\"");
		}
		if (-e $directory."/object.json") {
			system("perl ".$scriptpath."/ws-autometa-".$objs->[$i]->{type}.".pl ".$directory);
			open (my $fh,"<",$directory."/meta.json");
			my $data;
			while (my $line = <$fh>) {
				$data .= $line;	
			}
			close($fh);
			$ws->();
		}
	}
}