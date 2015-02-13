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
print "Loading server with this config: ".$Bin."/../configs/test.cfg\n";

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
rmtree($ws->_db_path());
$ws->_mongodb()->get_collection('workspaces')->remove({});
$ws->_mongodb()->get_collection('objects')->remove({});

can_ok("Bio::P3::Workspace::WorkspaceImpl", qw(
    create
    get
    ls
    copy
    delete
    set_permissions
    list_permissions
    version
   )
);

#Creating a private workspace as "$testuserone"
my $output = $ws->create({
	objects => [["/reviewer/TestWorkspace","folder",{description => "My first workspace!"},undef]],
	permission => "n"
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully created a top level directory!";
print "create output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;

#Creating a public workspace as "$testusertwo"
$output = $ws->create({
	objects => [["/chenry/TestWorkspace","folder",{description => "My first workspace!"},undef]],
	permission => "r"
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully created a top level directory!";
print "create output:\n".Data::Dumper->Dump($output)."\n\n";
#Testing testusertwo acting as an adminitrator
$output = $ws->create({
	objects => [["/reviewer/TestAdminWorkspace","folder",{description => "My first admin workspace!"},undef]],
	permission => "r",
	adminmode => 1,
	setowner => "reviewer"
});
ok defined($output), "Successfully created a top level directory!";
print "create output:\n".Data::Dumper->Dump($output)."\n\n";
#Attempting to make a workspace for another user
$output = undef;
eval {
	$output = $ws->create({
		objects => [["/reviewer/TestWorkspace","folder",{description => "My second workspace!"},undef]],
		permission => "r"
	});
};
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok !defined($output), "Creating a top level directory for another user should fail!";
#Getting workspace metadata
$output = $ws->get({
	metadata_only => 1,
	objects => ["/chenry/TestWorkspace"]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully ran get function to retrieve workspace metadata!";
print "get output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "$testusertwo"
$output = $ws->ls({
	paths => [""]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{""}->[0]) && !defined($output->{""}->[1]), "Successfully ran ls function on got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump([$output])."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

#Listing workspaces as "$testuserone"
$output = $ws->ls({
	paths => [""]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{""}->[1]), "Successfully ran ls function on got two workspaces back!";
print "ls output:\n".Data::Dumper->Dump([$output])."\n\n";

#Listing workspaces as "$testuserone" but restricting to owned only
$output = $ws->ls({
	paths => ["/$testuserone/"]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{"/$testuserone/"}->[0]) && !defined($output->{"/$testuserone/"}->[1]), "Successfully ran ls function and got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump([$output])."\n\n";

#Saving an object
$output = $ws->create({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/testobj","unspecified",{"Description" => "My first object!"},{key1 => "data",key2 => "data"}]]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->[0]), "Successfully ran save_objects action!";
print "save_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Creating shock nodes
$output = $ws->create({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/shockobj","string",{"Description" => "My first shock object!"}]],
	createUploadNodes => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->[0]), "Successfully ran create_upload_node action!";
print "create_upload_node output:\n".Data::Dumper->Dump($output)."\n\n";

#Uploading file to newly created shock node
print "Filename:".$Bin."/testdata.txt\n";
my $req = HTTP::Request::Common::POST($output->[0]->[11],Authorization => "OAuth ".$ctxone->{token},Content_Type => 'multipart/form-data',Content => [upload => [$Bin."/testdata.txt"]]);
$req->method('PUT');
my $ua = LWP::UserAgent->new();
my $res = $ua->request($req);
print "File uploaded:\n".Data::Dumper->Dump([$res])."\n\n";

#Retrieving shock object through workspace API
$output = $ws->get({
	objects => ["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/shockobj"]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->[0]), "Successfully ran get function!";
print "get_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing objects
$output = $ws->ls({
	paths => ["/$testuserone/TestWorkspace/testdir/testdir2"],
	excludeDirectories => 0,
	excludeObjects => 0,
	recursive => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{"/$testuserone/TestWorkspace/testdir/testdir2"}), "Successfully listed all workspace contents!";
print "ls output:\n".Data::Dumper->Dump([$output])."\n\n";
$output = $ws->ls({
	paths => ["/$testuserone/TestWorkspace"],
	excludeDirectories => 0,
	excludeObjects => 0,
	recursive => 0
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{"/$testuserone/TestWorkspace"}->[0]) && !defined($output->{"/$testuserone/TestWorkspace"}->[1]), "Successfuly listed workspace contents nonrecursively!";
print "list_workspace_contents output:\n".Data::Dumper->Dump([$output])."\n\n";
$output = $ws->ls({
	paths => ["/$testuserone/TestWorkspace"],
	excludeDirectories => 1,
	excludeObjects => 0,
	recursive => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{"/$testuserone/TestWorkspace"}->[0]) && !defined($output->{"/$testuserone/TestWorkspace"}->[2]), "Successfully listed workspace contents without directories!";
print "list_workspace_contents output:\n".Data::Dumper->Dump([$output])."\n\n";
$output = $ws->ls({
	paths => ["/$testuserone/TestWorkspace"],
	excludeDirectories => 0,
	excludeObjects => 1,
	recursive => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{"/$testuserone/TestWorkspace"}->[2]) && !defined($output->{"/$testuserone/TestWorkspace"}->[3]), "Successfully listed workspace contents without objects!";
print "list_workspace_contents output:\n".Data::Dumper->Dump([$output])."\n\n";

#Listing objects hierarchically
$output = $ws->ls({
	paths => ["/$testuserone/TestWorkspace"],
	excludeDirectories => 0,
	excludeObjects => 0,
	recursive => 1,
	fullHierachicalOutput => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{"/$testuserone/TestWorkspace"}) && defined($output->{"/$testuserone/TestWorkspace/testdir"}), "Successfully listed workspace contents hierarchically!";
print "list_workspace_hierarchical_contents output:\n".Data::Dumper->Dump([$output])."\n\n";

#Copying workspace object
$output = undef;
eval {
$output = $ws->copy({
	objects => [["/$testuserone/TestWorkspace/testdir","/$testusertwo/TestWorkspace/copydir"]],
	recursive => 1
});
};
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok !defined($output), "Copying to a read only workspace fails!";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;

#Changing workspace permissions
$output = $ws->set_permissions({
	path => "/$testusertwo/TestWorkspace",
	permissions => [[$testuserone,"w"]]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully ran set_workspace_permissions function!";
print "set_workspace_permissions output:\n".Data::Dumper->Dump($output)."\n\n";
#Listing workspace permission
$output = $ws->list_permissions({
	objects => ["/$testusertwo/TestWorkspace"]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{"/$testusertwo/TestWorkspace"}->[0]), "Successfully ran list_workspace_permissions function!";
print "list_workspace_permissions output:\n".Data::Dumper->Dump([$output])."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

#Copying workspace object
$output = $ws->copy({
	objects => [["/$testuserone/TestWorkspace/testdir","/$testusertwo/TestWorkspace/copydir"]],
	recursive => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully ran copy_objects function!";
print "copy_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing contents of workspace with copied objects
$output = $ws->ls({
	paths => ["/$testusertwo/TestWorkspace"],
	excludeDirectories => 0,
	excludeObjects => 0,
	recursive => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->{"/$testusertwo/TestWorkspace"}->[0]), "Successfully listed workspace contents!";
print "list_workspace_contents output:\n".Data::Dumper->Dump([$output])."\n\n";

#Changing global workspace permissions
$output = $ws->set_permissions({
	path => "/$testuserone/TestWorkspace",
	new_global_permission => "w"
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully changed global permissions!";
print "reset_global_permission output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user two
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;

#Moving objects
$output = $ws->copy({
	objects => [["/$testusertwo/TestWorkspace/copydir","/$testuserone/TestWorkspace/movedir"]],
	recursive => 1,
	move => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully ran copy to move objects!";
print "move_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

#Deleting an object
$output = $ws->delete({
	objects => ["/$testuserone/TestWorkspace/movedir/testdir2/testdir3/testobj","/$testuserone/TestWorkspace/movedir/testdir2/testdir3/shockobj"]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully ran delete_objects function on object!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";

$output = $ws->delete({
	objects => ["/$testuserone/TestWorkspace/movedir/testdir2/testdir3"],
	deleteDirectories => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully ran delete_objects function on directory!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Deleting a directory
$output = $ws->delete({
	objects => ["/$testuserone/TestWorkspace/movedir"],
	force => 1,
	deleteDirectories => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully ran delete_workspace_directory function!";
print "delete_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Creating a directory
$output = $ws->create({
	objects => [["/$testuserone/TestWorkspace/emptydir","folder",{},undef]]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully ran create_workspace_directory function!";
print "create_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Getting an object
$output = $ws->get({
	objects => ["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/testobj"]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->[0]->[1]), "Successfully ran get_objects function!";
print "get_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Getting an object by reference
$output = $ws->get({
	objects => [$output->[0]->[0]->[4]]
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output->[0]->[1]), "Successfully ran get_objects_by_reference function!";
print "get_objects_by_reference output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

#Deleting workspaces
$output = $ws->delete({
	objects => ["/$testuserone/TestWorkspace"],
	force => 1,
	deleteDirectories => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";
#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;
$output = $ws->delete({
	objects => ["/$testusertwo/TestWorkspace"],
	force => 1,
	deleteDirectories => 1
});
delete $ctxtwo->{_wscache};
delete $ctxone->{_wscache};
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