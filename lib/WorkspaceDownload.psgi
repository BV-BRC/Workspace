use Bio::P3::Workspace::WorkspaceImpl;
use Plack::Middleware::CrossOrigin;
use Plack::Builder;
use Plack::Util;

use strict;

my $impl = Bio::P3::Workspace::WorkspaceImpl->new();

$impl->_download_service_start();

my $dl_handler = sub { $impl->_download_request(@_); };
my $view_handler = sub { $impl->_view_request(@_); };
my $set_auth_handler = sub { $impl->_set_auth_request(@_); };

my $handler = builder {
    enable sub {
	my $app = shift;
	
        return sub {
	    my $env = shift;
	    my $res = $app->($env);
	    
            my $origin = $env->{HTTP_ORIGIN};
	    
#            if ($origin && grep { $_ eq $origin } @allowed_origins) {
            if ($origin) {
		Plack::Util::response_cb($res, sub {
		    my $res = shift;
		    $res->[1] ||= [];
		    my $headers = Plack::Util::headers($res->[1]);
		    
                    $headers->set('Access-Control-Allow-Origin' => $origin);
		    $headers->set('Access-Control-Allow-Credentials' => 'true');
		    $headers->set('Access-Control-Allow-Methods' => 'GET, POST, OPTIONS');
		    $headers->set('Access-Control-Allow-Headers' => 'Authorization, Content-Type');
		});
	    }
	    
            return $res;
	};
    };
    mount "/download" => $dl_handler,
    mount "/view" => $view_handler,
    mount "/set-cookie-auth" => $set_auth_handler,
};

$handler;
#Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*");


