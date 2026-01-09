package Bio::P3::Workspace::FUSE;

#
# FUSE filesystem driver for BV-BRC Workspace.
# Provides read-write access to workspace files via a FUSE mount.
#

use strict;
use warnings;
use Fuse;
use POSIX qw(ENOENT ENOTDIR EISDIR EACCES EIO ENOTEMPTY EROFS EBADF EEXIST);
use Fcntl qw(:mode);
use Bio::P3::Workspace::WorkspaceClientExt;
use Bio::P3::Workspace::Cache;
use P3AuthToken;
use Date::Parse qw(str2time);
use Data::Dumper;
use File::Temp;
use File::Spec;
use File::Basename;

sub new {
    my ($class, %opts) = @_;

    my $self = bless {
        ws        => Bio::P3::Workspace::WorkspaceClientExt->new($opts{url}),
        token     => $opts{token} || P3AuthToken->new(),
        cache     => Bio::P3::Workspace::Cache->new(%{$opts{cache} || {}}),
        admin     => $opts{admin} || 0,
        root_path => $opts{root_path} || '/',
        uid       => $opts{uid} // $<,
        gid       => $opts{gid} // $(+0,
        debug     => $opts{debug} || 0,
        # Write support
        read_only   => $opts{read_only} || 0,
        temp_dir    => $opts{temp_dir} || File::Temp::tempdir(CLEANUP => 1),
        open_files  => {},   # { fh_id => { path, mode, temp_file, dirty } }
        next_fh     => 1,
    }, $class;

    # Normalize root_path - remove trailing slash
    $self->{root_path} =~ s|/$||;

    return $self;
}

#
# Map local FUSE path to workspace path
#
sub _ws_path {
    my ($self, $local_path) = @_;

    return $self->{root_path} if $local_path eq '/';

    my $ws_path = $self->{root_path} . $local_path;
    $ws_path =~ s|//+|/|g;

    return $ws_path;
}

#
# Debug logging
#
sub _debug {
    my ($self, @msg) = @_;
    return unless $self->{debug};
    print STDERR "[FUSE] ", @msg, "\n";
}

#
# Parse ISO8601 timestamp to epoch seconds
#
sub _parse_timestamp {
    my ($ts) = @_;
    return 0 unless $ts;
    my $epoch = str2time($ts);
    return $epoch || 0;
}

#
# Check if object type is a directory
#
sub _is_directory {
    my ($type) = @_;
    return ($type eq 'folder' || $type eq 'modelfolder' || $type eq 'model_folder');
}

#
# FUSE: getattr - get file/directory attributes (stat)
#
sub getattr {
    my ($self, $path) = @_;

    $self->_debug("getattr: $path");

    my $ws_path = $self->_ws_path($path);

    # Handle mount root specially if it's a user-level path
    if ($path eq '/') {
        # Return directory attributes for root
        return $self->_make_dir_stat(0);
    }

    # Check cache first
    my $cached = $self->{cache}->get_metadata($ws_path);
    if ($cached) {
        return $self->_meta_to_stat($cached);
    }

    # Fetch from API
    my $meta;
    eval {
        my $res = $self->{ws}->get({
            objects => [$ws_path],
            metadata_only => 1,
            adminmode => $self->{admin}
        });
        if ($res && $res->[0] && $res->[0]->[0] && defined($res->[0]->[0]->[0])) {
            $meta = $res->[0]->[0];
        }
    };
    if ($@) {
        $self->_debug("getattr error: $@");
    }

    return -ENOENT() unless $meta;

    $self->{cache}->set_metadata($ws_path, $meta);
    return $self->_meta_to_stat($meta);
}

#
# Convert ObjectMeta to stat array
#
sub _meta_to_stat {
    my ($self, $meta) = @_;

    my $type = $meta->[1] || '';
    my $is_dir = _is_directory($type);
    my $size = $meta->[6] || 0;
    my $mtime = _parse_timestamp($meta->[3]);
    my $user_perm = $meta->[9] || 'n';

    # Determine mode based on permissions and read_only setting
    my $mode;
    if ($is_dir) {
        if ($self->{read_only} || ($user_perm ne 'w' && $user_perm ne 'o' && $user_perm ne 'a')) {
            $mode = S_IFDIR | 0555;  # r-xr-xr-x
        } else {
            $mode = S_IFDIR | 0755;  # rwxr-xr-x
        }
    } else {
        if ($self->{read_only} || ($user_perm ne 'w' && $user_perm ne 'o' && $user_perm ne 'a')) {
            $mode = S_IFREG | 0444;  # r--r--r--
        } else {
            $mode = S_IFREG | 0644;  # rw-r--r--
        }
    }

    return (
        0,                           # dev
        0,                           # ino
        $mode,                       # mode
        1,                           # nlink
        $self->{uid},                # uid
        $self->{gid},                # gid
        0,                           # rdev
        $size,                       # size
        $mtime,                      # atime
        $mtime,                      # mtime
        $mtime,                      # ctime
        4096,                        # blksize
        int(($size + 511) / 512),    # blocks
    );
}

