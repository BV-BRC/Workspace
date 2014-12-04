use FindBin qw($Bin);
use Test::More;
use Config::Simple;
use JSON;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::KBase::AuthToken;
use File::Path;
use REST::Client;
use LWP::UserAgent;
use JSON::XS;
use HTTP::Request::Common;
my $test_count = 31;

BEGIN {
	use_ok( Bio::P3::Workspace::WorkspaceClient );
}

my $cfg;
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

my $url = "http://" . $cfg->param('workspace.service-host') . 
	  ":" . $cfg->param('workspace.service-port');

ok(system("curl -h > /dev/null 2>&1") == 0, "curl is installed");
ok(system("curl $url > /dev/null 2>&1") == 0, "$url is reachable");

my $testuserone = "reviewer";
my $tokenObj = Bio::KBase::AuthToken->new(
    user_id => $testuserone, password => 'reviewer',ignore_authrc => 1
);

my $wsone;
isa_ok ($wsone = Bio::P3::Workspace::WorkspaceClient->new($url,user_id => 'reviewer', password => 'reviewer'), Bio::P3::Workspace::WorkspaceClient);

my $wstwo;
isa_ok ($wstwo = Bio::P3::Workspace::WorkspaceClient->new($url,token => "un=chenry|tokenid=03B0C858-7A70-11E4-9DE6-FDA042A49C03|expiry=1449094224|client_id=chenry|token_type=Bearer|SigningSubject=http://rast.nmpdr.org/goauth/keys/E087E220-F8B1-11E3-9175-BD9D42A49C03|sig=085255b952c8db3ddd7e051ac4a729f719f22e531ddbc0a3edd86a895da851faa93249a7347c75324dc025b977e9ac7c4e02fb4c966ec6003ecf90d3148e35160265dbcdd235658deeed0ec4e0c030efee923fda1a55e8cc6f116bcd632fa6a576d7bf4a794554d2d914b54856e1e7ac2b071f81a8841d142123095f6af957cc"), Bio::P3::Workspace::WorkspaceClient);

can_ok("Bio::P3::Workspace::WorkspaceClient", qw(
    create_workspace
    save_objects
    create_upload_node
    get_objects
    get_objects_by_reference
    list_workspace_contents
    list_workspace_hierarchical_contents
    list_workspaces
    search_for_workspaces
    search_for_workspace_objects
    create_workspace_directory
    copy_objects
    move_objects
    delete_workspace
    delete_objects
    delete_workspace_directory
    reset_global_permission
    set_workspace_permissions
    list_workspace_permissions
    version
   )
);

#Creating a private workspace as "$testuserone"
my $output = $wsone->create_workspace({
	workspace => "TestWorkspace",
	permission => "n",
	metadata => {description => "My first workspace!"}
});
ok defined($output), "Successfully ran create_workspace function!";
print "create_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

#Creating a public workspace as "$testusertwo"
$output = $wstwo->create_workspace({
	workspace => "TestWorkspace",
	permission => "r",
	metadata => {description => "My first workspace!"}
});
ok defined($output), "Successfully ran create_workspace function!";
print "create_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "$testusertwo"
$output = $wstwo->list_workspaces({});
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces function on got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "$testuserone"
$output = $wsone->list_workspaces({});
ok defined($output->[1]), "Successfully ran list_workspaces function on got two workspaces back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "$testuserone" but restricting to owned only
$output = $wsone->list_workspaces({
	owned_only => 1
});
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces unction and got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "$testuserone" but restricting to private only
$output = $wsone->list_workspaces({
	owned_only => 0,
	no_public => 1
});
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces unction and got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Saving an object
$output = $wsone->save_objects({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/","testobj","my test object data","String",{"Description" => "My first object!"}]]
});
ok defined($output->[0]), "Successfully ran save_objects action!";
print "save_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Creating shock nodes
$output = $wsone->create_upload_node({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/","shockobj","String",{"Description" => "My first shock object!"}]]
});
ok defined($output->[0]), "Successfully ran create_upload_node action!";
print "create_upload_node output:\n".Data::Dumper->Dump($output)."\n\n";

#Uploading file to newly created shock node
print "Filename:".$Bin."/testdata.txt\n";
my $req = HTTP::Request::Common::POST($output->[0],Authorization => "OAuth ".$ctxone->{token},Content_Type => 'multipart/form-data',Content => [upload => [$Bin."/testdata.txt"]]);
$req->method('PUT');
my $ua = LWP::UserAgent->new();
my $res = $ua->request($req);
print "File uploaded:\n".Data::Dumper->Dump([$res])."\n\n";

