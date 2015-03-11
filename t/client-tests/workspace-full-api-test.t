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

if (!defined($ENV{P3WORKSPACEURL})) {
	$ENV{P3WORKSPACEURL} = "http://p3.theseed.org/services/Workspace";
}
my $url = $ENV{P3WORKSPACEURL};

ok(system("curl -h > /dev/null 2>&1") == 0, "curl is installed");
ok(system("curl $url > /dev/null 2>&1") == 0, "$url is reachable");

my $testuserone = "reviewer";
my $testusertwo = "chenry";
my $tokenObj = Bio::KBase::AuthToken->new(
    user_id => $testuserone, password => 'reviewer',ignore_authrc => 1
);

my $wsone;
isa_ok ($wsone = Bio::P3::Workspace::WorkspaceClient->new($url,user_id => 'reviewer', password => 'reviewer'), Bio::P3::Workspace::WorkspaceClient);

my $wstwo;
isa_ok ($wstwo = Bio::P3::Workspace::WorkspaceClient->new($url,token => "un=chenry|tokenid=03B0C858-7A70-11E4-9DE6-FDA042A49C03|expiry=1449094224|client_id=chenry|token_type=Bearer|SigningSubject=http://rast.nmpdr.org/goauth/keys/E087E220-F8B1-11E3-9175-BD9D42A49C03|sig=085255b952c8db3ddd7e051ac4a729f719f22e531ddbc0a3edd86a895da851faa93249a7347c75324dc025b977e9ac7c4e02fb4c966ec6003ecf90d3148e35160265dbcdd235658deeed0ec4e0c030efee923fda1a55e8cc6f116bcd632fa6a576d7bf4a794554d2d914b54856e1e7ac2b071f81a8841d142123095f6af957cc"), Bio::P3::Workspace::WorkspaceClient);

#Setting context to authenticated user one

can_ok("Bio::P3::Workspace::WorkspaceClient", qw(
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

#Clearing out previous test results
my $output = $wstwo->ls({
	paths => [""],
	adminmode => 1
});
if (defined($output->{""})) {
	my $hash = {};
	for (my $i=0; $i < @{$output->{""}}; $i++) {
		my $item = $output->{""}->[$i];
		print $item->[2].$item->[0]."\n";
		$hash->{$item->[2].$item->[0]} = 1;
	}
	if (defined($hash->{"/chenry/TestWorkspace"})) {
		$output = $wstwo->delete({
			objects => ["/chenry/TestWorkspace"],
			force => 1,
			deleteDirectories => 1,
			adminmode => 1
		});
	}
	if (defined($hash->{"/reviewer/TestWorkspace"})) {
		$output = $wstwo->delete({
			objects => ["/reviewer/TestWorkspace"],
			force => 1,
			deleteDirectories => 1,
			adminmode => 1
		});
	}
	if (defined($hash->{"/reviewer/TestAdminWorkspace"})) {
		$output = $wstwo->delete({
			objects => ["/reviewer/TestAdminWorkspace"],
			force => 1,
			deleteDirectories => 1,
			adminmode => 1
		});
	}
}

#Creating a private workspace as "$testuserone"
$output = $wsone->create({
	objects => [["/reviewer/TestWorkspace","folder",{description => "My first workspace!"},undef]],
	permission => "n"
});
ok defined($output), "Successfully created a top level directory!";
print "create output:\n".Data::Dumper->Dump($output)."\n\n";

#Creating a public workspace as "$testusertwo"
$output = $wstwo->create({
	objects => [["/chenry/TestWorkspace","folder",{description => "My first workspace!"},undef]],
	permission => "r"
});
ok defined($output), "Successfully created a top level directory!";
print "create output:\n".Data::Dumper->Dump($output)."\n\n";
#Testing testusertwo acting as an adminitrator
$output = $wstwo->create({
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
	$output = $wstwo->create({
		objects => [["/reviewer/TestWorkspace","folder",{description => "My second workspace!"},undef]],
		permission => "r"
	});
};
ok !defined($output), "Creating a top level directory for another user should fail!";
#Getting workspace metadata
$output = $wstwo->get({
	metadata_only => 1,
	objects => ["/chenry/TestWorkspace"]
});
ok defined($output), "Successfully ran get function to retrieve workspace metadata!";
print "get output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing workspaces as "$testusertwo"
$output = $wstwo->ls({
	paths => [""]
});
ok defined($output->{""}->[0]) && !defined($output->{""}->[1]), "Successfully ran ls function on got one workspace back!";
print "list_workspaces output:\n".Data::Dumper->Dump([$output])."\n\n";

#Listing workspaces as "$testuserone"
$output = $wsone->ls({
	paths => [""]
});
ok defined($output->{""}->[2]), "Successfully ran ls function on got three workspaces back!";
print "ls output:\n".Data::Dumper->Dump([$output])."\n\n";

#Listing workspaces as "$testuserone" but restricting to owned only
$output = $wsone->ls({
	paths => ["/$testuserone/"]
});
ok defined($output->{"/$testuserone/"}->[1]) && !defined($output->{"/$testuserone/"}->[2]), "Successfully ran ls function and got two workspaces back!";
print "list_workspaces output:\n".Data::Dumper->Dump([$output])."\n\n";

#Saving an object
$output = $wsone->create({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/testobj","genome",{"Description" => "My first object!"},{
		id => "83333.1",
		scientific_name => "Escherichia coli",
		domain => "Bacteria",
		dna_size => 4000000,
		num_contigs => 1,
		gc_content => 0.5,
		taxonomy => "Bacteria",
		features => [{}]
	}]]
});
ok defined($output->[0]), "Successfully ran save_objects action!";
print "save_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Recreating an existing folder
$output = $wsone->create({
	objects => [["/$testuserone/TestWorkspace/testdir","folder",{"Description" => "My recreated folder!"},undef]]
});
ok !defined($output->[0]), "Successfully recreated workspace folder with no errors!";

