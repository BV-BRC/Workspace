use strict vars;
use Test::More;
use Test::Exception;
use Config::Simple;

my($cfg, $url, );
my $username = 'brettin';

if (defined $ENV{KB_DEPLOYMENT_CONFIG} && -e $ENV{KB_DEPLOYMENT_CONFIG}) {
    $cfg = new Config::Simple($ENV{KB_DEPLOYMENT_CONFIG}) or
	die "can not create Config object";
    pass "using $ENV{KB_DEPLOYMENT_CONFIG} for configs";
}
else {
    $cfg = new Config::Simple(syntax=>'ini');
    $cfg->param('Workspace.service-host', '127.0.0.1');
    $cfg->param('Workspace.service-port', '7125');
    pass "using hardcoded Config values";
}

$url = "http://" . $cfg->param('Workspace.service-host') . 
	  ":" . $cfg->param('Workspace.service-port');

ok(system("curl -h > /dev/null 2>&1") == 0, "curl is installed");
ok(system("curl $url > /dev/null 2>&1") == 0, "$url is reachable");

BEGIN {
	use_ok( Bio::P3::Workspace::WorkspaceClient );
	use_ok( Bio::P3::Workspace::WorkspaceImpl );
}



# create a client
my $obj;
isa_ok ($obj = Bio::P3::Workspace::WorkspaceClient->new(), Bio::P3::Workspace::WorkspaceClient);

# check the interface
my @funcdefs = qw(
	create
        get
        ls
        copy
        delete
        set_permissions
        list_permissions
      );
can_ok( "Bio::P3::Workspace::WorkspaceClient", @funcdefs);
diag("API supports ", join ", ", @funcdefs);

done_testing();
