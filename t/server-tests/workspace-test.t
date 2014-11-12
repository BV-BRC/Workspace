use Test::More;
use Config::Simple;
use JSON;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceImpl;
use Bio::KBase::AuthToken;
use File::Path;
my $test_count = 29;

BEGIN {
	use_ok( Bio::P3::Workspace::WorkspaceImpl );
}

my $params = {
	"shock-url" => "140.221.67.190:7078",
	"db-path" => "/Users/chenry/P3WSDB/",
	"mongodb-database" => "P3Workspace",
	"mongodb-host" => "localhost",
	"mongodb-user" => undef,
	"mongodb-pwd" => undef
};

my $tokenObj = Bio::KBase::AuthToken->new(
    user_id => 'kbasetest', password => '@Suite525'
);
my $tokenone = $tokenObj->token();
my $ws = Bio::P3::Workspace::WorkspaceImpl->new($params);
$ws->_authenticate($tokenObj->token());
$tokenObj = Bio::KBase::AuthToken->new(
    user_id => 'kbasetest2', password => '@Suite525'
);
my $tokentwo = $tokenObj->token();

print "DBPath:".$ws->_db_path()."\n";
rmtree($ws->_db_path());
$ws->_mongodb()->get_collection('workspaces')->remove({});
$ws->_mongodb()->get_collection('objects')->remove({});

