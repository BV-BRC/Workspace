#
# Workspace interactive shell.
#
# Some of this is derived from the Term::ReadLine::Gnu example program pftp.
#

use strict;
use POSIX;
use Data::Dumper;
use Term::ReadLine;
use Bio::P3::Workspace::WorkspaceClientExt;
use Getopt::Long::Descriptive;
use P3AuthToken;
use Bio::P3::Workspace::ScriptHelpers;
use Text::Table;
use Term::ReadKey;
use IO::Handle;
use Fcntl ':mode';

my $default_url = "https://p3.thseed.org/services/Workspace";

my($opt, $usage) = describe_options("%c %o",
				    ["url|u=s", "Workspace URL"],
				    ["help|h", "Show this help message"],
				    );
print $usage->text, exit 0 if $opt->help;
die $usage->text if @ARGV != 0;

my %commands = (cd => \&cmd_cd,
		ls => \&cmd_ls,
		);

my @cmd_list = keys %commands;

my $term = Term::ReadLine->new("ws");
my $attribs = $term->Attribs;

open(D, ">", "/dev/ttys010");
D->autoflush(0);

#
# Set up completion.
#
$attribs->{attempted_completion_function} = sub {
        my ($text, $line, $start, $end) = @_;
	#print "\ntext='$text' line='$line' start=$start end=$end\n";
	if (substr($line, 0, $start) =~ /^\s*$/) {
	    $attribs->{completion_word} = \@cmd_list;
	    undef $attribs->{completion_display_matches_hook};
	    return $term->completion_matches($text,
					     $attribs->{'list_completion_function'});
	} elsif ($line =~ /^\s*(ls|dir|get|mget)\s/) {
#	    $attribs->{completion_display_matches_hook} = \&ws_display_match_list;
	    return $term->completion_matches($text,
					     \&ws_filename_completion_function);
	} elsif ($line =~ /^\s*(cd|cwd)\s/) {
#	    $attribs->{completion_display_matches_hook} = \&ws_display_match_list;
	    return $term->completion_matches($text,
					     \&ws_dirname_completion_function);
	} else {# put mput lcd
	    undef $attribs->{completion_display_matches_hook};
	    return ();# local file name completion
	}
    };



#my $token_obj = Bio::KBase::AuthToken->new;
my $token = Bio::P3::Workspace::ScriptHelpers::token();

my $ws = Bio::P3::Workspace::WorkspaceClientExt->new($opt->url, token => $token);

my $login = token_user($token);

my $home = "/$login/home";
my $pwd = $home;

#
#Command loop
#
$SIG{INT} = 'IGNORE' ;		# ignore Control-C

our $running = 1;

while ($running && defined($_ = $term->readline("$pwd> ")))
{
    no strict 'refs';
    next if /^\s*$/;
    my ($cmd, @args) = $term->history_tokenize($_);
    
    my $ref = $commands{$cmd};
    if ($ref)
    {
	$ref->(@args);
    }
    $attribs->{completion_append_character} = ' ';
}

exit (0);

#
# Commands
#

sub cmd_ls
{
    my(@args) = @_;
    
    my $path;
    my $opath;
    my $isdir;
    if (@args == 0)
    {
	$path = $pwd;
	$isdir = 1;		# we know pwd is a dir
    }
    elsif (@args == 1)
    {
	$opath = $path = $args[0];
	if ($path !~ m,^/,)
	{
	    $path = "$pwd/$path";
	}
    }
    else
    {
	warn "Usage: ls [path]\n";
	return;
    }

    my $obj;

    if (!$isdir)
    {
	my $res = $ws->get({ objects => [$path], metadata_only => 1});
	$obj = $res->[0]->[0];
    }

    if ($isdir || $obj->[1] eq 'folder')
    {
	my $dh = $ws->opendir($path);
	my @files = sort { $a cmp $b } $ws->readdir($dh);
	
	my @out = tabularize(\@files);
	print "$_\n" foreach @out;
    }
    else
    {
	print "$opath\n";
    }
}

sub cmd_cd
{
    my($path) = @_;

    my $new;
    if ($path)
    {
	if ($path =~ m,^/,)
	{
	    $new = $path;
	}
	else
	{
	    $new = "$pwd/$path";
	}

	my $stat = $ws->stat($new);
	if (!$stat)
	{
	    print "$path does not exist\n";
	    return;
	}
	if (!S_ISDIR($stat->mode))
	{
	    print "$path is not a directory\n";
	    return;
	}
	
	$pwd = normalize_path($new);
    }
    else
    {
	$pwd = $home;
    }
}

sub token_user
{
    my($token) = @_;
    my($user) = $token =~ /un=([^|]+)/;
    return $user;
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

our $compdat;
our $compdir;
sub ws_filename_completion_function
{
    my($text, $state) = @_;
    print D "Complete: '$text' state=$state\n";
    if ($state == 0)
    {
	my($dir, $file) = $text =~ m,(.*/)?(.*)$,;
	$compdir = $dir;
	$dir = "$pwd/$dir" if $dir !~ m,^/,;
	$attribs->{completion_append_character} = ' ';
	my $dh = $ws->opendir($dir);
	print D "Opendir $dir => $dh\n";
	$compdat = [];
	for my $ent (sort { $a cmp $b } $ws->readdir($dh, 1))
	{
	    my $f = $ent->[0];
	    if ($f =~ /^$file/)
	    {
		if ($ent->[1] eq 'folder')
		{
		    $f .= "/";
		}
		push(@$compdat, $f);
	    }
	}
    }
    my $val = $compdat->[$state];
    $attribs->{completion_append_character} = '' if ($val =~ m,/$,);
    print D "  val=$val\n";
    return $val ? ($compdir . $val) : undef;
}

sub ws_display_match_list
{
    print D Dumper(@_);
}
    

sub ws_dirname_completion_function
{
}
