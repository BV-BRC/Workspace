use Bio::P3::Workspace::WorkspaceImpl;

use Bio::P3::Workspace::Service;
use Plack::Middleware::CrossOrigin;



my @dispatch;

{
    my $obj = Bio::P3::Workspace::WorkspaceImpl->new;
    push(@dispatch, 'Workspace' => $obj);
}


my $server = Bio::P3::Workspace::Service->new(instance_dispatch => { @dispatch },
				allow_get => 0,
			       );

my $handler = sub { $server->handle_input(@_) };

$handler = Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*");
