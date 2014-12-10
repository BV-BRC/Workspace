use FindBin qw($Bin);
use Test::More;
use Config::Simple;
use JSON;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceImpl;
use Bio::KBase::AuthToken;
use File::Path;
use REST::Client;
use LWP::UserAgent;
use JSON::XS;
use HTTP::Request::Common;
my $test_count = 31;

BEGIN {
	use_ok( Bio::P3::Workspace::WorkspaceImpl );
}

#if (!defined $ENV{KB_DEPLOYMENT_CONFIG} || !-e $ENV{KB_DEPLOYMENT_CONFIG}) {
    $ENV{KB_DEPLOYMENT_CONFIG}=$Bin."/../../configs/test.cfg";
#}
print $Bin."/../configs/test.cfg";

my $testuserone = "reviewer";
my $tokenObj = Bio::KBase::AuthToken->new(
    user_id => $testuserone, password => 'reviewer',ignore_authrc => 1
);
my $ctxone = Bio::P3::Workspace::ServiceContext->new($tokenObj->token(),"test",$testuserone);
my $testusertwo = "chenry";
my $ctxtwo = Bio::P3::Workspace::ServiceContext->new("un=chenry|tokenid=03B0C858-7A70-11E4-9DE6-FDA042A49C03|expiry=1449094224|client_id=chenry|token_type=Bearer|SigningSubject=http://rast.nmpdr.org/goauth/keys/E087E220-F8B1-11E3-9175-BD9D42A49C03|sig=085255b952c8db3ddd7e051ac4a729f719f22e531ddbc0a3edd86a895da851faa93249a7347c75324dc025b977e9ac7c4e02fb4c966ec6003ecf90d3148e35160265dbcdd235658deeed0ec4e0c030efee923fda1a55e8cc6f116bcd632fa6a576d7bf4a794554d2d914b54856e1e7ac2b071f81a8841d142123095f6af957cc","test",$testusertwo);

my $ws = Bio::P3::Workspace::WorkspaceImpl->new();

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

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

#Creating a private workspace as "$testuserone"
my $output = $ws->create_workspace({
	workspace => "TestWorkspace",
	permission => "n",
	metadata => {description => "My first workspace!"}
});
ok defined($output), "Successfully ran create_workspace function!";
print "create_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;

#Creating a public workspace as "$testusertwo"
$output = $ws->create_workspace({
	workspace => "TestWorkspace",
	permission => "r",
	metadata => {description => "My first workspace!"}
});
ok defined($output), "Successfully ran create_workspace function!";
print "create_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

#Getting workspace metadata
$output = $ws->get_workspace_meta({
	workspaces => ["/chenry/TestWorkspace"]
});
ok defined($output), "Successfully ran get_workspace_meta function!";
print "get_workspace_meta output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "$testusertwo"
$output = $ws->list_workspaces({});
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces function on got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

#Listing workspaces as "$testuserone"
$output = $ws->list_workspaces({});
ok defined($output->[1]), "Successfully ran list_workspaces function on got two workspaces back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "$testuserone" but restricting to owned only
$output = $ws->list_workspaces({
	owned_only => 1
});
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces unction and got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "$testuserone" but restricting to private only
$output = $ws->list_workspaces({
	owned_only => 0,
	no_public => 1
});
ok defined($output->[0]) && !defined($output->[1]), "Successfully ran list_workspaces unction and got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump($output)."\n\n";

