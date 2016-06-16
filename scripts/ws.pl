#
# Workspace interactive shell.
#
# Some of this is derived from the Term::ReadLine::Gnu example program pftp.
#

use strict;
use POSIX;
use Data::Dumper;
use Term::ReadLine;
use Bio::P3::Workspace::WorkspaceClient;
use Getopt::Long::Descriptive;
use Bio::KBase::AuthToken;
use Bio::P3::Workspace::ScriptHelpers;
use Text::Table;
use Term::ReadKey;

my $default_url = "https://p3.thseed.org/services/Workspace";

my($opt, $usage) = describe_options("%c %o",
				    ["url|u=s", "Workspace URL"],
				    ["help|h", "Show this help message"],
				    );
print $usage->text, exit 0 if $opt->help;
die $usage->text if @ARGV != 0;

my $term = Term::ReadLine->new("ws");
my $attribs = $term->Attribs;

#my $token_obj = Bio::KBase::AuthToken->new;
my $token = Bio::P3::Workspace::ScriptHelpers::token();

my $ws = Bio::P3::Workspace::WorkspaceClient->new($opt->url, token => $token);

my $login = token_user($token);

my $pwd = "/$login/home";

#
#Command loop
#
$SIG{INT} = 'IGNORE' ;# ignore Control-C

while (defined($_ = $term->readline("$pwd> ")))
{
    no strict 'refs';
    next if /^\s*$/;
    my ($cmd, @args) = $term->history_tokenize($_);
    if ($cmd eq 'quit' || $cmd eq 'bye') {
	last;
    }
    my $func = "cmd_" . $cmd;
    &$func(@args);
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
    if (@args == 0)
    {
	$path = $pwd;
    }
    elsif (@args == 1)
    {
	$path = $args[0];
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

    my $res = ($ws->ls({paths => [$path]}));
    my @files = transform_ls_to_flat($res->{$path}, { -F => 1 });
    my @out = tabularize(\@files);
    print "$_\n" foreach @out;
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
