#
# File listing helper scripts.
#

package Bio::P3::Workspace::FileListing;

use Data::Dumper;
use POSIX;
use strict;
use Term::ReadKey;
use Text::Table;
use Date::Parse;

use Exporter 'import';
our @EXPORT_OK = qw(show_pretty_ls);

sub show_pretty_ls
{
    my($ws, $path, $opt) = @_;

    my $res = $ws->get({ objects => [$path], metadata_only => 1});

    if (!$res || @$res == 0)
    {
	die "$path not found\n";
    }

    $res = $res->[0]->[0];

    if ($res->[1] eq 'folder' && !$opt->directory)
    {
	my $dir = $ws->ls({ paths => [$path] });

	my @files = @{$dir->{$path}};
	if (!$opt->all)
	{
	    @files = grep { $_->[0] !~ /^\./ } @files;
	}

	@files = sort { compare_paths_for_sort($a, $b, $opt) } @files;

	if ($opt->long)
	{
	    my @list = map { compute_long_listing($_, $opt) } @files;
	    my $table = Text::Table->new();
	    $table->load(@list);
	    print $table;
	}
	else
	{
	    @files = map { $_->[0] } @files;
	    my @out = tabularize(\@files);
	    print "$_\n" foreach @out;
	}
    }
    else
    {
	if ($opt->long)
	{
	    my($ent) = compute_long_listing($res, $opt);
	    print join(" ", @$ent), "\n";
	}
	else
	{
	    print "$path\n";
	}
    }
}

#
# Compute fields for "ls -l" style listing for this object.
sub compute_long_listing
{
    my($ws_obj, $opt) = @_;
    my($name, $type, $path, $created, $oid, $owner, $size, $user_meta, $auto_meta, $user_perm, $global_perm, $shock) = @$ws_obj;

    my @short_perms;
    push(@short_perms, $type eq 'folder' ? 'd' : '-');
    push(@short_perms, 'rw'); 	# In workspace, owner can always access
    push(@short_perms, $global_perm eq 'n' ? '--' : 'r-');
    my $short_perms = join("", @short_perms);

    my @ret = ();
    push(@ret, $short_perms);
    push(@ret, $owner);
    push(@ret, $size);

    my $fmt_cstamp;
    my $cstamp = str2time($created);
    if (time - $cstamp > 180 * 86400)
    {
	$fmt_cstamp = strftime("%b %d  %Y", localtime $cstamp);
    }
    else
    {
	$fmt_cstamp = strftime("%b %d %H:%M", localtime $cstamp);
    }
    push(@ret, $fmt_cstamp);

    if ($opt->ids)
    {
	push(@ret, $oid);
    }

    if ($opt->type)
    {
	push(@ret, $type);
    }
    
    if ($opt->full_shock && $shock)
    {
	$name .= " <- $shock";
    }
    elsif ($opt->shock && $shock =~ m,/node/([^/]+),)
    {
	$name .= " <- $1";
    }
    
    push(@ret, $name);
    return \@ret;
}


#
# Compare pathnames for display.
# First sort with leading dots removed so we can group job results
# with their folders.
#

sub compare_paths_for_sort
{
    my($a, $b, $opt) = @_;

    if ($opt->reverse)
    {
	($b, $a) = ($a, $b);
    }

    my $da = $a->[0];
    my $db = $b->[0];
	
    $da =~ s/^\.//;
    $db =~ s/^\.//;
	
    if ($opt->time)
    {
	my $ta = str2time($a->[3]);
	my $tb = str2time($b->[3]);
	return $ta <=> $tb or $da cmp $db or $a->[0] cmp $b->[0];
    }
    else
    {
	return $da cmp $db or $a->[0] cmp $b->[0];
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
