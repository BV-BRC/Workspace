#
# Archive::Zip::Member subclass for lazily-loaded workspace data
#
# Modified from Archive::Zip::FileMember
#

package Bio::P3::Workspace::WSFileMember;

use Data::Dumper;
use strict;
use vars qw( $VERSION @ISA );
use File::stat;

BEGIN {
    $VERSION = '1.68';
    @ISA     = qw ( Archive::Zip::Member );
}

use Archive::Zip qw(
  :UTILITY_METHODS
);

sub externalFileName {
    shift->{'externalFileName'};
}

# Return true if I depend on the named file
sub _usesFileNamed {
    my $self     = shift;
    my $fileName = shift;
    my $xfn      = $self->externalFileName();
    return undef if ref($xfn);
    return $xfn eq $fileName;
}

sub fh {
    my $self = shift;
    $self->_openFile()
      if !defined($self->{'fh'}) || !$self->{'fh'}->opened();
    return $self->{'fh'};
}

# opens my file handle from my file name
sub _openFile {
    my $self = shift;
    my $fn = $self->externalFileName();

    my $meta = $self->{meta};
    my $fdata;
    if (!$meta)
    {
	# print STDERR "Get to fill in meta for $fn\n";
	my $res = $self->{ws}->get({objects => [$fn]});
	# print STDERR " ... done\n";
	if (!$res || @$res == 0)
	{
	    _ioError("Can't open", $fn);
	    return undef;
	}
	
	($meta, $fdata) = @{$res->[0]};
	$self->{meta} = $meta;
    }

    my ($status, $fh);

    my $url = $meta->[11];
    if ($url)
    {
	#
	# Attempt to directly open the file.
	#

	my $shock_base = "/disks/shock/Shock/data";

	my($id) = $url =~ m,node/([a-f0-9-]+)$,i;
	if ($id)
	{
	    my $path = _get_path($shock_base, $id);
	    my $file = "$path/$id.data";
	    my $sfh = IO::File->new();
	    if (open($sfh, "<", $file))
	    {
		# print STDERR "Directly opened $file\n";
		$fh = $sfh;
	    }
	}
	
	# curl -X GET  -H "Authorization: OAuth `cat /home/olson/.patric_token`" https://p3.theseed.org/services/shock_api/node/2f83bd7d-5a60-4f5a-a565-0b5bd619a29b'?download'


	if (!$fh)
	{
	    # print STDERR "Retrieve shock data for $fn size=$meta->[6] $url\n";
	    my @cmd = ("curl",
		       "-s",
		       "-X", "GET",
		       "-H", "Authorization: OAuth $self->{ws}->{token}",
		       "$url?download");
	    my $sfh = IO::File->new();
	    my $pid = open($sfh, "-|", @cmd);
	    if (!$pid)
	    {
		_ioError("can't open curl pipe for $url");
		return undef;
	    }
	    
	    # ($status, $fh) = _newFileHandle($sfh, 'r');
	    $fh = $sfh;
	}
	$status = 1;
    }
    else
    {
	if (!$fdata)
	{
	    my $ws_base = "/disks/p3/workspace/P3WSDB";

	    my $ws_path = "$ws_base/$fn";

	    my $sfh = IO::File->new();
	    if (open($sfh, "<", $ws_path))
	    {
		my $st = stat($sfh);
		if ($st->size == $self->{uncompressedSize})
		{
		    $fh = $sfh;
		    $status = 1;
		}
	    }
	    else
	    {
		# print STDERR "get to fill in data for $fn\n";
		my $res = $self->{ws}->get({objects => [$fn]});
		# print STDERR "... done size=" . length($res->[0]->[1]) . " comp=$self->{compressedSIze} uncomp=$self->{uncompressedSize}\n";
		
		if (!$res || @$res == 0)
		{
		    _ioError("Can't open", $fn);
		    return undef;
		}
		
		(undef, $fdata) = @{$res->[0]};
		# print "Got fdata $fdata\n";
	    }
	}
	if (!$fh)
	{
	    if ($fdata eq '')
	    {
		# HACK patch for debugging where we don't have all the file data
		#
		$self->{uncompressedSize} = $self->{compressedSize} = 0;
	    }
	    my $sfh = IO::File->new(\$fdata, 'r');
	    ($status, $fh) = _newFileHandle($sfh, 'r');
	}
    }
    
    if (!$status) {
        _ioError("Can't open", $fn);
        return undef;
    }
    $self->{'fh'} = $fh;
    _binmode($fh);
    return $fh;
}

# Make sure I close my file handle
sub endRead {
    my $self = shift;
    # print "read done\n";
    undef $self->{'fh'};    # _closeFile();
    return $self->SUPER::endRead(@_);
}

sub _become {
    my $self     = shift;
    my $newClass = shift;
    return $self if ref($self) eq $newClass;
    delete($self->{'externalFileName'});
    delete($self->{'fh'});
    return $self->SUPER::_become($newClass);
}

sub _get_path
{
    my($data_dir, $id) = @_;
    my $path = join("/", $data_dir, substr($id, 0, 2), substr($id, 2, 2), substr($id, 4, 2), $id);
    return $path;
}

1;
