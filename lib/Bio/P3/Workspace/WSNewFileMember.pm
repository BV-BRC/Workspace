#
# Archive::Zip::Member subclass for lazily-loaded workspace data
#
# Modified from Archive::Zip::NewFileMember
#

package Bio::P3::Workspace::WSNewFileMember;

use Bio::P3::Workspace::WorkspaceClientExt;

use Data::Dumper;
use strict;
use vars qw( $VERSION @ISA );

BEGIN {
    $VERSION = '1.68';
    @ISA     = qw ( Bio::P3::Workspace::WSFileMember );
}

use Archive::Zip qw(
  :CONSTANTS
  :ERROR_CODES
  :UTILITY_METHODS
);

# Given a file name, set up for eventual writing.
sub _newFromFileNamed {
    my $class    = shift;
    my $fileName = shift;    # local FS format
    my $newName  = shift;
    my $meta_cache = shift;
    my $ws = shift;

    $ws //= Bio::P3::Workspace::WorkspaceClientExt->new();
    
    $newName = _asZipDirName($fileName) unless defined($newName);

    my $meta = $meta_cache->{$fileName};
    my $stat;
    if ($meta)
    {
	$stat = $ws->convert_meta_to_stat($meta);
    }
    else
    {
	$stat = $ws->stat($fileName);
    }

    return undef if (!$stat);

    # Need better checks for readability
    # return undef unless (stat($fileName) && -r _ && !-d _ );
    #
    my $self = $class->new(@_);
    $self->{ws} = $ws;
    $self->{meta} = $meta;
    $self->{'fileName'}          = $newName;
    $self->{'externalFileName'}  = $fileName;
    $self->{'compressionMethod'} = COMPRESSION_STORED;

    $self->{'compressedSize'} = $self->{'uncompressedSize'} = $stat->size;
    $self->desiredCompressionMethod(
        ($self->compressedSize() > 0)
        ? COMPRESSION_DEFLATED
        : COMPRESSION_STORED
    );
    $self->unixFileAttributes($stat->mode);
    $self->setLastModFileDateTimeFromUnix($stat->mtime);
    #$self->isTextFile(-T _ );
    $self->isTextFile(0);
    return $self;
}

sub rewindData {
    my $self = shift;

    my $status = $self->SUPER::rewindData(@_);
    return $status unless $status == AZ_OK;

    return AZ_IO_ERROR unless $self->fh();
    $self->fh()->clearerr();
#    $self->fh()->seek(0, IO::Seekable::SEEK_SET)
#      or return _ioError("rewinding", $self->externalFileName());
    return AZ_OK;
}

# Return bytes read. Note that first parameter is a ref to a buffer.
# my $data;
# my ( $bytesRead, $status) = $self->readRawChunk( \$data, $chunkSize );
sub _readRawChunk {
    my ($self, $dataRef, $chunkSize) = @_;
#     print "READ $chunkSize\n";
    return (0, AZ_OK) unless $chunkSize;
    my $bytesRead = $self->fh()->read($$dataRef, $chunkSize);
    if (!$bytesRead && $!)
    {
	return (0, _ioError("reading data"));
    }
#    print "$bytesRead $$dataRef\n";
    return ($bytesRead, AZ_OK);
}

# If I already exist, extraction is a no-op.
sub extractToFileNamed {
    my $self = shift;
    my $name = shift;    # local FS name
    if (File::Spec->rel2abs($name) eq
        File::Spec->rel2abs($self->externalFileName()) and -r $name) {
        return AZ_OK;
    } else {
        return $self->SUPER::extractToFileNamed($name, @_);
    }
}

1;
