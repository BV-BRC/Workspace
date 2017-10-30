use Bio::P3::Workspace::WorkspaceImpl;
use Plack::Middleware::CrossOrigin;

use strict;

my $impl = Bio::P3::Workspace::WorkspaceImpl->new();

$impl->_download_service_start();

my $handler = sub { $impl->_download_request(@_); };

Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*");