#
# Create stat array for a directory
#
sub _make_dir_stat {
    my ($self, $mtime) = @_;
    $mtime ||= time();

    my $mode = $self->{read_only} ? (S_IFDIR | 0555) : (S_IFDIR | 0755);

    return (
        0,                    # dev
        0,                    # ino
        $mode,                # mode
        2,                    # nlink
        $self->{uid},         # uid
        $self->{gid},         # gid
        0,                    # rdev
        4096,                 # size
        $mtime,               # atime
        $mtime,               # mtime
        $mtime,               # ctime
        4096,                 # blksize
        8,                    # blocks
    );
}

#
# FUSE: readdir - list directory contents
#
sub readdir {
    my ($self, $path, $offset) = @_;

    $self->_debug("readdir: $path");

    my $ws_path = $self->_ws_path($path);

    # Check cache
    my $cached = $self->{cache}->get_dir($ws_path);
    if ($cached) {
        return (@$cached, 0);
    }

    # Fetch from API
    my @entries = ('.', '..');
    eval {
        my $res = $self->{ws}->ls({
            paths => [$ws_path],
            adminmode => $self->{admin}
        });

        if ($res && $res->{$ws_path}) {
            for my $entry (@{$res->{$ws_path}}) {
                my $name = $entry->[0];
                push @entries, $name;

                # Pre-cache metadata for children
                my $parent_path = $entry->[2];
                my $child_path = $parent_path . $name;
                $self->{cache}->set_metadata($child_path, $entry);
            }
        }
    };
    if ($@) {
        $self->_debug("readdir error: $@");
        return -EIO();
    }

    $self->{cache}->set_dir($ws_path, \@entries);
    return (@entries, 0);
}

#
# FUSE: open - open a file
#
sub fuse_open {
    my ($self, $path, $flags) = @_;

    $self->_debug("open: $path, flags=$flags");

    my $access_mode = $flags & 3;  # O_RDONLY=0, O_WRONLY=1, O_RDWR=2

    # Check read-only mode
    if ($access_mode != 0 && $self->{read_only}) {
        return -EROFS();
    }

    # Verify the file exists
    my $ws_path = $self->_ws_path($path);
    my $meta = $self->{cache}->get_metadata($ws_path);

    unless ($meta) {
        eval {
            my $res = $self->{ws}->get({
                objects => [$ws_path],
                metadata_only => 1,
                adminmode => $self->{admin}
            });
            $meta = $res->[0]->[0] if $res && $res->[0] && $res->[0]->[0];
        };
    }

    return -ENOENT() unless $meta;

    # Check if it's a directory
    if (_is_directory($meta->[1])) {
        return -EISDIR();
    }

    # Check write permission
    if ($access_mode != 0) {
        my $user_perm = $meta->[9] || 'n';
        unless ($user_perm eq 'w' || $user_perm eq 'o' || $user_perm eq 'a') {
            return -EACCES();
        }
    }

    # Create file handle
    my $fh_id = $self->{next_fh}++;

    if ($access_mode != 0) {
        # Write mode - create temp file with current content
        my $temp_file = File::Spec->catfile($self->{temp_dir}, "fuse_$$\_$fh_id");

        # Download existing content if file has content
        my $file_size = $meta->[6] || 0;
        if ($file_size > 0) {
            eval {
                $self->_download_to_file($ws_path, $temp_file);
            };
            if ($@) {
                $self->_debug("download error: $@");
                return -EIO();
            }
        } else {
            # Create empty file
            open(my $fh, '>', $temp_file) or return -EIO();
            close($fh);
        }

        # Handle O_TRUNC
        if ($flags & 0x200) {  # O_TRUNC
            truncate($temp_file, 0);
        }

        $self->{open_files}{$fh_id} = {
            path => $ws_path,
            temp_file => $temp_file,
            dirty => 0,
            mode => $access_mode,
        };
    } else {
        $self->{open_files}{$fh_id} = {
            path => $ws_path,
            mode => $access_mode,
        };
    }

    return (0, $fh_id);
}

