use strict;
use UUID;

use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::WorkspaceImpl;

# logout
!system('kbase-logout') or die $!;

# check to see if token exists in home dir
print "check for token: ", `grep token $ENV{HOME}/.kbase_config`, "\n";

# create a random workspace name
my($uuid, $workspace);
UUID::generate($uuid);
UUID::unparse($uuid, $workspace);

# create the create_workspace_params
my $create_workspace_params = {
	workspace => $workspace,
	permission => "a",
	metadata => {'owner' => 'brettin'}, 
};

eval {
	# create an unauthenticated client
	my $obj1 = Bio::P3::Workspace::WorkspaceClient->new();

	# create a worksapace with unauthenticated client
	my $output1 = $obj1->create_workspace($create_workspace_params);
};
if ($@) {
	print "unsuccessful unauthencitaed attempt to creat workspace\n";
}

# authenticate
!system('kbase-login', 'kbasetest', '-p', '@Suite525') or die $!;

# check to see if token exists in home dir
print "check for token", `grep token $ENV{HOME}/.kbase_config`, "\n";

eval {
	# create an authenticated client
	my $obj2 = Bio::P3::Workspace::WorkspaceClient->new();

	# create a workspace with authenticated client
	my $output2 = $obj2->create_workspace($create_workspace_params);
};
if ($@) {
	print "unsuccessful authenticated attempt to create workspace\n";
}