#Saving contigs
$output = $wsone->create({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/contigs","contigs",{"Description" => "My first contigs!"},">gi|284931009|gb|CP001873.1| Mycoplasma gallisepticum str. F, complete genome
TTTTTATTATTAACCATGAGAATTGTTGATAAATCTGTGGATAACTCTAAAAAAATTCCGGATTTATAAA
AGTACATTAAAATATTTATATTTTAATGTAAATATTATATCACTTTTTCACAAAAACGTGTATTATATAT
AAGGAGTTTTGTAAATTATTTAACTATATTACTATGTAATATAGTTATTATATCAAAACAAACTAAAACA
GTAGAGCAACCTTTAAAAATTAACTAAAAACTAAATACAAATTTGTTTATAGACGAAAGTTTTTCTATTA
ATATCCCCACATTAACTCTATCAAAACCCCTATACTAAAAAAAACACACTCTGAATACATAACTTGTATG
TAAAGTTTGAGTGAAGTTAAATCGCTTTAATATTGTAACAATATTGTTTGTAAAAATATTTATTTAATAT
GAAAAAAATATTGTGATTTTTATCGGAAATATTGTGATTTTCTAATTCAGGCCAATTAAAAATATCAAAA
CTAATTACTTAAATAAAAATATCAATAAATAAATTAAAAAACTTATTAACATTTCTACTAAGAGAGTTCG
TATTTGGAAATAATATTAAAGTAATACACAATATTAAAAAAATATTATTAGTATTTAAACGATTAAGTAC
TTTTTCATTCTTTTGTCTATCTGTAAAAGACACTAGGTAAGGATTACTTTATTAACAAGATAAAGAGAAA
AGAATTTATTTTTAATAATACGATTTTAATATTTTTAAAATATTATTCAATTTACGTTGTTTTATTACCA
AAAATAGAATATTAAAACAATATTTATAAGTTAATTAAAATTAATACTTTTTAAAACAAAACAACAATAT
TATTTCAATATGGTCACAGTAGTCACAATAAAGTTGATAATATTTAAATAATATTAATTAAATATTTATT
CAAGAATTTATTATTCTTGAATAACAGCAAAAAACTTTTATAGAACTGAAGAGCATTCTTAAAAAAGAAA
AAACCTAATGCTAACGGCATCAGAACTAACTAATACGAAAATAATATTTGATTACAAGAGAAGCAAATAA
TATTGTTAAGGGATCAATATTGTAATAATATTAAAATCATATCATAGAAGGTTAATGCTTACCAGTAATA
CTACTAACAGATAGTTTAATGTAGATGTATTAATATTGTAATAATATTAAAGTCATATTGTAAAAAGTTT
ATCTTTAGCAAAAAATACTACTAAACGGAGAATTTAATATAGATATATCATTAATATTTAAATAATATTA
CTTCATAAGGAAGCAATAATAACAAATATTCTTAACTTATAAATAAGCAATATATTAATAATATGGTAAC
AATATTGTTTTAATACTACATTCGTAATAAAGCTAGTTTAAGAGAATATTAAAATAATATTGGTTTGAAA
CTGTTAAAAATTATCTTTCTTAACAATATTGCCAAATCCGATTTTGCTTTACTTCAACGGGAATAAGTTT
TTAACTAAACTTTGCACTCTAATTACTAAAATATAAAAACAAACTTAGGACTAAAAAGATTTGAAATGAT
TAGCGTAAGGCTGAGGTTTTAGTTTAAATATACAAAGTAAAGTATTTTTTATTTAAAACAAGTTTTAAAA
ATACCAAAATGATATTTTATTAATATTGTTATCTATATCAAGATTTATAATATGTTTTCTTGAGCACTTT
TTTTCAAGATTGCCTAATAATAATATATTTTTAATATTTAATTACTAGGAAAATAATATTGCGAAAATTA"]]
});
ok defined($output->[0]), "Successfully ran save_objects action!";
print "save_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Creating shock nodes
$output = $wsone->create({
	objects => [["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/shockobj","genome",{"Description" => "My first shock object!"}]],
	createUploadNodes => 1
});
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
$output = $wsone->get({
	objects => ["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/shockobj"]
});
ok defined($output->[0]), "Successfully ran get function!";
print "get_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing objects
$output = $wsone->ls({
	paths => ["/$testuserone/TestWorkspace/testdir/testdir2"],
	excludeDirectories => 0,
	excludeObjects => 0,
	recursive => 1
});
ok defined($output->{"/$testuserone/TestWorkspace/testdir/testdir2"}), "Successfully listed all workspace contents!";
print "ls output:\n".Data::Dumper->Dump([$output])."\n\n";
$output = $wsone->ls({
	paths => ["/$testuserone/TestWorkspace"],
	excludeDirectories => 0,
	excludeObjects => 0,
	recursive => 0
});
ok defined($output->{"/$testuserone/TestWorkspace"}->[0]) && !defined($output->{"/$testuserone/TestWorkspace"}->[1]), "Successfuly listed workspace contents nonrecursively!";
print "list_workspace_contents output:\n".Data::Dumper->Dump([$output])."\n\n";
$output = $wsone->ls({
	paths => ["/$testuserone/TestWorkspace"],
	excludeDirectories => 1,
	excludeObjects => 0,
	recursive => 1
});
ok defined($output->{"/$testuserone/TestWorkspace"}->[0]) && !defined($output->{"/$testuserone/TestWorkspace"}->[2]), "Successfully listed workspace contents without directories!";
print "list_workspace_contents output:\n".Data::Dumper->Dump([$output])."\n\n";
$output = $wsone->ls({
	paths => ["/$testuserone/TestWorkspace"],
	excludeDirectories => 0,
	excludeObjects => 1,
	recursive => 1
});
ok defined($output->{"/$testuserone/TestWorkspace"}->[2]) && !defined($output->{"/$testuserone/TestWorkspace"}->[3]), "Successfully listed workspace contents without objects!";
print "list_workspace_contents output:\n".Data::Dumper->Dump([$output])."\n\n";

