
use strict;
use Getopt::Long::Descriptive;
use Bio::ModelSEED::ProbModelSEED::ProbModelSEEDHelper;
use Data::Dumper;
use JSON::XS;

=head1 NAME

ws-autometa-<type>

=head1 SYNOPSIS

ws-autometa-<type> <directory>

=head1 DESCRIPTION

Load a <type> object, compute auto metadata, and save to file

=head1 COMMAND-LINE OPTIONS

ws-autometa-<type> [-h] [long options...]
	-h --help   Show this usage message
	
=cut

my @options = (
	       ["help|h", "Show this usage message"]
	      );

my($opt, $usage) = describe_options("%c <directory> %o",
				    @options);

print($usage->text), exit if $opt->help;

my $directory = $ARGV[0];

my $JSON = JSON::XS->new->utf8(1);
open (my $fh,"<",$directory."/object.txt");
my $data;
while (my $line = <$fh>) {
	$data .= $line;	
}
close($fh);

my $metadata = {};
#*******************************************************************
#Start type specific code to generate automated metadata
#*******************************************************************
$data = $JSON->decode($data);
$metadata->{id} = $data->{id};
$metadata->{source} = $data->{source};
$metadata->{source_id} = $data->{source_id};
$metadata->{name} = $data->{name};
$metadata->{type} = $data->{type};
$metadata->{source} = $data->{source};
$metadata->{genome_ref} = $data->{genome_ref};
$metadata->{template_ref} = $data->{template_ref};
$metadata->{genome_ref} =~ s/\|\|//;
$metadata->{template_ref} =~ s/\|\|//;
$metadata->{num_compounds} = @{$data->{modelcompounds}};
$metadata->{num_reactions} = @{$data->{modelreactions}};
$metadata->{num_compartments} = @{$data->{modelcompartments}};
$metadata->{num_biomasses} = @{$data->{biomasses}};
my $biomasshash;
my $biocpdhash;
my $genehash;
my $rxnhash;
for (my $i=0; $i < @{$data->{biomasses}}; $i++) {
	$biomasshash->{$data->{biomasses}->[$i]->{id}} = 1;
	for (my $j=0; $j < @{$data->{biomasses}->[$i]->{biomasscompounds}}; $j++) {
		if ($data->{biomasses}->[$i]->{biomasscompounds}->[$j]->{modelcompound_ref} =~ /\/([^\/]+)$/) {
			$biocpdhash->{$1} = 1;
		}
	}
}
for (my $i=0; $i < @{$data->{modelreactions}}; $i++) {
	$rxnhash->{$data->{modelreactions}->[$i]->{id}} = 1;
	my $prots = $data->{modelreactions}->[$i]->{modelReactionProteins};
	for (my $j=0; $j < @{$prots}; $j++) {
		my $subunits = $prots->[$j]->{modelReactionProteinSubunits};
		for (my $k=0; $k < @{$subunits}; $k++) {
			my $features = $subunits->[$k]->{feature_refs};
			for (my $m=0; $m < @{$features}; $m++) {
				if ($features->[$m] =~ /\/([^\/]+)$/) {
					$genehash->{$1} = 1;
				}
			}
		}
	}
}
$metadata->{num_genes} = keys(%{$genehash});
#*******************************************************************
#End type specific code to generate automated metadata
#*******************************************************************
open (my $fhh,">",$directory."/meta.json");
$metadata = $JSON->encode($metadata);	
print $fhh $metadata;
close($fhh);
