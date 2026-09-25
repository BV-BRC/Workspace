use Bio::P3::Workspace::StampedStderr;
use Bio::P3::Workspace::WorkspaceImpl;
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


