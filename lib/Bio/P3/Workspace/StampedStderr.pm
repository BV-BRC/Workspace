package Bio::P3::Workspace::StampedStderr;

#
# Prefix every line written to STDERR with a timestamp and pid.
#
# Why this exists: during the 2026-09-24 download-service stall
# investigation, the error log was the only record of what the service
# was doing internally, but it had no timestamps of its own. The stall
# could only be located because a leftover debug statement happened to
# Dumper the Shock response headers, which include an HTTP 'date'
# header -- that accident was the clock. Correlating the error log
# against the access log and against external probes depended on it.
#
# Rather than timestamp individual print statements (which the next
# person will forget to do), this ties into STDERR itself, so warn(),
# die() messages, Data::Dumper output and any print STDERR are all
# covered.
#
# Usage, as early as possible in a .psgi or script:
#
#     use Bio::P3::Workspace::StampedStderr;
#     Bio::P3::Workspace::StampedStderr->install();
#
# Format:  [2026-09-25 11:42:03.118 CDT 31337] original line
#
# Notes:
#  - Partial writes are buffered until a newline arrives, so a line
#    assembled from several prints gets exactly one stamp rather than
#    one per fragment. Data::Dumper emits multi-line output in a single
#    write, and each of its lines is stamped.
#  - Autoflush is enabled so ordering against other logs is preserved.
#  - Failure to install is non-fatal: an unstamped log is much better
#    than a service that will not start.
#

use strict;
use warnings;

use POSIX qw(strftime);
use Time::HiRes qw(gettimeofday);

our $VERSION = '1.00';

my $installed = 0;

sub install
{
    my($class) = @_;

    return 1 if $installed;

    # Keep the real STDERR; the tied handle writes through to it.
    open(my $real_stderr, '>&', \*STDERR)
        or do {
            # Nothing we can do but carry on unstamped.
            print STDERR "StampedStderr: cannot dup STDERR: $!\n";
            return 0;
        };

    # Unbuffered, so lines appear in order relative to other logs.
    select((select($real_stderr), $| = 1)[0]);

    my $ok = eval {
        tie *STDERR, 'Bio::P3::Workspace::StampedStderr', $real_stderr;
        1;
    };
    if (!$ok)
    {
        print $real_stderr "StampedStderr: tie failed: $@";
        return 0;
    }

    $installed = 1;
    return 1;
}

sub timestamp
{
    my($sec, $usec) = gettimeofday();
    return sprintf("%s.%03d %s",
                   strftime("%Y-%m-%d %H:%M:%S", localtime($sec)),
                   $usec / 1000,
                   strftime("%Z", localtime($sec)));
}

#
# Tie implementation.
#

sub TIEHANDLE
{
    my($class, $fh) = @_;
    return bless { fh => $fh, partial => '' }, $class;
}

sub PRINT
{
    my $self = shift;
    $self->_emit(join(defined $, ? $, : '', @_) . (defined $\ ? $\ : ''));
    return 1;
}

sub PRINTF
{
    my $self = shift;
    my $fmt  = shift;
    $self->_emit(sprintf($fmt, @_));
    return 1;
}

sub WRITE
{
    my($self, $buf, $len, $offset) = @_;
    $offset ||= 0;
    $len = length($buf) - $offset if !defined $len;
    $self->_emit(substr($buf, $offset, $len));
    return 1;
}

sub _emit
{
    my($self, $text) = @_;
    return if !defined $text || $text eq '';

    # Accumulate until we have complete lines, so a line built from
    # several prints is stamped once rather than mid-line.
    $self->{partial} .= $text;

    my $fh = $self->{fh};
    my $stamp;

    while ((my $nl = index($self->{partial}, "\n")) >= 0)
    {
        my $line = substr($self->{partial}, 0, $nl + 1, '');
        $stamp = timestamp() if !defined $stamp;
        print $fh "[$stamp $$] $line";
    }
}

# Flush any trailing partial line so nothing is silently lost.
sub _flush_partial
{
    my($self) = @_;
    return if !length($self->{partial});
    my $fh = $self->{fh};
    print $fh "[" . timestamp() . " $$] " . $self->{partial} . "\n";
    $self->{partial} = '';
}

sub CLOSE
{
    my($self) = @_;
    $self->_flush_partial;
    return close($self->{fh});
}

sub BINMODE { return 1 }

sub FILENO
{
    my($self) = @_;
    return fileno($self->{fh});
}

sub DESTROY
{
    my($self) = @_;
    eval { $self->_flush_partial };
}

1;