#Retrieving shock object through workspace API
$output = $wsone->get_objects({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3","shockobj"]]
});
ok defined($output->[0]->{data}), "Successfully ran get_objects function!";
print "get_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing objects
$output = $wsone->list_workspace_contents({
	directory => "/$testuserone/TestWorkspace/testdir/testdir2",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->[1]), "Successfully listed all workspace contents!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $wsone->list_workspace_contents({
	directory => "/$testuserone/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 0
});
ok defined($output->[0]) && !defined($output->[1]), "Successfuly listed workspace contents nonrecursively!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $wsone->list_workspace_contents({
	directory => "/$testuserone/TestWorkspace",
	includeSubDirectories => 0,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->[0]) && !defined($output->[2]), "Successfully listed workspace contents without directories!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $wsone->list_workspace_contents({
	directory => "/$testuserone/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 1,
	Recursive => 1
});
ok defined($output->[2]) && !defined($output->[3]), "Successfully listed workspace contents without objects!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing objects hierarchically
$output = $wsone->list_workspace_hierarchical_contents({
	directory => "/$testuserone/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->{"/$testuserone/TestWorkspace"}) && defined($output->{"/$testuserone/TestWorkspace/testdir"}), "Successfully listed workspace contents hierarchically!";
print "list_workspace_hierarchical_contents output:\n".Data::Dumper->Dump([$output])."\n\n";

#Copying workspace object
$output = undef;
eval {
$output = $wstwo->copy_objects({
	objects => [["/$testuserone/TestWorkspace","testdir","/$testusertwo/TestWorkspace","copydir"]],
	recursive => 1
});
};
ok !defined($output), "Copying to a read only workspace fails!";

#Changing workspace permissions
$output = $wstwo->set_workspace_permissions({
	workspace => "TestWorkspace",
	permissions => [[$testuserone,"w"]]
});
ok defined($output), "Successfully ran set_workspace_permissions function!";
print "set_workspace_permissions output:\n".Data::Dumper->Dump($output)."\n\n";
#Listing workspace permission
$output = $wstwo->list_workspace_permissions({
	workspaces => ["/$testusertwo/TestWorkspace"]
});
ok defined($output->{"/$testusertwo/TestWorkspace"}->[0]), "Successfully ran list_workspace_permissions function!";
print "list_workspace_permissions output:\n".Data::Dumper->Dump([$output])."\n\n";

#Copying workspace object
$output = $wsone->copy_objects({
	objects => [["/$testuserone/TestWorkspace","testdir","/$testusertwo/TestWorkspace","copydir"]],
	recursive => 1
});
ok defined($output), "Successfully ran copy_objects function!";
print "copy_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing contents of workspace with copied objects
$output = $wsone->list_workspace_contents({
	directory => "/$testusertwo/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->[1]), "Successfully listed workspace contents!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";

#Changing global workspace permissions
$output = $wsone->reset_global_permission({
	workspace => "/$testuserone/TestWorkspace",
	global_permission => "w"
});
ok defined($output), "Successfully changed global permissions!";
print "reset_global_permission output:\n".Data::Dumper->Dump($output)."\n\n";

#Moving objects
$output = $wstwo->move_objects({
	objects => [["/$testusertwo/TestWorkspace","copydir","/$testuserone/TestWorkspace","movedir"]],
	recursive => 1
});
ok defined($output), "Successfully ran move_objects function!";
print "move_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Deleting an object
$output = $wsone->delete_objects({
	objects => [["/$testuserone/TestWorkspace/movedir/testdir2/testdir3","testobj"],["/$testuserone/TestWorkspace/movedir/testdir2/testdir3","shockobj"]]
});
ok defined($output), "Successfully ran delete_objects function on object!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $wsone->delete_objects({
	objects => [["/$testuserone/TestWorkspace/movedir/testdir2","testdir3"]],
	delete_directories => 1
});
ok defined($output), "Successfully ran delete_objects function on directory!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";
#Deleting a directory
$output = $wsone->delete_workspace_directory({
	directory => "/$testuserone/TestWorkspace/movedir",
	force => 1
});
ok defined($output), "Successfully ran delete_workspace_directory function!";
print "delete_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Creating a directory
$output = $wsone->create_workspace_directory({
	directory => "/$testuserone/TestWorkspace/emptydir"
});
ok defined($output), "Successfully ran create_workspace_directory function!";
print "create_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Getting an object
$output = $wsone->get_objects({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3","testobj"]]
});
ok defined($output->[0]->{data}), "Successfully ran get_objects function!";
print "get_objects output:\n".Data::Dumper->Dump($output)."\n\n";
#Getting an object by reference
$output = $wsone->get_objects_by_reference({
	objects => [$output->[0]->{info}->[0]]
});
ok defined($output->[0]->{data}), "Successfully ran get_objects_by_reference function!";
print "get_objects_by_reference output:\n".Data::Dumper->Dump($output)."\n\n";

#Deleting workspaces
$output = $wsone->delete_workspace({
	workspace => "/$testuserone/TestWorkspace"
});
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $wstwo->delete_workspace({
	workspace => "TestWorkspace"
});
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

done_testing($test_count);