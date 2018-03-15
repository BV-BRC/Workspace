#
# File listing helper scripts.
#

package Bio::P3::Workspace::FileListing;

use Data::Dumper;
use POSIX;
use strict;
use Term::ReadKey;

use Exporter 'import';
our @EXPORT_OK = qw(show_pretty_ls);

sub show_pretty_ls
{
    my($ws, $path) = @_;

    my $res = $ws->get({ objects => [$path], metadata_only => 1});

    if (!$res || @$res == 0)
    {
	die "$path not found\n";
    }

    $res = $res->[0]->[0];

    if ($res->[1] eq 'folder')
    {
	my $dh = $ws->opendir($path);
	my @files = sort { $a cmp $b } $ws->readdir($dh);
	
	my @out = tabularize(\@files);
	print "$_\n" foreach @out;
    }
    else
    {
	print "$path\n";
    }
}

#
# Turn workspace ls output into a list of files (which might
# be marked with the usual ls -F characters).
sub transform_ls_to_flat
{
    my($res, $flags) = @_;
    my @out;
    for my $ent (@$res)
    {
	my $str = $ent->[0];
	if ($flags->{-F})
	{
	    $str .= "/" if $ent->[1] eq 'folder';
	}
	
	push(@out, $str);
    }
    return sort { $a cmp $b } @out;
}

#
# Normalize a path with respect to a pwd.
#
# Split into parts.
# For each element that is "..", remove it and its predecessor in the list.
# a/b => a/b
# a/../b => b
# a/b/../c => a/c 
sub normalize_path
{
    my($path, $pwd) = @_;
    if ($path !~ m,^/,)
    {
	$path = "$pwd/$path";
    }
    my @parts = split(/\//, $path);
    my $i = 0;
    while ($i < @parts)
    {
	# print Dumper($i, \@parts);
	if ($parts[$i] eq '')
	{
	    splice(@parts, $i, 1);
	}
	elsif ($parts[$i] eq '..')
	{
	    if ($i > 0)
	    {
		splice(@parts, $i-1, 2);
		$i--;
	    }
	    else
	    {
		splice(@parts, $i, 1);
	    }
	}
	else
	{
	    $i++;
	}
    }
    return "/" . join("/", @parts);
}

sub tabularize
{
    my($list) = @_;
    my $max = longest_string($list);
    my $width = window_width();
    my $gutter = 3;
    my $cols = int($width / ($max + $gutter));
    my $rows = ceil(@$list / $cols);
    # print "max=$max width=$width gutter=$gutter cols=$cols rows=$rows\n";
    my @out;
    for my $r (0..$rows - 1)
    {
	my $rowstr = "";
	for my $c (0..$cols - 1)
	{
	    my $idx = $c * $rows + $r;
	    next if $idx >= @$list;
	    my $elt = $list->[$idx];
	    $rowstr .= $elt . ' ' x ($max - length($elt) + $gutter);
	}
	push(@out, $rowstr);
    }
    return @out;
}

sub longest_string
{
    my($list) = @_;
    my $max = -1;
    for my $ent (@$list)
    {
	if (length($ent) > $max) {
	    $max = length($ent);
	}
    }
    return $max;
}

sub window_width
{
    my($w,$h) = GetTerminalSize();
    return $w if $w;

    $w = $ENV{COLUMNS};
    return $w if $w;
    my $l = `stty size`;
    ($w) = $l =~ /^\d+\s+(\d+)/;
    return $w if $w;
    return 80;
}

1;
