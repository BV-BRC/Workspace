use Test::More;
use Config::Simple;
use JSON;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceImpl;
use Bio::KBase::AuthToken;
use File::Path;
my $test_count = 17;

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
my $output = $ws->create_workspace("TestWorkspace","n",{description => "My first workspace!"});
ok defined($output), "Successfully ran create_workspace function!";
print "create_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

$ws->_authenticate($tokentwo);

#Creating a public workspace as "kbasetest2"
$output = $ws->create_workspace("TestWorkspace","r",{description => "My first workspace!"});
ok defined($output), "Successfully ran create_workspace function!";
print "create_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "kbasetest2"
$output = $ws->list_workspaces();
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces function on got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

$ws->_authenticate($tokenone);

#Listing workspaces as "kbasetest"
$output = $ws->list_workspaces();
ok defined($output->[1]), "Successfully ran list_workspaces function on got two workspaces back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "kbasetest" but restricting to owned only
$output = $ws->list_workspaces(1);
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces unction and got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "kbasetest" but restricting to private only
$output = $ws->list_workspaces(0,1);
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces unction and got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Saving an object
$output = $ws->save_objects([["/kbasetest/TestWorkspace/testdir/","testobj","my test object data","String",{"Description" => "My first object!"}]]);
ok defined($output->[0]), "Successfully ran save_objects action!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Deleting workspaces
$output = $ws->delete_workspace("/kbasetest/TestWorkspace");
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";
$ws->_authenticate($tokentwo);
$output = $ws->delete_workspace("TestWorkspace");
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

done_testing($test_count);
