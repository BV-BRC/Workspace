
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use JSON::XS;
use File::Slurp;
use GenomeTypeObject;

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

my($opt, $usage) = describe_options("%c %o",
				    @options);

print($usage->text), exit if $opt->help;
die($usage->text) if @ARGV != 1;

my $JSON = JSON::XS->new->utf8(1)->pretty(1);

my $directory = $ARGV[0];

my $genome_file = "$directory/object.txt";
my $data = GenomeTypeObject->new({ file => $genome_file });
$data or die "Cannot load genome object from $genome_file\n";

my $metadata = {};

$metadata->{genome_id} = $data->{id};
$metadata->{scientific_name} = $data->{scientific_name};
$metadata->{domain} = $data->{domain};

my $metrics = $data->metrics();

$metadata->{dna_size} = $metrics->{totlen};
$metadata->{N50} = $metrics->{N50};
$metadata->{N70} = $metrics->{N70};
$metadata->{N90} = $metrics->{N90};

$metadata->{num_contigs} = @{$data->{contigs}};
my($gc, $per_contig) = $data->compute_contigs_gc();

#
# Mongo doesn't like dotted field names.
#
delete $per_contig->{$_} foreach grep { /\./ } (keys %$per_contig);

$metadata->{gc_content} = $gc;
$metadata->{per_contig_gc_content} = $per_contig if $metadata->{num_contigs} < 100;

$metadata->{taxonomy} = $data->{taxonomy};
$metadata->{ncbi_taxonomy_id} = $data->{ncbi_taxonomy_id};
$metadata->{num_features} = @{$data->{features}};
#*******************************************************************
#End type specific code to generate automated metadata
#*******************************************************************
open (my $fhh,">",$directory."/meta.json");
$metadata = $JSON->encode($metadata);	
print $fhh $metadata;
close($fhh);