#Listing objects hierarchically
$output = $wsone->ls({
	paths => ["/$testuserone/TestWorkspace"],
	excludeDirectories => 0,
	excludeObjects => 0,
	recursive => 1,
	fullHierachicalOutput => 1
});
ok defined($output->{"/$testuserone/TestWorkspace"}) && defined($output->{"/$testuserone/TestWorkspace/testdir"}), "Successfully listed workspace contents hierarchically!";
print "list_workspace_hierarchical_contents output:\n".Data::Dumper->Dump([$output])."\n\n";

#Copying workspace object
$output = undef;
eval {
$output = $wsone->copy({
	objects => [["/$testuserone/TestWorkspace/testdir","/$testusertwo/TestWorkspace/copydir"]],
	recursive => 1
});
};
ok !defined($output), "Copying to a read only workspace fails!";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;

#Changing workspace permissions
$output = $wstwo->set_permissions({
	path => "/$testusertwo/TestWorkspace",
	permissions => [[$testuserone,"w"]]
});
ok defined($output), "Successfully ran set_workspace_permissions function!";
print "set_workspace_permissions output:\n".Data::Dumper->Dump($output)."\n\n";
#Listing workspace permission
$output = $wstwo->list_permissions({
	objects => ["/$testusertwo/TestWorkspace"]
});
ok defined($output->{"/$testusertwo/TestWorkspace"}->[0]), "Successfully ran list_workspace_permissions function!";
print "list_workspace_permissions output:\n".Data::Dumper->Dump([$output])."\n\n";

