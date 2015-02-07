use Bio::P3::Workspace::WorkspaceImpl;

use Plack::Builder;
use strict;

my $impl = Bio::P3::Workspace::WorkspaceImpl->new();

$impl->_download_service_start();

builder { 
    mount '/download' => sub { $impl->_download_request(@_); };
};

