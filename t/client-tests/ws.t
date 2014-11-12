use Test::More;
use Config::Simple;
use JSON;
use Data::Dumper;

if (defined $ENV{KB_DEPLOYMENT_CONFIG} && -e $ENV{KB_DEPLOYMENT_CONFIG}) {
    $cfg = new Config::Simple($ENV{KB_DEPLOYMENT_CONFIG}) or
	die "can not create Config object";
    print "using $ENV{KB_DEPLOYMENT_CONFIG} for configs\n";
}
else {
    $cfg = new Config::Simple(syntax=>'ini');
    $cfg->param('workspace.service-host', '127.0.0.1');
    $cfg->param('workspace.service-port', '7109');
}

my $url = "http://" . $cfg->param('handle_service.service-host') . 
	  ":" . $cfg->param('handle_service.service-port');


# TODO for a pure client side test, remove AWE, Shock, and WorkspaceImpl
BEGIN {
	use_ok( Bio::P3::Workspace::WorkspaceClient );
	use_ok( Bio::P3::Workspace::WorkspaceImpl );
}

can_ok("Bio::P3::Workspace::WorkspaceClient", qw(
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

   )
);
