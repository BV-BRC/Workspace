use Bio::P3::Workspace::WorkspaceImpl;

use strict;

my $impl = Bio::P3::Workspace::WorkspaceImpl->new();

$impl->_download_service_start();

sub { $impl->_download_request(@_); };