#
# FUSE: read - read file content
#
sub fuse_read {
    my ($self, $path, $size, $offset) = @_;

    $self->_debug("read: $path, size=$size, offset=$offset");

    my $ws_path = $self->_ws_path($path);

    # Get metadata to check for shock URL and file size
    my $meta = $self->{cache}->get_metadata($ws_path);
    unless ($meta) {
        eval {
            my $res = $self->{ws}->get({
                objects => [$ws_path],
                metadata_only => 1,
                adminmode => $self->{admin}
            });
            if ($res && $res->[0] && $res->[0]->[0]) {
                $meta = $res->[0]->[0];
                $self->{cache}->set_metadata($ws_path, $meta);
            }
        };
    }
    return -ENOENT() unless $meta;

    my $file_size = $meta->[6] || 0;
    my $shock_url = $meta->[11];

    # Handle read past end of file
    return '' if $offset >= $file_size;

    # Adjust size if reading past end
    if ($offset + $size > $file_size) {
        $size = $file_size - $offset;
    }

    my $content;

    if ($shock_url) {
        # Large file via Shock - use range request
        $self->_debug("read from shock: $shock_url, offset=$offset, size=$size");
        eval {
            # shock_read_bytes uses the token stored in the ws client
            $content = $self->{ws}->shock_read_bytes(
                $shock_url,
                $offset,
                $size
            );
        };
        if ($@) {
            $self->_debug("shock read error: $@");
            return -EIO();
        }
    } else {
        # Small file (inline storage) - get full content, cache it
        my $full = $self->{cache}->get_content($ws_path);

        unless ($full) {
            $self->_debug("fetching inline content for: $ws_path");
            eval {
                my $res = $self->{ws}->get({
                    objects => [$ws_path],
                    metadata_only => 0,
                    adminmode => $self->{admin}
                });
                if ($res && $res->[0] && defined($res->[0]->[1])) {
                    my $data = $res->[0]->[1];
                    $full = \$data;
                    $self->{cache}->set_content($ws_path, $full);
                }
            };
            if ($@) {
                $self->_debug("content fetch error: $@");
                return -EIO();
            }
        }

        return -EIO() unless $full;
        $content = substr($$full, $offset, $size);
    }

    return defined($content) ? $content : -EIO();
}

#
# FUSE: statfs - get filesystem statistics
#
sub statfs {
    my ($self) = @_;

    $self->_debug("statfs");

    # Return reasonable defaults for a remote filesystem
    # Values: bsize, frsize, blocks, bfree, bavail, files, ffree, favail, fsid, flag, namemax
    return (
        4096,        # block size
        4096,        # fragment size
        1000000,     # total blocks
        500000,      # free blocks
        500000,      # available blocks
        1000000,     # total inodes
        999999,      # free inodes
        999999,      # available inodes
        0,           # filesystem id
        0,           # mount flags
        255,         # max name length
    );
}

#
# FUSE: access - check file access permissions
#
sub access {
    my ($self, $path, $mode) = @_;

    $self->_debug("access: $path, mode=$mode");

    # mode: 0=F_OK, 1=X_OK, 2=W_OK, 4=R_OK
    if ($mode & 2) {  # W_OK
        # Check if read-only mode
        return -EROFS() if $self->{read_only};
    }

    # Check if file exists
    my $ws_path = $self->_ws_path($path);
    my $meta = $self->{cache}->get_metadata($ws_path);

    unless ($meta) {
        eval {
            my $res = $self->{ws}->get({
                objects => [$ws_path],
                metadata_only => 1,
                adminmode => $self->{admin}
            });
            $meta = $res->[0]->[0] if $res && $res->[0] && $res->[0]->[0];
        };
    }

    return -ENOENT() unless $meta;

    # Check write permission if requested
    if ($mode & 2) {
        my $user_perm = $meta->[9] || 'n';
        unless ($user_perm eq 'w' || $user_perm eq 'o' || $user_perm eq 'a') {
            return -EACCES();
        }
    }

    return 0;  # Access granted
}

