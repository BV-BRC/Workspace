package Bio::P3::Workspace::Cache;

#
# Caching layer for Workspace FUSE filesystem.
# Provides TTL-based LRU caching for metadata, directory listings, and file content.
#

use strict;
use warnings;
use Time::HiRes qw(time);

sub new {
    my ($class, %opts) = @_;
    return bless {
        # Cache storage: { key => { data => $data, expires => $time } }
        metadata_cache => {},
        content_cache  => {},
        dir_cache      => {},

        # Size limits
        metadata_size  => $opts{metadata_size} || 10000,
        content_size   => $opts{content_size} || 1000,
        dir_size       => $opts{dir_size} || 5000,

        # TTL in seconds
        metadata_ttl   => $opts{metadata_ttl} || 60,     # 60 seconds
        dir_ttl        => $opts{dir_ttl} || 30,          # 30 seconds
        content_ttl    => $opts{content_ttl} || 300,     # 5 minutes

        # Access order tracking for LRU eviction
        metadata_order => [],
        content_order  => [],
        dir_order      => [],
    }, $class;
}

#
# Get cached metadata for a path
# Returns ObjectMeta arrayref or undef if not cached/expired
#
sub get_metadata {
    my ($self, $path) = @_;
    return $self->_get_from_cache('metadata', $path);
}

#
# Cache metadata for a path
#
sub set_metadata {
    my ($self, $path, $meta) = @_;
    $self->_set_in_cache('metadata', $path, $meta);
}

#
# Get cached directory listing
# Returns arrayref of entry names or undef
#
sub get_dir {
    my ($self, $path) = @_;
    return $self->_get_from_cache('dir', $path);
}

#
# Cache directory listing
#
sub set_dir {
    my ($self, $path, $entries) = @_;
    $self->_set_in_cache('dir', $path, $entries);
}

#
# Get cached file content
# Returns scalar ref to content or undef
#
sub get_content {
    my ($self, $path) = @_;
    return $self->_get_from_cache('content', $path);
}

#
# Cache file content (for small files only)
#
sub set_content {
    my ($self, $path, $content) = @_;
    $self->_set_in_cache('content', $path, $content);
}

#
# Invalidate a specific cache entry
#
sub invalidate {
    my ($self, $path) = @_;
    delete $self->{metadata_cache}{$path};
    delete $self->{dir_cache}{$path};
    delete $self->{content_cache}{$path};
}

#
# Invalidate directory cache only (for write operations)
#
sub invalidate_dir {
    my ($self, $path) = @_;
    delete $self->{dir_cache}{$path};
}

#
# Clear all caches
#
sub clear {
    my ($self) = @_;
    $self->{metadata_cache} = {};
    $self->{dir_cache} = {};
    $self->{content_cache} = {};
    $self->{metadata_order} = [];
    $self->{dir_order} = [];
    $self->{content_order} = [];
}

#
# Internal: Get from a specific cache type
#
sub _get_from_cache {
    my ($self, $type, $key) = @_;

    my $cache = $self->{"${type}_cache"};
    my $entry = $cache->{$key};

    return undef unless $entry;

    # Check TTL
    if (time() > $entry->{expires}) {
        delete $cache->{$key};
        return undef;
    }

    # Update access order for LRU
    $self->_touch_lru($type, $key);

    return $entry->{data};
}

#
# Internal: Set in a specific cache type
#
sub _set_in_cache {
    my ($self, $type, $key, $data) = @_;

    my $cache = $self->{"${type}_cache"};
    my $ttl = $self->{"${type}_ttl"};
    my $max_size = $self->{"${type}_size"};

    # Evict if at capacity
    while (scalar(keys %$cache) >= $max_size) {
        $self->_evict_lru($type);
    }

    $cache->{$key} = {
        data => $data,
        expires => time() + $ttl,
    };

    # Add to LRU order
    $self->_touch_lru($type, $key);
}

#
# Internal: Update LRU order for a key
#
sub _touch_lru {
    my ($self, $type, $key) = @_;

    my $order = $self->{"${type}_order"};

    # Remove existing entry
    @$order = grep { $_ ne $key } @$order;

    # Add to end (most recently used)
    push @$order, $key;
}

#
# Internal: Evict least recently used entry
#
sub _evict_lru {
    my ($self, $type) = @_;

    my $order = $self->{"${type}_order"};
    my $cache = $self->{"${type}_cache"};

    return unless @$order;

    # Remove oldest (first) entry
    my $oldest = shift @$order;
    delete $cache->{$oldest};
}

#
# Get cache statistics for debugging
#
sub stats {
    my ($self) = @_;
    return {
        metadata_count => scalar(keys %{$self->{metadata_cache}}),
        dir_count      => scalar(keys %{$self->{dir_cache}}),
        content_count  => scalar(keys %{$self->{content_cache}}),
    };
}

1;

__END__

=head1 NAME

Bio::P3::Workspace::Cache - Caching layer for Workspace FUSE filesystem

=head1 SYNOPSIS

    use Bio::P3::Workspace::Cache;

    my $cache = Bio::P3::Workspace::Cache->new(
        metadata_ttl => 60,    # seconds
        dir_ttl      => 30,
        content_ttl  => 300,
    );

    # Cache and retrieve metadata
    $cache->set_metadata('/user/workspace/file', $meta);
    my $meta = $cache->get_metadata('/user/workspace/file');

    # Cache directory listings
    $cache->set_dir('/user/workspace', ['.', '..', 'file1', 'file2']);
    my $entries = $cache->get_dir('/user/workspace');

    # Cache file content (small files only)
    $cache->set_content('/user/workspace/small.txt', \$content);
    my $content_ref = $cache->get_content('/user/workspace/small.txt');

=head1 DESCRIPTION

Provides TTL-based LRU caching for the Workspace FUSE filesystem.
Three separate caches are maintained:

=over 4

=item * Metadata cache - ObjectMeta arrays, 60s TTL, 10000 entries

=item * Directory cache - Entry name lists, 30s TTL, 5000 entries

=item * Content cache - File contents (small files), 300s TTL, 1000 entries

=back

=cut