#Saving an object
$output = $ws->save_objects({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/","testobj","my test object data","String",{"Description" => "My first object!"}]]
});
ok defined($output->[0]), "Successfully ran save_objects action!";
print "save_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Creating shock nodes
$output = $ws->create_upload_node({
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
$output = $ws->get_objects({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3","shockobj"]]
});
ok defined($output->[0]->{data}), "Successfully ran get_objects function!";
print "get_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing objects
$output = $ws->list_workspace_contents({
	directory => "/$testuserone/TestWorkspace/testdir/testdir2",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->[1]), "Successfully listed all workspace contents!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $ws->list_workspace_contents({
	directory => "/$testuserone/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 0
});
ok defined($output->[0]) && !defined($output->[1]), "Successfuly listed workspace contents nonrecursively!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $ws->list_workspace_contents({
	directory => "/$testuserone/TestWorkspace",
	includeSubDirectories => 0,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->[0]) && !defined($output->[2]), "Successfully listed workspace contents without directories!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $ws->list_workspace_contents({
	directory => "/$testuserone/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 1,
	Recursive => 1
});
ok defined($output->[2]) && !defined($output->[3]), "Successfully listed workspace contents without objects!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing objects hierarchically
$output = $ws->list_workspace_hierarchical_contents({
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
$output = $ws->copy_objects({
	objects => [["/$testuserone/TestWorkspace","testdir","/$testusertwo/TestWorkspace","copydir"]],
	recursive => 1
});
};
ok !defined($output), "Copying to a read only workspace fails!";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;

#Changing workspace permissions
$output = $ws->set_workspace_permissions({
	workspace => "TestWorkspace",
	permissions => [[$testuserone,"w"]]
});
ok defined($output), "Successfully ran set_workspace_permissions function!";
print "set_workspace_permissions output:\n".Data::Dumper->Dump($output)."\n\n";
#Listing workspace permission
$output = $ws->list_workspace_permissions({
	workspaces => ["/$testusertwo/TestWorkspace"]
});
ok defined($output->{"/$testusertwo/TestWorkspace"}->[0]), "Successfully ran list_workspace_permissions function!";
print "list_workspace_permissions output:\n".Data::Dumper->Dump([$output])."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

#Copying workspace object
$output = $ws->copy_objects({
	objects => [["/$testuserone/TestWorkspace","testdir","/$testusertwo/TestWorkspace","copydir"]],
	recursive => 1
});
ok defined($output), "Successfully ran copy_objects function!";
print "copy_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing contents of workspace with copied objects
$output = $ws->list_workspace_contents({
	directory => "/$testusertwo/TestWorkspace",
	includeSubDirectories => 1,
	excludeObjects => 0,
	Recursive => 1
});
ok defined($output->[1]), "Successfully listed workspace contents!";
print "list_workspace_contents output:\n".Data::Dumper->Dump($output)."\n\n";

#Changing global workspace permissions
$output = $ws->reset_global_permission({
	workspace => "/$testuserone/TestWorkspace",
	global_permission => "w"
});
ok defined($output), "Successfully changed global permissions!";
print "reset_global_permission output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user two
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;

#Moving objects
$output = $ws->move_objects({
	objects => [["/$testusertwo/TestWorkspace","copydir","/$testuserone/TestWorkspace","movedir"]],
	recursive => 1
});
ok defined($output), "Successfully ran move_objects function!";
print "move_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

#Deleting an object
$output = $ws->delete_objects({
	objects => [["/$testuserone/TestWorkspace/movedir/testdir2/testdir3","testobj"],["/$testuserone/TestWorkspace/movedir/testdir2/testdir3","shockobj"]]
});
ok defined($output), "Successfully ran delete_objects function on object!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";
$output = $ws->delete_objects({
	objects => [["/$testuserone/TestWorkspace/movedir/testdir2","testdir3"]],
	delete_directories => 1
});
ok defined($output), "Successfully ran delete_objects function on directory!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";
#Deleting a directory
$output = $ws->delete_workspace_directory({
	directory => "/$testuserone/TestWorkspace/movedir",
	force => 1
});
ok defined($output), "Successfully ran delete_workspace_directory function!";
print "delete_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Creating a directory
$output = $ws->create_workspace_directory({
	directory => "/$testuserone/TestWorkspace/emptydir"
});
ok defined($output), "Successfully ran create_workspace_directory function!";
print "create_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Getting an object
$output = $ws->get_objects({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3","testobj"]]
});
ok defined($output->[0]->{data}), "Successfully ran get_objects function!";
print "get_objects output:\n".Data::Dumper->Dump($output)."\n\n";
#Getting an object by reference
$output = $ws->get_objects_by_reference({
	objects => [$output->[0]->{info}->[0]]
});
ok defined($output->[0]->{data}), "Successfully ran get_objects_by_reference function!";
print "get_objects_by_reference output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

#Deleting workspaces
$output = $ws->delete_workspace({
	workspace => "/$testuserone/TestWorkspace"
});
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";
#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;
$output = $ws->delete_workspace({
	workspace => "TestWorkspace"
});
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

done_testing($test_count);

package Bio::P3::Workspace::ServiceContext;

use strict;

sub new {
    my($class,$token,$method,$user) = @_;
    my $self = {
        token => $token,
        method => $method,
        user_id => $user
    };
    return bless $self, $class;
}
sub user_id {
	my($self) = @_;
	return $self->{user_id};
}
sub token {
	my($self) = @_;
	return $self->{token};
}
sub method {
	my($self) = @_;
	return $self->{method};
}