#
# FUSE: mknod - create a file
#
sub fuse_mknod {
    my ($self, $path, $mode, $dev) = @_;

    $self->_debug("mknod: $path");
    return -EROFS() if $self->{read_only};

    my $ws_path = $self->_ws_path($path);

    eval {
        # Create empty file in workspace
        $self->{ws}->create({
            objects => [[$ws_path, 'unspecified', {}, '']],
            overwrite => 0,
            adminmode => $self->{admin}
        });
    };
    if ($@) {
        $self->_debug("mknod error: $@");
        return -EEXIST() if $@ =~ /exists/i;
        return -EIO();
    }

    # Invalidate parent directory cache
    my $parent = dirname($ws_path);
    $self->{cache}->invalidate($parent);
    $self->{cache}->invalidate_dir($parent);

    return 0;
}

#
# FUSE: create - create and open a file (called instead of mknod+open)
#
sub fuse_create {
    my ($self, $path, $mode, $flags) = @_;

    $self->_debug("create: $path, mode=$mode, flags=$flags");
    return -EROFS() if $self->{read_only};

    my $ws_path = $self->_ws_path($path);

    eval {
        # Create empty file in workspace
        $self->{ws}->create({
            objects => [[$ws_path, 'unspecified', {}, '']],
            overwrite => 0,
            adminmode => $self->{admin}
        });
    };
    if ($@) {
        $self->_debug("create error: $@");
        return -EEXIST() if $@ =~ /exists/i;
        return -EIO();
    }

    # Invalidate parent directory cache
    my $parent = dirname($ws_path);
    $self->{cache}->invalidate($parent);
    $self->{cache}->invalidate_dir($parent);

    # Create file handle for write
    my $fh_id = $self->{next_fh}++;
    my $temp_file = File::Spec->catfile($self->{temp_dir}, "fuse_$$\_$fh_id");

    # Create empty temp file
    open(my $fh, '>', $temp_file) or return -EIO();
    close($fh);

    $self->{open_files}{$fh_id} = {
        path => $ws_path,
        temp_file => $temp_file,
        dirty => 0,
        mode => 1,  # write mode
    };

    return (0, $fh_id);
}

#
# FUSE: mkdir - create a directory
#
sub fuse_mkdir {
    my ($self, $path, $mode) = @_;

    $self->_debug("mkdir: $path");
    return -EROFS() if $self->{read_only};

    my $ws_path = $self->_ws_path($path);

    eval {
        $self->{ws}->create({
            objects => [[$ws_path, 'folder', {}]],
            adminmode => $self->{admin}
        });
    };
    if ($@) {
        $self->_debug("mkdir error: $@");
        return -EEXIST() if $@ =~ /exists/i;
        return -EIO();
    }

    # Invalidate parent directory cache
    my $parent = dirname($ws_path);
    $self->{cache}->invalidate($parent);
    $self->{cache}->invalidate_dir($parent);

    return 0;
}

#
# FUSE: unlink - delete a file
#
sub fuse_unlink {
    my ($self, $path) = @_;

    $self->_debug("unlink: $path");
    return -EROFS() if $self->{read_only};

    my $ws_path = $self->_ws_path($path);

    eval {
        $self->{ws}->delete({
            objects => [$ws_path],
            adminmode => $self->{admin}
        });
    };
    if ($@) {
        $self->_debug("unlink error: $@");
        return -ENOENT() if $@ =~ /not found/i;
        return -EIO();
    }

    # Invalidate caches
    $self->{cache}->invalidate($ws_path);
    my $parent = dirname($ws_path);
    $self->{cache}->invalidate_dir($parent);

    return 0;
}

#
# FUSE: rmdir - delete a directory
#
sub fuse_rmdir {
    my ($self, $path) = @_;

    $self->_debug("rmdir: $path");
    return -EROFS() if $self->{read_only};

    my $ws_path = $self->_ws_path($path);

    eval {
        $self->{ws}->delete({
            objects => [$ws_path],
            deleteDirectories => 1,
            force => 0,  # Fail if not empty
            adminmode => $self->{admin}
        });
    };
    if ($@) {
        $self->_debug("rmdir error: $@");
        return -ENOTEMPTY() if $@ =~ /not empty/i;
        return -ENOENT() if $@ =~ /not found/i;
        return -EIO();
    }

    # Invalidate caches
    $self->{cache}->invalidate($ws_path);
    $self->{cache}->invalidate_dir($ws_path);
    my $parent = dirname($ws_path);
    $self->{cache}->invalidate_dir($parent);

    return 0;
}

