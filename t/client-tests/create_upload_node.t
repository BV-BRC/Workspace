use strict vars;
use Test::More;
use Test::Exception;
use Config::Simple;
use UUID;

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



# create a workspace
my $perm = 'w';
my $create_workspace_params = {
    workspace => new_uuid("brettin"),
    permission => $perm,
    metadata => {'owner' => 'brettin'},
};

ok($obj->create_workspace($create_workspace_params), "can create workspace with perm=$perm");




# can create
my $create_upload_node_params = { objects => [["", "", "", ""]], overwrite => 1 }; 

my @v = ("/" . $username . "/" . $create_workspace_params->{workspace} . "/");        # this should be a valid ws path
my @w = ("", 'object_name');           # this is the object name
my @x = ("String", 'Genome', 'Unspecified', 'Directory');                # this is the object type
my @y = ({}, { 'comment' => 'for testing only' });

for (my $n=0; $n<1; $n++) {
  for (my $o=0; $o<2; $o++) {
    for (my $p=0; $p<4; $p++) {
      for (my $q=0; $q<2; $q++) {
        $create_upload_node_params->{objects}->[0]->[0] = $v[$n],
        $create_upload_node_params->{objects}->[0]->[1] = $w[$o],
        $create_upload_node_params->{objects}->[0]->[2] = $x[$p],
        $create_upload_node_params->{objects}->[0]->[3] = $y[$q],
	ok(my $ret = $obj->create_upload_node($create_upload_node_params),
           "can create_upload_node with $v[$n], $w[$o], $x[$p], $y[$q]");
      }
    }
  }
}




done_testing();



sub new_uuid {
        my $prefix = shift if @_;

        my($uuid, $string);
        UUID::generate($uuid);
        UUID::unparse($uuid, $string);

        my $return = $string;
        $return = $prefix . '-' . $string if defined $prefix;

        return $return;
}
