#!/usr/bin/env perl

#
# p3-mount-ws - Mount a BV-BRC workspace as a FUSE filesystem
#

use strict;
use warnings;
use Getopt::Long::Descriptive;
use Bio::P3::Workspace::FUSE;
use P3AuthToken;
use POSIX qw(setsid);
use File::Basename;

=head1 NAME

p3-mount-ws - Mount a BV-BRC workspace as a FUSE filesystem

=head1 SYNOPSIS

    p3-mount-ws [options] <workspace-path> <mountpoint>

    # Mount your home workspace
    p3-mount-ws /user@example.org/home ~/ws-mount

    # Mount entire user directory
    p3-mount-ws /user@example.org ~/ws-mount

    # Mount with debug output
    p3-mount-ws -f -d /user@example.org/home ~/ws-mount

    # Unmount
    fusermount -u ~/ws-mount

=head1 DESCRIPTION

Mounts a BV-BRC Workspace path as a local filesystem using FUSE.
This allows you to access and modify workspace files using standard Unix commands
like ls, cat, cp, mkdir, rm, etc.

By default, the filesystem is mounted read-write. Use --read-only for read-only access.

=head1 OPTIONS

=over 4

=item -f, --foreground

Run in foreground (don't daemonize). Useful for debugging.

=item -d, --debug

Enable debug output. Implies --foreground.

=item -r, --read-only

Mount as read-only filesystem. Write operations will fail with EROFS.

=item --temp-dir=DIR

Directory for temporary write buffers. Default: auto-created temp directory.

=item -A, --admin

Run in admin mode (requires admin privileges).

=item --url=URL

Workspace service URL. Uses default if not specified.

=item --cache-ttl=SECONDS

Metadata cache TTL in seconds (default: 60).

=item --allow-empty

Allow mounting on a non-empty directory.

=item -h, --help

Show this help message.

=back

=cut

my ($opt, $usage) = describe_options(
    "%c %o <workspace-path> <mountpoint>",
    ["Mount a BV-BRC workspace path as a local filesystem"],
    [],
    ["foreground|f", "Run in foreground (don't daemonize)"],
    ["debug|d",      "Enable debug output (implies foreground)"],
    ["read-only|r",  "Mount as read-only filesystem"],
    ["temp-dir=s",   "Directory for temporary write buffers"],
    ["admin|A",      "Run in admin mode"],
    ["url=s",        "Workspace service URL"],
    ["cache-ttl=i",  "Cache TTL in seconds", { default => 60 }],
    ["allow-empty",  "Allow mounting on non-empty directory"],
    [],
    ["help|h",       "Show this help message"],
);

print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV != 2;

my ($ws_path, $mountpoint) = @ARGV;

# Debug implies foreground
my $foreground = $opt->foreground || $opt->debug;

# Validate authentication
my $token = P3AuthToken->new();
unless ($token->token()) {
    die "You must be logged in via p3-login to mount a workspace.\n";
}

# Validate workspace path
unless ($ws_path =~ m|^/|) {
    die "Workspace path must be absolute (start with /)\n";
}

# Validate mountpoint
unless (-d $mountpoint) {
    die "Mountpoint $mountpoint does not exist or is not a directory\n";
}

# Check if mountpoint is empty
unless ($opt->allow_empty) {
    opendir(my $dh, $mountpoint) or die "Cannot open $mountpoint: $!\n";
    my @entries = grep { $_ ne '.' && $_ ne '..' } readdir($dh);
    closedir($dh);
    if (@entries) {
        die "Mountpoint $mountpoint is not empty. Use --allow-empty to override.\n";
    }
}

# Check if already mounted
if (-f "/proc/mounts") {
    open(my $mounts, "<", "/proc/mounts");
    while (<$mounts>) {
        if (/\s\Q$mountpoint\E\s/) {
            die "Something is already mounted at $mountpoint\n";
        }
    }
    close($mounts);
}

# Create FUSE driver
my $fuse = Bio::P3::Workspace::FUSE->new(
    url       => $opt->url,
    root_path => $ws_path,
    admin     => $opt->admin,
    debug     => $opt->debug,
    read_only => $opt->read_only,
    temp_dir  => $opt->temp_dir,
    token     => $token,
    cache     => {
        metadata_ttl => $opt->cache_ttl,
        dir_ttl      => int($opt->cache_ttl / 2),
        content_ttl  => $opt->cache_ttl * 5,
    },
);

# Daemonize unless foreground mode
if (!$foreground) {
    my $pid = fork();
    if (!defined $pid) {
        die "Fork failed: $!\n";
    }
    if ($pid) {
        # Parent
        print "Mounted $ws_path on $mountpoint (pid $pid)\n";
        print "To unmount: fusermount -u $mountpoint\n";
        exit 0;
    }

    # Child - daemonize
    setsid() or die "setsid failed: $!\n";

    # Close standard file handles
    open(STDIN, "<", "/dev/null");
    open(STDOUT, ">", "/dev/null");
    open(STDERR, ">", "/dev/null");

    # Change to root directory to avoid holding any directory open
    chdir("/");
}

# Install signal handlers
$SIG{INT} = $SIG{TERM} = sub {
    print STDERR "Received signal, unmounting...\n" if $opt->debug;
    exit 0;
};

$SIG{HUP} = sub {
    print STDERR "Received SIGHUP, clearing cache...\n" if $opt->debug;
    $fuse->{cache}->clear();
};

# Run FUSE main loop
if ($foreground) {
    my $mode = $opt->read_only ? "read-only" : "read-write";
    print "Mounting $ws_path on $mountpoint ($mode)...\n";
    print "Press Ctrl+C to unmount, or use: fusermount -u $mountpoint\n";
}

$fuse->run($mountpoint);

__END__

=head1 EXAMPLES

=head2 Basic usage

    # Login first
    p3-login

    # Create a mountpoint
    mkdir -p ~/ws

    # Mount your home workspace (read-write)
    p3-mount-ws /myuser@patricbrc.org/home ~/ws

    # Now use standard commands
    ls ~/ws
    cat ~/ws/myfile.txt
    cp ~/ws/data.fasta /tmp/

    # Create files and directories
    echo "Hello" > ~/ws/newfile.txt
    mkdir ~/ws/newfolder

    # Unmount when done
    fusermount -u ~/ws

=head2 Read-only mount

    # Mount as read-only
    p3-mount-ws -r /myuser@patricbrc.org/home ~/ws

=head2 Debugging

    # Run in foreground with debug output
    p3-mount-ws -f -d /myuser@patricbrc.org/home ~/ws

=head2 Clear cache without unmounting

    # Send SIGHUP to clear the cache
    kill -HUP $(pgrep -f "p3-mount-ws.*$HOME/ws")

=head1 NOTES

=over 4

=item * By default, the filesystem is mounted read-write. Use -r for read-only.

=item * Write operations buffer files locally and upload on close (flush).

=item * Large files are streamed directly from Shock storage with range request support.

=item * Metadata and directory listings are cached for performance (default: 60s TTL).

=item * Send SIGHUP to the mount process to clear the cache.

=item * Modified files require local temp space equal to the file size.

=back

=head1 SEE ALSO

L<p3-ls>, L<p3-cat>, L<p3-cp>, L<fusermount(1)>

=cut