#Copying workspace object
$output = $wsone->copy({
	objects => [["/$testuserone/TestWorkspace/testdir","/$testusertwo/TestWorkspace/copydir"]],
	recursive => 1
});
ok defined($output), "Successfully ran copy_objects function!";
print "copy_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Listing contents of workspace with copied objects
$output = $wsone->ls({
	paths => ["/$testusertwo/TestWorkspace"],
	excludeDirectories => 0,
	excludeObjects => 0,
	recursive => 1
});
ok defined($output->{"/$testusertwo/TestWorkspace"}->[0]), "Successfully listed workspace contents!";
print "list_workspace_contents output:\n".Data::Dumper->Dump([$output])."\n\n";

#Changing global workspace permissions
$output = $wsone->set_permissions({
	path => "/$testuserone/TestWorkspace",
	new_global_permission => "w"
});
ok defined($output), "Successfully changed global permissions!";
print "reset_global_permission output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user two
$Bio::P3::Workspace::Service::CallContext = $ctxtwo;

#Moving objects
$output = $wstwo->copy({
	objects => [["/$testusertwo/TestWorkspace/copydir","/$testuserone/TestWorkspace/movedir"]],
	recursive => 1,
	move => 1
});
ok defined($output), "Successfully ran copy to move objects!";
print "move_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Setting context to authenticated user one
$Bio::P3::Workspace::Service::CallContext = $ctxone;

#Deleting an object
$output = $wsone->delete({
	objects => ["/$testuserone/TestWorkspace/movedir/testdir2/testdir3/testobj","/$testuserone/TestWorkspace/movedir/testdir2/testdir3/shockobj"]
});
ok defined($output), "Successfully ran delete_objects function on object!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";

$output = $wsone->delete({
	objects => ["/$testuserone/TestWorkspace/movedir/testdir2/testdir3"],
	deleteDirectories => 1
});
ok defined($output), "Successfully ran delete_objects function on directory!";
print "delete_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Deleting a directory
$output = $wsone->delete({
	objects => ["/$testuserone/TestWorkspace/movedir"],
	force => 1,
	deleteDirectories => 1
});
ok defined($output), "Successfully ran delete_workspace_directory function!";
print "delete_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Creating a directory
$output = $wsone->create({
	objects => [["/$testuserone/TestWorkspace/emptydir","folder",{},undef]]
});
ok defined($output), "Successfully ran create_workspace_directory function!";
print "create_workspace_directory output:\n".Data::Dumper->Dump($output)."\n\n";
#Getting an object
$output = $wsone->get({
	objects => ["/$testuserone/TestWorkspace/testdir/testdir2/testdir3/testobj"]
});
ok defined($output->[0]->[1]), "Successfully ran get_objects function!";
print "get_objects output:\n".Data::Dumper->Dump($output)."\n\n";

#Getting an object by reference
$output = $wsone->get({
	objects => [$output->[0]->[0]->[4]]
});
ok defined($output->[0]->[1]), "Successfully ran get_objects_by_reference function!";
print "get_objects_by_reference output:\n".Data::Dumper->Dump($output)."\n\n";

#Deleting workspaces
$output = $wsone->delete({
	objects => ["/$testuserone/TestWorkspace"],
	force => 1,
	deleteDirectories => 1
});
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

$output = $wstwo->delete({
	objects => ["/$testusertwo/TestWorkspace"],
	force => 1,
	deleteDirectories => 1
});
ok defined($output), "Successfully ran delete_workspace function!";
print "delete_workspace output:\n".Data::Dumper->Dump($output)."\n\n";

done_testing($test_count);