can_ok("Bio::P3::Workspace::WorkspaceImpl", qw(
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

#Creating a private workspace as "kbasetest"
my $output = $ws->create_workspace({
	workspace => "TestWorkspace",
	permission => "n",
	metadata => {description => "My first workspace!"}
});
ok defined($output), "Successfully ran create_workspace function!";
print "create_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

$ws->_authenticate($tokentwo);

#Creating a public workspace as "kbasetest2"
$output = $ws->create_workspace({
	workspace => "TestWorkspace",
	permission => "r",
	metadata => {description => "My first workspace!"}
});
ok defined($output), "Successfully ran create_workspace function!";
print "create_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "kbasetest2"
$output = $ws->list_workspaces({});
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces function on got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

$ws->_authenticate($tokenone);

#Listing workspaces as "kbasetest"
$output = $ws->list_workspaces({});
ok defined($output->[1]), "Successfully ran list_workspaces function on got two workspaces back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "kbasetest" but restricting to owned only
$output = $ws->list_workspaces({
	owned_only => 1
});
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces unction and got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "kbasetest" but restricting to private only
$output = $ws->list_workspaces({
	owned_only => 0,
	no_public => 1
});
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces unction and got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Saving an object
$output = $ws->save_objects({
	objects => [["/kbasetest/TestWorkspace/testdir/testdir2/testdir3/","testobj","my test object data","String",{"Description" => "My first object!"}]]
});
ok defined($output->[0]), "Successfully ran save_objects action!";
print "save_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing objects
$output = $ws->list_workspace_contents({
	directory => "/kbasetest/TestWorkspace/testdir/testdir2",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->[1]), "Successfully listed all workspace contents!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $ws->list_workspace_contents({
	directory => "/kbasetest/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 0
});
ok defined($output->[0]) && !defined($output->[1]), "Successfuly listed workspace contents nonrecursively!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $ws->list_workspace_contents({
	directory => "/kbasetest/TestWorkspace",
	includeSubDirectories => 0,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->[0]) && !defined($output->[1]), "Successfully listed workspace contents without directories!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $ws->list_workspace_contents({
	directory => "/kbasetest/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 1,
	Recursive => 1
});
ok defined($output->[2]) && !defined($output->[3]), "Successfully listed workspace contents without objects!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing objects hierarchically
$output = $ws->list_workspace_hierarchical_contents({
	directory => "/kbasetest/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->{"/kbasetest/TestWorkspace"}) && defined($output->{"/kbasetest/TestWorkspace/testdir"}), "Successfully listed workspace contents hierarchically!";
print "list_workspace_hierarchical_contents output:\n".Data::Dumper->Dump([$output])."\n\n";

#Copying workspace object
$output = undef;
eval {
$output = $ws->copy_objects({
	objects => [["/kbasetest/TestWorkspace","testdir","/kbasetest2/TestWorkspace","copydir"]],
	recursive => 1
});
};
ok !defined($output), "Copying to a read only workspace fails!";

#Changing workspace permissions
$ws->_authenticate($tokentwo);
$output = $ws->set_workspace_permissions({
	workspace => "TestWorkspace",
	permissions => [["kbasetest","w"]]
});
ok defined($output), "Successfully ran set_workspace_permissions function!";
print "set_workspace_permissions output:\n".Data::Dumper->Dump($output)."\n\n";
#Listing workspace permission
$output = $ws->list_workspace_permissions({
	workspaces => ["/kbasetest2/TestWorkspace"]
});
ok defined($output->{"/kbasetest2/TestWorkspace"}->[0]), "Successfully ran list_workspace_permissions function!";
print "list_workspace_permissions output:\n".Data::Dumper->Dump([$output])."\n\n";
#Copying workspace object
$ws->_authenticate($tokenone);
$output = $ws->copy_objects({
	objects => [["/kbasetest/TestWorkspace","testdir","/kbasetest2/TestWorkspace","copydir"]],
	recursive => 1
});
ok defined($output), "Successfully ran copy_objects function!";
print "copy_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing contents of workspace with copied objects
$output = $ws->list_workspace_contents({
	directory => "/kbasetest2/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->[1]), "Successfully listed workspace contents!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";

#Changing global workspace permissions
$output = $ws->reset_global_permission({
	workspace => "/kbasetest/TestWorkspace",
	global_permission => "w"
});
ok defined($output), "Successfully changed global permissions!";
print "reset_global_permission output:\n".Data::Dumper->Dump($output)."\n\n";

#Moving objects
$ws->_authenticate($tokentwo);
$output = $ws->move_objects({
	objects => [["/kbasetest2/TestWorkspace","copydir","/kbasetest/TestWorkspace","movedir"]],
	recursive => 1
});
ok defined($output), "Successfully ran move_objects function!";
print "move_objects output:\n".Data::Dumper->Dump($output)."\n\n";
#Deleting an object
$ws->_authenticate($tokenone);
$output = $ws->delete_objects({
	objects => [["/kbasetest/TestWorkspace/movedir/testdir2/testdir3","testobj"]]
});
ok defined($output), "Successfully ran delete_objects function on object!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $ws->delete_objects({
	objects => [["/kbasetest/TestWorkspace/movedir/testdir2","testdir3"]],
	delete_directories => 1
});
ok defined($output), "Successfully ran delete_objects function on directory!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";
#Deleting a directory
$output = $ws->delete_workspace_directory({
	directory => "/kbasetest/TestWorkspace/movedir",
	force => 1
});
ok defined($output), "Successfully ran delete_workspace_directory function!";
print "delete_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Creating a directory
$output = $ws->create_workspace_directory({
	directory => "/kbasetest/TestWorkspace/emptydir"
});
ok defined($output), "Successfully ran create_workspace_directory function!";
print "create_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Getting an object
$output = $ws->get_objects({
	objects => [["/kbasetest/TestWorkspace/testdir/testdir2/testdir3","testobj"]]
});
ok defined($output->[0]->{data}), "Successfully ran get_objects function!";
print "get_objects output:\n".Data::Dumper->Dump($output)."\n\n";
#Getting an object by reference
$output = $ws->get_objects_by_reference({
	objects => [$output->[0]->{info}->[0]]
});
ok defined($output->[0]->{data}), "Successfully ran get_objects_by_reference function!";
print "get_objects_by_reference output:\n".Data::Dumper->Dump($output)."\n\n";
#Deleting workspaces
$ws->_authenticate($tokenone);
$output = $ws->delete_workspace({
	workspace => "/kbasetest/TestWorkspace"
});
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";
$ws->_authenticate($tokentwo);
$output = $ws->delete_workspace({
	workspace => "TestWorkspace"
});
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

done_testing($test_count);
