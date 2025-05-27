use Bio::P3::Workspace::WorkspaceImpl;
use Plack::Middleware::CrossOrigin;
use Plack::Builder;

use strict;

my $impl = Bio::P3::Workspace::WorkspaceImpl->new();

$impl->_download_service_start();

my $dl_handler = sub { $impl->_download_request(@_); };
my $view_handler = sub { $impl->_view_request(@_); };
my $set_auth_handler = sub { $impl->_set_auth_request(@_); };

my $handler = builder {
    mount "/download" => $dl_handler,
    mount "/view" => $view_handler,
    mount "/set-cookie-auth" => $set_auth_handler,
};

Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*");


