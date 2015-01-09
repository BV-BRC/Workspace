
use strict vars;
use Test::More;
use Test::Exception;
use Config::Simple;
use JSON;
use Data::Dumper;
use UUID;

my($cfg, $url, );

if (defined $ENV{KB_DEPLOYMENT_CONFIG} && -e $ENV{KB_DEPLOYMENT_CONFIG}) {
    $cfg = new Config::Simple($ENV{KB_DEPLOYMENT_CONFIG}) or
	die "can not create Config object";
    pass "using $ENV{KB_DEPLOYMENT_CONFIG} for configs";
}
else {
    $cfg = new Config::Simple(syntax=>'ini');
    $cfg->param('workspace.service-host', '127.0.0.1');
    $cfg->param('workspace.service-port', '7125');
    pass "using hardcoded Config values";
}

$url = "http://" . $cfg->param('workspace.service-host') . 
	  ":" . $cfg->param('workspace.service-port');

ok(system("curl -h > /dev/null 2>&1") == 0, "curl is installed");
ok(system("curl $url > /dev/null 2>&1") == 0, "$url is reachable");

BEGIN {
	use_ok( Bio::P3::Workspace::WorkspaceClient );
	use_ok( Bio::P3::Workspace::WorkspaceImpl );
}

# create a client
my $obj;
isa_ok ($obj = Bio::P3::Workspace::WorkspaceClient->new(), Bio::P3::Workspace::WorkspaceClient);

# create a workspace for each permission value and then delete it
my $full_obj_path = '/' . 'brettin' . '/' . new_uuid("brettin");
my $obj_type = 'folder'; # folder, 
my $user_meta = undef;
my $obj_data = undef;

my $object = [$full_obj_path, $obj_type, $user_meta, $obj_data];
my $objects = [$object];
my $perm = 'w';
my $cun = undef;
my $dl = undef;
my $ow = undef;
my $create_params = {
	objects => $objects,
	permission => $perm,
	createUploadNodes => $cun,
	downloadLinks => $dl,
	overwrite => $ow
};
#    metadata => {'owner' => 'brettin'},
#};

# create a ws
ok($obj->create($create_params), "can call create");

# create a duplicate ws
# ok($obj->create($create_params), "can call create");

{
  # create a ws and check return is defined, contains arrays, and has values
  my $full_obj_path = '/' . 'brettin' . '/' . new_uuid("brettin");
  my $obj_type = 'folder'; # folder, 
  my $user_meta = undef;
  my $obj_data = undef;

  my $object = [$full_obj_path, $obj_type, $user_meta, $obj_data];
  my $objects = [$object];
  my $perm = 'w';
  my $cun = undef;
  my $dl = undef;
  my $ow = undef;
  my $create_params = {
        objects => $objects,
        permission => $perm,
        createUploadNodes => $cun,
        downloadLinks => $dl,
        overwrite => $ow
  };

  my $output;

  ok($output = $obj->create($create_params), "create workspace returns output");
  ok(ref $output->[0] eq 'ARRAY', "output is contains arrays");
  ok($output->[0]->[0], "Object meta has name " . $output->[0]->[0]);
  ok($output->[0]->[1], "Object meta has type " . $output->[0]->[1]);
  ok($output->[0]->[2], "Object meta has path " . $output->[0]->[2]);
  ok($output->[0]->[3], "Object meta has timestamp " . $output->[0]->[3]);
  ok($output->[0]->[4], "Object meta has id " . $output->[0]->[4]);
  ok($output->[0]->[5], "Object meta has owner " . $output->[0]->[5]);
  ok($output->[0]->[6] == 0, "Object meta has size " . $output->[0]->[6]);
  ok($output->[0]->[7], "Object meta has user meta " . $output->[0]->[7]);
  ok($output->[0]->[8], "Object meta has auto meta " . $output->[0]->[8]);
  ok($output->[0]->[9], "Object meta has user perm " . $output->[0]->[9]);
  ok($output->[0]->[10], "Object meta has global perm " . $output->[0]->[10]);
  ok($output->[0]->[11] eq '',  "Object meta has shock url " . $output->[0]->[11]);



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
