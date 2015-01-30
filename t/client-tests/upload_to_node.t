use strict vars;
use Test::More;
use Test::Exception;
use Config::Simple;
use UUID;
use Bio::KBase::AuthToken;
use Data::Dumper;

my($cfg, $url, );
my $username = 'brettin';
my $infile = "./t/client-tests/small-contigs.fasta.gz";

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

# the service is reachable
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
ok($obj->create_workspace($create_workspace_params), 
  "can create workspace with parameters\n" .
  Dumper $create_workspace_params );


# can create
my $create_upload_node_params = { objects => [[]], overwrite => 1 }; 
my $path = '/brettin/' . $create_workspace_params->{workspace} . '/';
my $obj_name = $infile;
my $obj_type = 'Contigs';
my %metadata = {owner => 'brettin', testonly => 1};
my $rnodes;
$create_upload_node_params->{objects}->[0]->[0] = $path,
$create_upload_node_params->{objects}->[0]->[1] = $obj_name,
$create_upload_node_params->{objects}->[0]->[2] = $obj_type,
$create_upload_node_params->{objects}->[0]->[3] = \%metadata,


ok($rnodes = $obj->create_upload_node($create_upload_node_params),
  "can create_upload_node with params\n" . 
  Dumper $create_upload_node_params .  "\n" .
  "and return is\n" .
  Dumper $rnodes );


# can put data to created node
my $auth_header;
ok(my $tok = Bio::KBase::AuthToken->new(), "can create token object");
$auth_header = "-H 'Authorization: OAuth $tok->{token}'" if $tok->{token};
my $cmd = "curl -s $auth_header -X PUT -F upload=\@$infile $rnodes->[0] > /dev/null";
ok(system($cmd) == 0, "can put data to shock node at\n  $rnodes->[0]");
# print $cmd;


# can see the data in the workspace
my $list_workspace_params = {
	directory => '/brettin/' . $create_workspace_params->{workspace} . '/',
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 1
};

my $output;
ok($output = $obj->list_workspace_contents($list_workspace_params), "can call list_workspace_contents");
print Dumper $output;
undef $output;

# can get data
my $ret;
my $get_objects_params = {
	objects => [[$path, $obj_name]],
	metadata_only => 1
};
ok($ret = $obj->get_objects($get_objects_params), "can call get_objects for metadata");
ok (ref $ret->[0]->{info} eq "ARRAY", "get_objects return info is array ref");
print Dumper $ret;


$get_objects_params->{metadata_only} = 0;
ok($ret = $obj->get_objects($get_objects_params), "can call get_objects for data");
ok (exists $ret->[0]->{data} , "data exists in get_objects return");
ok (defined $ret->[0]->{data} , "data defined in get_objects return");
# print Dumper $ret;


# done testing
done_testing();


# helper routines
sub new_uuid {
        my $prefix = shift if @_;

        my($uuid, $string);
        UUID::generate($uuid);
        UUID::unparse($uuid, $string);

        my $return = $string;
        $return = $prefix . '-' . $string if defined $prefix;

        return $return;
}
