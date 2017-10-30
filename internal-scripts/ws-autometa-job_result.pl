
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use JSON::XS;
use Encode;

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

my $directory = $ARGV[0];

my $JSON = JSON::XS->new->utf8(1);
my $data;
if (open (my $fh,"<",$directory."/object.txt"))
{
    local $/;
    undef $/;

    $data = <$fh>;
    close($fh);
}
else
{
    die "$0: cannot read $directory/object.txt: $!";
}
    
my $metadata = {};
#*******************************************************************
#Start type specific code to generate automated metadata
#*******************************************************************
#You data object is loaded as text in "$data"

eval {
    $data = $JSON->decode($data);
};
if ($@)
{
    if ($@ =~ /malformed UTF-8/)
    {
	$data = $JSON->decode(encode('utf-8', $data));
    }
    else
    {
	die "$0: Error parsing data in $directory: $@";
    }
}

*******************************************************************
#End type specific code to generate automated metadata
#*******************************************************************
open (my $fhh,">",$directory."/meta.json");
$metadata = $JSON->encode($data);	
print $fhh $metadata;
close($fhh);
