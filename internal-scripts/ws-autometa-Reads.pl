#! /usr/bin/env perl

use strict;
use Carp;
use File::Temp;
use Getopt::Long::Descriptive;
use JSON::XS;

my @options = (["help|h",   "Show this usage message"],
               ["out|o=s",  "Output filename for metadata", { default  => "meta.json" }],
               ["temp|t=s", "Temporary directory"]);

my ($opt, $usage) = describe_options("%c %o reads.fastq (or fasta or compressed formats)", @options);

print($usage->text), exit if $opt->help;

my $readfile = shift @ARGV or die $usage->text;
-s $readfile or die "File not found or empty: $readfile\n";

my $tmpdir = File::Temp::tempdir("fastqc_XXXXX", DIR => $opt->temp); #, CLEANUP => 1);
my $meta = reads_to_meta($readfile, $tmpdir);

my $JSON = JSON::XS->new->utf8(1);
open(OUT, ">", $opt->out) or die "Could not open output file: ". $opt->out;
print OUT $JSON->encode($meta);
close(OUT);

sub reads_to_meta {
    my ($readfile, $tmpdir) = @_;

    verify_cmd("fastqc");
    run("fastqc --extract -q -o $tmpdir $readfile");

    my ($subd) = grep { -d } glob("$tmpdir/*");
    my ($f1, $f2) = map { "$subd/$_" } qw(fastqc_data.txt summary.txt);

    my %basic   = map { chomp; my ($k, $v) = split/\t/; clean_key($k) => $v } `head -n 10 $f1 | tail -n 7`;
    my %quality = map { chomp; my ($v, $k) = split/\t/; clean_key($k) => $v } `cut -f1,2 $f2`;

    my %meta = (%basic, quality_tests => \%quality);

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

sub verify_cmd {
    my ($cmd) = @_;
    system("which $cmd >/dev/null") == 0 or die "Command not found: $cmd\n";
}

sub run { system(@_) == 0 or confess("FAILED: ". join(" ", @_)); }