#
# FUSE: rename - rename/move a file or directory
#
sub fuse_rename {
    my ($self, $old_path, $new_path) = @_;

    $self->_debug("rename: $old_path -> $new_path");
    return -EROFS() if $self->{read_only};

    my $old_ws_path = $self->_ws_path($old_path);
    my $new_ws_path = $self->_ws_path($new_path);

    eval {
        $self->{ws}->copy({
            objects => [[$old_ws_path, $new_ws_path]],
            move => 1,
            overwrite => 1,
            adminmode => $self->{admin}
        });
    };
    if ($@) {
        $self->_debug("rename error: $@");
        return -ENOENT() if $@ =~ /not found/i;
        return -EIO();
    }

    # Invalidate all affected caches
    $self->{cache}->invalidate($old_ws_path);
    $self->{cache}->invalidate($new_ws_path);
    $self->{cache}->invalidate_dir(dirname($old_ws_path));
    $self->{cache}->invalidate_dir(dirname($new_ws_path));

    return 0;
}

#
# FUSE: write - write to a file
#
sub fuse_write {
    my ($self, $path, $data, $offset, $fh_id) = @_;

    $self->_debug("write: $path, offset=$offset, size=" . length($data) . ", fh=$fh_id");

    my $handle = $self->{open_files}{$fh_id};
    return -EBADF() unless $handle;
    return -EBADF() unless $handle->{temp_file};

    # Write to temp file
    open(my $fh, '+<', $handle->{temp_file}) or return -EIO();
    binmode($fh);
    seek($fh, $offset, 0);
    my $written = syswrite($fh, $data);
    close($fh);

    $handle->{dirty} = 1;

    return defined($written) ? $written : -EIO();
}

#
# FUSE: truncate - truncate a file
#
sub fuse_truncate {
    my ($self, $path, $size) = @_;

    $self->_debug("truncate: $path, size=$size");
    return -EROFS() if $self->{read_only};

    my $ws_path = $self->_ws_path($path);

    if ($size == 0) {
        # Truncate to zero - just replace with empty content
        eval {
            $self->{ws}->create({
                objects => [[$ws_path, 'unspecified', {}, '']],
                overwrite => 1,
                adminmode => $self->{admin}
            });
        };
        if ($@) {
            $self->_debug("truncate error: $@");
            return -EIO();
        }
        $self->{cache}->invalidate($ws_path);
        return 0;
    }

    # Non-zero truncate requires downloading, truncating, re-uploading
    my $temp_file = File::Temp->new(UNLINK => 1);
    eval {
        $self->_download_to_file($ws_path, $temp_file->filename);
    };
    if ($@) {
        $self->_debug("truncate download error: $@");
        return -EIO();
    }

    truncate($temp_file->filename, $size);

    eval {
        $self->_upload_file($temp_file->filename, $ws_path);
    };
    if ($@) {
        $self->_debug("truncate upload error: $@");
        return -EIO();
    }

    $self->{cache}->invalidate($ws_path);
    return 0;
}

#
# FUSE: flush - flush file data (called before release)
#
sub fuse_flush {
    my ($self, $path, $fh_id) = @_;

    $self->_debug("flush: $path, fh=$fh_id");

    my $handle = $self->{open_files}{$fh_id};
    return 0 unless $handle && $handle->{dirty};

    # Upload the modified file
    eval {
        $self->_upload_file($handle->{temp_file}, $handle->{path});
    };
    if ($@) {
        $self->_debug("flush upload error: $@");
        return -EIO();
    }

    $handle->{dirty} = 0;
    $self->{cache}->invalidate($handle->{path});

    return 0;
}

#
# FUSE: release - close a file handle
#
sub fuse_release {
    my ($self, $path, $flags, $fh_id) = @_;

    $self->_debug("release: $path, fh=$fh_id");

    my $handle = delete $self->{open_files}{$fh_id};
    return 0 unless $handle;

    # Clean up temp file
    if ($handle->{temp_file} && -e $handle->{temp_file}) {
        unlink $handle->{temp_file};
    }

    return 0;
}

#
# Helper: Download workspace file to local file
#
sub _download_to_file {
    my ($self, $ws_path, $local_file) = @_;
    $self->{ws}->download_file($ws_path, $local_file, 1);
}

