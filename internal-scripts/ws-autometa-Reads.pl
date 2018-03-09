#! /usr/bin/env perl

use strict;
use Carp;
use File::Temp;
use File::Basename;
use Getopt::Long::Descriptive;
use JSON::XS;
use IPC::Run;
use File::Which qw(which);
use File::Slurp;

my @options = (["help|h",   "Show this usage message"],
               ["out|o=s",  "Output filename for metadata", { default  => "meta.json" }],
	       );

my ($opt, $usage) = describe_options("%c %o reads.fastq (or fasta or compressed formats)", @options);

print($usage->text), exit if $opt->help;
die($usage->text) if @ARGV != 1;

my $dir = shift;

my $obj = "$dir/object.txt";

my $type;
my $ok = IPC::Run::run(["file", "--mime-type", "-b", $obj], ">", \$type);
$ok or die "Failure running file on $obj\n";

my $readfile;
chomp $type;

if ($type eq 'application/x-gzip')
{
    $readfile = "$dir/readfile.fq.gz";
    symlink($obj, $readfile) or die "symlink $obj $readfile failed: $!";
}
else
{
    $readfile = "$dir/readfile.fq";
    symlink($obj, $readfile) or die "symlink $obj $readfile failed: $!";
}

-s $readfile or die "File not found or empty: $readfile\n";

my $tmpdir = File::Temp->newdir("fastqc_XXXXX", TMPDIR => 1, CLEANUP => 1);
print STDERR "tmpdir=$tmpdir\n";
my $meta = reads_to_meta($readfile, $tmpdir);

my $out_file = "$dir/" . $opt->out;

my $JSON = JSON::XS->new->utf8(1)->pretty(1);

open(OUT, ">", $out_file) or die "Could not open output file $out_file: $!";
print OUT $JSON->encode($meta);
close(OUT);

sub reads_to_meta {
    my ($readfile, $tmpdir) = @_;

    my $fastqc = which("fastqc");
    $fastqc or die "Cannot find fastqc to execute\n";

    my($stdout, $stderr);
    my $ok = IPC::Run::run([$fastqc, "--threads", 2, "--extract", "-q", "-o", $tmpdir,  $readfile],
			   ">", \$stdout, "2>", \$stderr);
    my %meta;
    if (!$ok)
    {
	print STDERR "fastqc failure $?:\n<<$stdout>>\n<<$stderr>>\n";
    }
    else
    {
	my ($subd) = grep { -d } glob("$tmpdir/*");
	my ($f1, $f2) = map { "$subd/$_" } qw(fastqc_data.txt summary.txt);
	
	my %basic   = map { chomp; my ($k, $v) = split/\t/; clean_key($k) => $v } `head -n 10 $f1 | tail -n 7`;
	my %quality = map { chomp; my ($v, $k) = split/\t/; clean_key($k) => $v } `cut -f1,2 $f2`;

	#
	# Load images.
	#
	my %images;
	for my $img (glob("$subd/Images/*png"))
	{
	    my $data = read_file($img, err_mode => 'quiet');
	    if ($data)
	    {
		my $f = basename($img, ".png");
		$images{$f} = $data;
	    }
	}
	
	%meta = (%basic, quality_tests => \%quality, images => \%images);
    }
    wantarray ? %meta : \%meta;
}

sub clean_key {
    my ($key) = @_;
    $key =~ s/\W+/ /g;
    $key =~ s/^\s+//;
    $key =~ s/\s+$//;
    $key =~ s/\s+/_/g;
    lc $key;
}

