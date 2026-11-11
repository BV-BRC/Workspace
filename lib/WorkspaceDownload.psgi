use Bio::P3::Workspace::StampedStderr;
use Bio::P3::Workspace::WorkspaceImpl;
use AnyEvent::HTTP;
use Plack::Middleware::CrossOrigin;
use Plack::Builder;
use Plack::Util;

use strict;

#
# Timestamp everything this service writes to download.error.log.
#
# Installed before anything else so startup warnings are covered too.
# Without this the error log has no clock of its own: the 2026-09-24
# stall could only be located because a leftover debug Dumper happened
# to include Shock's HTTP 'date' header. Do not rely on that again.
#
Bio::P3::Workspace::StampedStderr->install();

#
# Raise the AnyEvent::HTTP per-host connection limit.
#
# THIS IS THE FIX FOR THE 2026-09-24 DOWNLOAD STALL.
#
# AnyEvent::HTTP defaults $MAX_PER_HOST to 4 (HTTP.pm:59). Requests beyond
# that are not sent -- they queue in _slot_schedule until a connection
# closes. Every Shock fetch this service makes goes to the same hostname,
# so the default caps the WHOLE SERVICE at four concurrent Shock downloads.
# The fifth user to start a large download waits for one of the first four
# to finish, and because the service is a single Twiggy process, so does
# every other request behind it.
#
# Measured directly with the shock-fetch instrumentation, 20 concurrent
# downloads of a 253 MB file:
#
#   ttfb= 0.12  total= 5.62   <- generation 1 (4 requests)
#   ttfb= 5.72  total=11.38   <- generation 2 waits for generation 1
#   ttfb=11.41  total=16.85   <- generation 3
#   ttfb=16.86  total=22.43   <- generation 4
#   ttfb=22.47  total=27.87   <- generation 5
#
# The body transfer is a constant ~5.6s (~46 MB/s) throughout: the fetches
# are not slow, they are queued. ttfb climbs by one generation each time.
# That is why an unrelated probe doing nothing but an indexed Mongo lookup
# could stall ~10s, why Shock's own log showed it was never asked during
# the gaps, and why the host sat idle at ~7% CPU while "stalled".
#
# The module warns against raising this, but that advice is aimed at
# well-behaved web crawlers hitting third-party sites. This is a server
# talking to its own backend on the same machine; the politeness argument
# does not apply.
#
# Set to 16 rather than something larger, deliberately. The old default of
# 4 was inadvertently capping memory exposure: the Shock streaming path has
# NO BACKPRESSURE (on_body calls $writer->write and returns 1 regardless),
# and Twiggy::Writer::write is push_write into an unbounded buffer. The
# service pulls from Shock at ~46 MB/s while a slow client may drain at
# tens of KB/s, so each in-flight transfer can buffer most of its response
# in memory. With 253 MB objects the worst case scales directly:
#
#   MAX_PER_HOST=4  ->  ~1 GB       (the old, accidental, bound)
#   MAX_PER_HOST=16 ->  ~4 GB
#   MAX_PER_HOST=64 -> ~16 GB
#
# 16 is 4x the old concurrency, which is comfortably past the stall
# reproduced at 20 clients, while keeping the unbounded-buffer exposure
# to something survivable until backpressure is implemented properly.
#
# Note this limit is per-HOSTNAME, which is why it bites so hard here: the
# stored shocknode URLs all point at the public p3.theseed.org name rather
# than the local address, so every fetch shares one budget.
#
$AnyEvent::HTTP::MAX_PER_HOST = 16;

my $impl = Bio::P3::Workspace::WorkspaceImpl->new();

$impl->_download_service_start();

my $dl_handler = sub { $impl->_download_request(@_); };
my $old_dl_handler = sub { $impl->_download_request_orig(@_); };
my $view_handler = sub { $impl->_view_request(@_); };
my $set_auth_handler = sub { $impl->_set_auth_request(@_); };

my $handler = builder {
     mount "/download" => $dl_handler,
     mount "/view" => $view_handler,
     mount "/set-cookie-auth" => $set_auth_handler,
     mount "/" => $old_dl_handler,
 };

Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*", credentials => 1);


