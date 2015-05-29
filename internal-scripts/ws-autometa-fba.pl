
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
$metadata->{model} = $data->{fbamodel_ref};
$metadata->{media} = $data->{media_ref};
$metadata->{model} =~ s/\|\|//;
$metadata->{media} =~ s/\|\|//;
my $list = [qw(
fva
fluxMinimization
findMinimalMedia
allReversible
simpleThermoConstraints
thermodynamicConstraints
comboDeletions
objectiveConstraintFraction
regulome_ref
promconstraint_ref
expression_sample_ref
phenotypeset_ref
objectiveValue
)];
for (my $i=0; $i < @{$list}; $i++) {
	if (defined($data->{$list->[$i]})) {
		$metadata->{$list->[$i]} = $data->{$list->[$i]};
	}	
}
if (@{$data->{geneKO_refs}} > 0) {
	$metadata->{geneKO} = "";
	for(my $i=0; $i < @{$data->{geneKO_refs}};$i++) {
		if (length($metadata->{geneKO})> 0) {
			$metadata->{geneKO} .= "/";
		}
		if ($data->{geneKO_refs}->[$i] =~ m/\/([^\/]+$)/) {
			$metadata->{geneKO} .= $1;
		}
	}
}
if (@{$data->{reactionKO_refs}} > 0) {
	$metadata->{reactionKO} = "";
	for(my $i=0; $i < @{$data->{reactionKO_refs}};$i++) {
		if (length($metadata->{reactionKO})> 0) {
			$metadata->{reactionKO} .= "/";
		}
		if ($data->{reactionKO_refs}->[$i] =~ m/\/([^\/]+$)/) {
			$metadata->{reactionKO} .= $1;
		}
	}
}
if (@{$data->{additionalCpd_refs}} > 0) {
	$metadata->{additionalcpd} = "";
	for(my $i=0; $i < @{$data->{additionalCpd_refs}};$i++) {
		if (length($metadata->{additionalcpd})> 0) {
			$metadata->{additionalcpd} .= "/";
		}
		if ($data->{additionalCpd_refs}->[$i] =~ m/\/([^\/]+$)/) {
			$metadata->{additionalcpd} .= $1;
		}
	}
}
if (keys(%{$data->{uptakeLimits}}) > 0) {
	$metadata->{uptakeLimits} = "";
	foreach my $atom (keys(%{$data->{uptakeLimits}})) {
		if (length($metadata->{uptakeLimits})> 0) {
			$metadata->{uptakeLimits} .= "/";
		}
		$metadata->{uptakeLimits} = $atom.":".$data->{uptakeLimits}->{$atom};
	}
}
if (defined($data->{FBADeletionResults}) && @{$data->{FBADeletionResults}} > 0) {
	$metadata->{essentialgenes} = "";
	foreach my $item (@{$data->{FBADeletionResults}}) {
		if ($item->{growthFraction} < 0.0000001) {
			if (length($metadata->{essentialgenes})> 0) {
				$metadata->{essentialgenes} .= "/";
			}
			if ($item->{feature_refs}->[0] =~ m/\/([^\/]+)$/) {
				$metadata->{essentialgenes} .= $1;
			}
		}
	}
}
if (defined($data->{FBAMetaboliteProductionResults}) && @{$data->{FBAMetaboliteProductionResults}} > 0) {
	$metadata->{no_production_biomass_compounds} = "";
	foreach my $item (@{$data->{FBAMetaboliteProductionResults}}) {
		if ($item->{maximumProduction} < 0.0000001) {
			if (length($metadata->{no_production_biomass_compounds})> 0) {
				$metadata->{no_production_biomass_compounds} .= "/";
			}
			if ($item->{modelcompound_ref} =~ m/\/([^\/]+)$/) {
				$metadata->{no_production_biomass_compounds} .= $1;
			}
		}
	}
}
if (defined($data->{gapfillingSolutions}) && @{$data->{gapfillingSolutions}} > 0) {
	$metadata->{solutiondata} = Bio::KBase::ObjectAPI::utilities::TOJSON($data->{gapfillingSolutions});
}
if ($data->{maximizeObjective} == 1) {
	$metadata->{objective_function} = "Max ";
} else {
	$metadata->{objective_function} = "Min ";
}
my $first = 1;
foreach my $cpd (keys(%{$data->{compoundflux_objterms}})) {
	if ($first == 0) {
		$metadata->{objective_function} .= " + ";
	}
	if ($data->{compoundflux_objterms}->{$cpd} != 1) {
		$metadata->{objective_function} .= "(".$data->{compoundflux_objterms}->{$cpd}.") ";
	}
	$metadata->{objective_function} .= $cpd;
	$first = 0;
}
foreach my $rxn (keys(%{$data->{reactionflux_objterms}})) {
	if ($first == 0) {
		$metadata->{objective_function} .= " + ";
	}
	if ($data->{reactionflux_objterms}->{$rxn} != 1) {
		$metadata->{objective_function} .= "(".$data->{reactionflux_objterms}->{$rxn}.") ";
	}
	$metadata->{objective_function} .= $rxn;
	$first = 0;
}
foreach my $rxn (keys(%{$data->{biomassflux_objterms}})) {
	if ($first == 0) {
		$metadata->{objective_function} .= " + ";
	}
	if ($data->{biomassflux_objterms}->{$rxn} != 1) {
		$metadata->{objective_function} .= "(".$data->{biomassflux_objterms}->{$rxn}.") ";
	}
	$metadata->{objective_function} .= $rxn;
	$first = 0;
}
#*******************************************************************
#End type specific code to generate automated metadata
#*******************************************************************
open (my $fhh,">",$directory."/meta.json");
$metadata = $JSON->encode($metadata);	
print $fhh $metadata;
close($fhh);