#
# Helper: Upload local file to workspace
#
sub _upload_file {
    my ($self, $local_file, $ws_path) = @_;

    my $size = -s $local_file;
    my $use_shock = ($size > 10_000);  # Use shock for files > 10KB

    $self->{ws}->save_file_to_file(
        $local_file,
        {},                  # metadata
        $ws_path,
        'unspecified',       # type
        1,                   # overwrite
        $use_shock,
        $self->{ws}->{token}
    );
}

#
# Run the FUSE main loop
#
sub run {
    my ($self, $mountpoint) = @_;

    $self->_debug("Starting FUSE main loop on $mountpoint");
    $self->_debug("Root path: $self->{root_path}");
    $self->_debug("Read-only: $self->{read_only}");
    $self->_debug("Temp dir: $self->{temp_dir}");

    Fuse::main(
        mountpoint  => $mountpoint,
        getattr     => sub { $self->getattr(@_) },
        readdir     => sub { $self->readdir(@_) },
        open        => sub { $self->fuse_open(@_) },
        read        => sub { $self->fuse_read(@_) },
        write       => sub { $self->fuse_write(@_) },
        create      => sub { $self->fuse_create(@_) },
        mknod       => sub { $self->fuse_mknod(@_) },
        mkdir       => sub { $self->fuse_mkdir(@_) },
        unlink      => sub { $self->fuse_unlink(@_) },
        rmdir       => sub { $self->fuse_rmdir(@_) },
        rename      => sub { $self->fuse_rename(@_) },
        truncate    => sub { $self->fuse_truncate(@_) },
        flush       => sub { $self->fuse_flush(@_) },
        release     => sub { $self->fuse_release(@_) },
        statfs      => sub { $self->statfs(@_) },
        access      => sub { $self->access(@_) },
        threaded    => 0,  # Single-threaded for simplicity
        debug       => $self->{debug},
    );
}

1;

__END__

=head1 NAME

Bio::P3::Workspace::FUSE - FUSE filesystem driver for BV-BRC Workspace

=head1 SYNOPSIS

    use Bio::P3::Workspace::FUSE;

    my $fuse = Bio::P3::Workspace::FUSE->new(
        root_path => '/user@example.org/home',
        url       => 'https://p3.theseed.org/services/Workspace',
        admin     => 0,
        debug     => 1,
        read_only => 0,
        temp_dir  => '/tmp/ws-fuse',
        cache     => { metadata_ttl => 60 },
    );

    $fuse->run('/mnt/workspace');

=head1 DESCRIPTION

Provides a read-write FUSE filesystem interface to the BV-BRC Workspace service.
Files and directories in the workspace can be accessed and modified using standard
Unix commands (ls, cat, cp, mkdir, rm, etc.) through the mounted filesystem.

=head1 METHODS

=over 4

=item new(%opts)

Create a new FUSE driver. Options:

  root_path  - Workspace path to mount (e.g., '/user@example.org/home')
  url        - Workspace service URL
  admin      - Enable admin mode (default: 0)
  debug      - Enable debug output (default: 0)
  read_only  - Mount as read-only (default: 0)
  temp_dir   - Directory for temporary write buffers (default: auto-created)
  cache      - Hash of cache options (metadata_ttl, dir_ttl, content_ttl)
  uid        - UID for mounted files (default: current user)
  gid        - GID for mounted files (default: current group)

=item run($mountpoint)

Mount the filesystem and run the FUSE main loop. This method blocks until
the filesystem is unmounted.

=back

=head1 SUPPORTED OPERATIONS

=head2 Read Operations

=over 4

=item * getattr - stat files and directories

=item * readdir - list directory contents

=item * open - open files

=item * read - read file contents (supports range reads for large files)

=item * statfs - filesystem statistics

=item * access - check access permissions

=back

=head2 Write Operations

=over 4

=item * create/mknod - create new files

=item * mkdir - create directories

=item * write - write to files

=item * truncate - truncate files

=item * unlink - delete files

=item * rmdir - delete directories

=item * rename - rename/move files and directories

=item * flush/release - commit changes and close files

=back

=head1 LIMITATIONS

=over 4

=item * Full file replacement: The Workspace API does not support partial writes.
Modified files are buffered locally and uploaded in their entirety when closed.

=item * Temp space: Modifying files requires local disk space for buffering.

=item * No locking: Concurrent modifications from multiple sources may cause data loss.

=item * Latency: Write operations have significant latency due to full-file uploads.

=back

=cut
