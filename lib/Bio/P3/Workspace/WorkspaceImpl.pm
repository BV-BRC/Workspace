package Bio::P3::Workspace::WorkspaceImpl;
use strict;
use Bio::KBase::Exceptions;
# Use Semantic Versioning (2.0.0-rc.1)
# http://semver.org 
our $VERSION = "0.1.0";

=head1 NAME

Workspace

=head1 DESCRIPTION



=cut

#BEGIN_HEADER

use File::Path;
use File::Copy;
use Data::UUID;
use REST::Client;
use LWP::UserAgent;
use JSON::XS;
use Data::Dumper;
use HTTP::Request::Common;
use Log::Log4perl qw(:easy);
use MongoDB::Connection;
Log::Log4perl->easy_init($DEBUG);

<<<<<<< HEAD
#Returns the authentication token supplied to the service in the context object
sub _authentication {
	my($self) = @_;
	if (!defined($self->_getContext()->{token})) {
		$self->_error("Workspace functions cannot be run without an authentication token!")
		
	}
	return $self->_getContext()->{token};
}
=======
#
# Alias our context variable.
#

*Bio::P3::Workspace::WorkspaceImpl::CallContext = *Bio::P3::Workspace::Service::CallContext;
our $CallContext;
>>>>>>> 17852f320b8c05cbb38150f00fbf51f0efd3583c

#Returns the username supplied to the service in the context object
sub _getUsername {
	my ($self) = @_;
<<<<<<< HEAD
	if (!defined($self->_getContext()->{user_id})) {
		$self->_error("Workspace functions cannot be run without an authenticated user!")
	}
	return $self->_getContext()->{user_id};
}

#Returns the current context object
sub _getContext {
	my ($self) = @_;
	if (!defined($Bio::P3::Workspace::Service::CallContext)) {
		$self->_error("Cannot call workspace functions without valid context object!")
	}
	return $Bio::P3::Workspace::Service::CallContext;
}
=======

	return $CallContext->user_id;
}
sub _getContext {
	my ($self) = @_;

	return $CallContext;
    }
>>>>>>> 17852f320b8c05cbb38150f00fbf51f0efd3583c

#Returns the method supplied to the service in the context object
sub _current_method {
	my ($self) = @_;
<<<<<<< HEAD
	if (!defined($self->_getContext()->{method})) {
		$self->_error("Context object must include which method is being called!")
	}
	return $self->_getContext()->{method};
=======
	return $CallContext->method;
>>>>>>> 17852f320b8c05cbb38150f00fbf51f0efd3583c
}

sub _validateargs {
	my ($self,$args,$mandatoryArguments,$optionalArguments,$substitutions) = @_;
	if (!defined($args)) {
	    $args = {};
	}
	if (ref($args) ne "HASH") {
		$self->_error("Arguments not hash");
	}
	if (defined($substitutions) && ref($substitutions) eq "HASH") {
		foreach my $original (keys(%{$substitutions})) {
			$args->{$original} = $args->{$substitutions->{$original}};
		}
	}
	if (defined($mandatoryArguments)) {
		for (my $i=0; $i < @{$mandatoryArguments}; $i++) {
			if (!defined($args->{$mandatoryArguments->[$i]})) {
				push(@{$args->{_error}},$mandatoryArguments->[$i]);
			}
		}
	}

	#     $input = $self->_validateargs($input,["workspace"],{});
	#     from line 2804
	if (defined($args->{_error})) {
		$self->_error("Mandatory arguments ".join("; ",@{$args->{_error}})." missing.");
	}
	if (defined($optionalArguments)) {
		foreach my $argument (keys(%{$optionalArguments})) {
			if (!defined($args->{$argument})) {
				$args->{$argument} = $optionalArguments->{$argument};	
			}
		}
	}
	return $args;
}

sub _shockurl {
	my $self = shift;
	return $self->{_params}->{"shock-url"};
}

sub _wsauth {
	my $self = shift;
	if (!defined($self->{_wsauth})) {
		my $token = Bio::KBase::AuthToken->new(user_id =>  $self->{_params}->{wsuser}, password => $self->{_params}->{wspassword});
		$self->{_wsauth} = $token->token();
	}
	return $self->{_wsauth};
}

sub _url {
	my $self = shift;
	return $self->{_params}->{"url"};
}

sub _error {
	my($self,$msg) = @_;
	$msg = "_ERROR_".$msg."_ERROR_";
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => $self->_current_method());
}

sub _db_path {
	my($self) = @_;
	return $self->{_params}->{"db-path"};
}

sub _mongodb {
	my ($self) = @_;
	return $self->{_mongodb};
}

sub _updateDB {
	my ($self,$name,$query,$update) = @_;
	my $data = $self->_mongodb()->run_command({
		findAndModify => $name,
		query => $query,
		update => $update
	});
	if (ref($data) ne "HASH" || !defined($data->{value})) {
		return 0;
	}
	return 1;
}

sub _get_db_ws {
	my ($self,$query) = @_;
	if (defined($query->{raw_id})) {
		my $id = $query->{raw_id};
		delete $query->{raw_id};
		if ($id =~ m/^\/([^\/]+)\/([^\/]+)\/*$/) {
			$query->{owner} = $1;
			$query->{name} = $2;
		} elsif ($id =~ m/^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$/) {
			$query->{uuid} = $id;
		} elsif ($id =~ m/([^\/]+)\/*$/) {
			$query->{owner} = $self->_getUsername();
			$query->{name} = $1;
		}
	}
	#DEBUG "_get_db_ws: received query: $query";
	#DEBUG "_get_db_ws: " . JSON->new()->pretty->encode($query);
	#DEBUG "_get_db_ws: parsing owner,name,and/or uuid where raw_id = $query->{raw_id}";
	#DEBUG "_get_db_ws: running query with owner = $query->{owner}";
	#DEBUG "_get_db_ws: running query with name = $query->{name}";

	my $cursor = $self->_mongodb()->get_collection('workspaces')->find($query);
	my $object = $cursor->next;
	if (!defined($object)) {
		$self->_error("Workspace not found!");
	}
	return $object;
}

sub _get_db_object {
	my ($self,$query,$throwerror) = @_;
	my $objects = $self->_query_database($query,0);
	if (defined($objects->[0])) {
		$objects->[0] = $self->_process_raw_object($objects->[0]);
	}
	if (!defined($objects->[0]) && $throwerror == 1) {
		$self->_error("Object not found!");
	}
	return $objects->[0];
}

sub _generate_ws_meta {
	my ($self,$ws) = @_;
	my $numobj = $self->_query_database({
		workspace_uuid => $ws->{uuid},
		directory => 0
	},1);
	my $numdir = $self->_query_database({
		workspace_uuid => $ws->{uuid},
		directory => 1
	},1);
	return [$ws->{uuid},$ws->{name},$ws->{owner},$ws->{creation_date},$numobj,$self->_get_ws_permission($ws),$ws->{global_permission},$numdir,$ws->{metadata}];
}

sub _generate_object_meta {
	my ($self,$obj,$ws) = @_;
	my $path = "/".$ws->{owner}."/".$ws->{name}."/".$obj->{path};
	if ($obj->{path} eq "") {
		$path = "/".$ws->{owner}."/".$ws->{name};
	}
	return [$obj->{uuid},$obj->{name},$obj->{type},$obj->{creation_date},$self->_url()."/objects/".$obj->{uuid},$obj->{owner},$obj->{workspace_uuid},$ws->{name},$path,$obj->{size},$obj->{metadata},$obj->{autometadata}];
}

sub _retrieve_object_data {
	my ($self,$obj,$ws) = @_;
	if ($obj->{directory} == 1) {
		return {};
	}
	my $data;
	if (!defined($obj->{shock}) || $obj->{shock} == 0) {
		my $filename = $self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$obj->{path}."/".$obj->{name};
		open (my $fh,"<",$filename);
		while (my $line = <$fh>) {
			$data .= $line;	
		}
		close($fh);
	} else {
		my $rest = REST::Client->new(useragent => LWP::UserAgent->new());
		$rest->addHeader(Authorization => "OAuth ".$self->_wsauth());
		my $res = $rest->GET($obj->{shocknode}."?download");
		if ($rest->responseCode != 200){
			die "get_file failed: " . $rest->responseContent();
		}
		$data = $rest->responseContent();
	}
	if ($data =~ m/^[\{\[].+[\}\]]$/) {
		my $JSON = JSON::XS->new->utf8(1);
		$data = $JSON->encode($data);
	}
	if (!defined($data)) {
		$data = "";
	}
	return $data;
}

sub _validate_workspace_permission {
	my ($self,$input) = @_;
	if ($input !~ m/^[awron]$/) {
		$self->_error("Input permissions invalid!");
	}
	return $input;
}

sub _validate_workspace_name {
	my ($self,$input) = @_;
	if ($input =~ m/[:\/]/) {
		$self->_error("Workspace contains forbidden characters!");
	}
	return $input;
}

sub _validate_object_type {
	my ($self,$type) = @_;
	my $types = {
		String => 1,Genome => 1,Unspecified => 1,Directory => 1
	};
	if (!defined($types->{$type})) {
		$self->_error("Invalid type submitted!");
	}
	return $type;
}

sub _escape_username {
	my ($self,$input) = @_;
	return $input;
}

sub _unescape_username {
	my ($self,$input) = @_;
	return $input;
}

sub _get_ws_permission {
	my ($self,$wsobj) = @_;
	my $curruser = $self->_escape_username($self->_getUsername());
	#DEBUG "curruser = $curruser";
	if ($wsobj->{owner} eq $curruser) {
		return "o";
	}
	my $values = {
		n => 0,
		r => 1,
		w => 2,
		a => 3,
		o => 4
	};
	if (defined($wsobj->{permissions}->{$curruser})) {
		if ($values->{$wsobj->{permissions}->{$curruser}} > $values->{$wsobj->{global_permission}}) {
			return $wsobj->{permissions}->{$curruser};
		}
	}
	return $wsobj->{global_permission};
}

sub _check_ws_permissions {
	my ($self,$wsobj,$minperm,$throwerror) = @_;
	my $perm = $self->_get_ws_permission($wsobj);
	my $values = {
		n => 0,
		r => 1,
		w => 2,
		a => 3,
		o => 4
	};
	if ($values->{$perm} < $values->{$minperm}) {
		if ($throwerror == 1) {
			$self->_error("User lacks permission for requested action!");
		}
		return 0;
	}
	return 1;
}

sub _parse_ws_path {
	my ($self,$input) = @_;
	#Three classes of paths are accepted:
	#/<Username>/<Workspace name>/<Path>
	#<Workspace name>/<Path> (in this case, the currently logged user is assumed to be the owner of the workspace)
	#/<Username>/<Workspace name>/<Path>
	#DEBUG "_parse_ws_path: input: $input";
	my ($user,$workspace,$path);

	if ($input =~ m,^[^/],)
	{
	    #
	    # No leading slash, therefore we are relative to the current user.
	    #
	    $input = "/" . $self->_getUsername() . "/$input";
	}

	if ($input =~ m,^/_uuid/([^/]+)/(.+)/*$,)
	{
	    #
	    # UUID
	    #
	    my $ws = $self->_get_db_ws({ uuid => $1 });
	    $user = $ws->{owner};
	    $workspace = $1;
	    $path = $2;
	}
	elsif ($input =~ m,^/([^/]+)/([^/]+)/(.+)/*$,)
	{
	    #
	    # /user/ws/path
	    #
	    $user = $1;
	    $workspace = $2;
	    $path = $3;
	}
	else { WARN "_parse_ws_path: could not parse WorkspacePath: $input"; }

	return ($user,$workspace,$path);
}

sub _parse_directory_name {
	my ($self,$path) = @_;
	my $array = [split(/\//,$path)];
	my $name = pop(@{$array});
	return (join("/",@{$array}),$name);
}

sub _delete_object {
	my ($self,$obj,$ws,$deletefile,$recursivedelete) = @_;
	if ($obj->{directory} == 1 && $recursivedelete == 1) {
		my $objs = $self->_get_directory_contents($obj,$ws,0);
		for (my $i=0; $i < @{$objs}; $i++) {
			$self->_delete_object($objs->[$i],$ws,0,1);
		}
		if ($deletefile) {
			rmtree($self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$obj->{path}."/".$obj->{name});
		}
	} elsif ($obj->{directory} == 0) {
		$self->_mongodb()->get_collection('objects')->remove({uuid => $obj->{uuid}});
		if ($deletefile) {
			unlink($self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$obj->{path}."/".$obj->{name});
		}
	}
}

sub _count_directory_contents {
	my ($self,$obj,$recursive) = @_;
	if ($recursive == 1) {
		my $path = "^".$obj->{path}."/".$obj->{name};
		return $self->_query_database({
			workspace_uuid => $obj->{workspace_uuid},
			path => qr/$path/
		},1);
	}
	return $self->_query_database({
		workspace_uuid => $obj->{workspace_uuid},
		path => $obj->{path}."/".$obj->{name}
	},1);
}

sub _get_directory_contents {
	my ($self,$obj,$ws,$recursive) = @_;
	my $query = {};
	if ($recursive == 1) {
		my $path = "^".$obj->{path}."/".$obj->{name};
		if (length($obj->{path}) == 0) {
			$path = "^".$obj->{name};
		}
		$query = {
			workspace_uuid => $obj->{workspace_uuid},
			path => qr/$path/
		};
	} else {
		my $path = $obj->{path}."/".$obj->{name};
		if (length($obj->{path}) == 0) {
			$path = $obj->{name};
		}
		$query = {
			workspace_uuid => $obj->{workspace_uuid},
			path => $path
		};
	}
	my $objects = $self->_query_database($query,0);
	my $output = [];
	for (my $i=0; $i < @{$objects}; $i++) {
		push(@{$output},$objects->[$i]);
	}
	return $output;
}

sub _ensure_path_exists {
	my ($self,$ws,$path,$create,$throwerror) = @_;
	if (!-d $self->_db_path()."/".$ws->{owner}."/".$ws->{name}) {
		if (defined($throwerror) && $throwerror == 1) {
			$self->_error("Workspace directory /".$ws->{owner}."/".$ws->{name}." does not exist!");
		}
		if (defined($create) && $create == 1) {
			$self->_error("Cannot create directory! Workspace directory /".$ws->{owner}."/".$ws->{name}." does not exist!");
		}
		return 0;
	}
	if (length($path) == 0) {
		return 1;
	}
	my $array = [split(/\//,$path)];
	my $name = pop(@{$array});
	my $count = $self->_query_database({
		workspace_uuid => $ws->{uuid},
		path => join("/",@{$array}),
		name => $name
	},1);
	if ($count == 0) {
		if ($create == 1) {
			$self->_create_new_object($ws,{
				directory => 1,
				workspace_uuid => $ws->{uuid},
				workspace_owner => $ws->{owner},
				path => join("/",@{$array}),
				name => $name,
				metadata => {},
				type => "Directory"
			});
			#Now we just return, because this step automatically checks all subdirectories
			return 1;
		} elsif ($throwerror == 1) {
			$self->_error("Workspace subdirectory /".$ws->{owner}."/".$ws->{name}."/".$path." does not exist!");
		}
		return 0;
	}
	if (@{$array} > 0) {
		return $self->_ensure_path_exists($ws,join("/",@{$array}),$create,$throwerror);
	}
	return 1;
}

sub _query_database {
	my ($self,$query,$count) = @_;
	if (defined($query->{path})) {
		$query->{path} =~ s/^\///;
		$query->{path} =~ s/\/$//;
	}
	if ($count == 1) {
		return $self->_mongodb()->get_collection('objects')->count($query);
	}
	my $output = [];
	my $cursor = $self->_mongodb()->get_collection('objects')->find($query);
	while (my $object = $cursor->next) {
		push(@{$output},$object);
	}
	return $output;
}

sub _create_new_object {
	my ($self,$ws,$obj,$data) = @_;
	if ($obj->{type} eq "Directory") {
    	$obj->{directory} = 1;
    }
    $obj->{size} = 0;
	if ($obj->{directory} == 1) {
		if ($self->_query_database({
			workspace_uuid => $ws->{uuid},
			path => $obj->{path},
			name => $obj->{name}
		},1) > 0) {
			$self->_error("Workspace directory /".$ws->{owner}."/".$ws->{name}."/".$obj->{path}."/".$obj->{name}." already exists!");
		}
	    if (!-d $self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$obj->{path}."/".$obj->{name}) {
	    	File::Path::mkpath ($self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$obj->{path}."/".$obj->{name});
	    }
	} else {
		if ($self->_query_database({
			workspace_uuid => $ws->{uuid},
			path => $obj->{path},
			name => $obj->{name}
		},1) > 0) {
			$self->_error("Workspace object /".$ws->{owner}."/".$ws->{name}."/".$obj->{path}."/".$obj->{name}." already exists!");
		}
	    if (!-d $self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$obj->{path}) {
	    	File::Path::mkpath ($self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$obj->{path});
	    }
	}
	$self->_validate_object_type($obj->{type});
	$self->_ensure_path_exists($ws,$obj->{path},1);
    if (defined($data)) {
    	my $JSON = JSON::XS->new->utf8(1);
		open (my $fh,">",$self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$obj->{path}."/".$obj->{name});
		if (ref($data) eq 'ARRAY' || ref($data) eq 'HASH') {
			$data = $JSON->encode($data);	
		}
		print $fh $data;
		close($fh);
		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$obj->{path}."/".$obj->{name});
		$obj->{size} = $size;
    }
    $self->_save_object_to_db($obj);
    return $obj;
}

sub _save_object_to_db {
	my ($self,$obj) = @_;
	my $uuid = Data::UUID->new()->create_str();
    $obj->{path} =~ s/^\/+//;
	$obj->{path} =~ s/\/+$//;
	$obj->{uuid} = $uuid;
    $obj->{creation_date} = DateTime->now()->datetime();
    $obj->{owner} = $self->_getUsername();
    $obj->{autometadata} = {};
    if (!defined($obj->{shock})) {
    	$obj->{shock} = 0;
    }
    if (!defined($obj->{metadata})) {
    	$obj->{metadata} = {};
    }
	$self->_mongodb()->get_collection('objects')->insert($obj);
	return $obj;
}

sub _process_raw_object {
	my ($self,$obj) = @_;
	return $obj;
}

sub _move_object {
	my ($self,$object,$ws) = @_;
	$self->_ensure_path_exists($ws,$object->{path},1);
	$object->{path} =~ s/^\/+//;
	$object->{path} =~ s/\/+$//;
	$self->_updateDB("objects",{uuid => $object->{uuid}},{
		'$set' => {
			workspace_uuid => $ws->{uuid},
			workspace_owner => $ws->{owner},
			path => $object->{path},
			name => $object->{name},
		}
	});
	$object->{workspace_uuid} = $ws->{uuid};
	$object->{workspace_owner} = $ws->{owner};
	if ($object->{directory} == 1) {
	    File::Path::mkpath ($self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$object->{path}."/".$object->{name});
	} else {
	    File::Path::mkpath ($self->_db_path()."/".$ws->{owner}."/".$ws->{name}."/".$object->{path});
	}
	return $object;
}

sub _copy_or_move_objects {
	my ($self,$objects, $overwrite, $recursive,$move) = @_;
	my $output = [];
	my $workspaces = {};
    my $wshash = {};
    my $destinations;
    my $objdest;
    for (my $i=0; $i < @{$objects}; $i++) {
    	my ($user,$workspace,$path) = $self->_parse_ws_path($objects->[$i]->[0]);
    	if (!defined($workspaces->{$user}->{$workspace})) {
    		$workspaces->{$user}->{$workspace} = $self->_get_db_ws({
    			name => $workspace,
    			owner => $user
    		});
    		$wshash->{$workspaces->{$user}->{$workspace}->{uuid}} = $workspaces->{$user}->{$workspace};
    		$self->_check_ws_permissions($workspaces->{$user}->{$workspace},"r",1);
    	}
    	my $obj = $self->_get_db_object({
	    	workspace_uuid => $workspaces->{$user}->{$workspace}->{uuid},
	    	path => $path,
	    	name => $objects->[$i]->[1]
	    },1);
	    my ($duser,$dworkspace,$dpath) = $self->_parse_ws_path($objects->[$i]->[2]);
	    if (!defined($workspaces->{$duser}->{$dworkspace})) {
    		$workspaces->{$duser}->{$dworkspace} = $self->_get_db_ws({
    			name => $dworkspace,
    			owner => $duser
    		});
    		$wshash->{$workspaces->{$duser}->{$dworkspace}->{uuid}} = $workspaces->{$duser}->{$dworkspace};
    		$self->_check_ws_permissions($workspaces->{$duser}->{$dworkspace},"w",1);
    	}
    	if ($obj->{directory} == 1 && $recursive == 1) {
	    	my $subobjs = $self->_get_directory_contents($obj,$workspaces->{$user}->{$workspace},1);
	    	for (my $j=0; $j < @{$subobjs}; $j++) {
	    		my $subpath = $obj->{path}."/".$obj->{name};
	    		if (length($obj->{path}) == 0) {
	    			$subpath = $obj->{name};
	    		}
	    		my $partialpath = substr($subobjs->[$j]->{path},length($subpath));
	    		my $newdest = [$duser,$dworkspace,$dpath."/".$objects->[$i]->[3].$partialpath,$subobjs->[$j]->{name}];
	    		if (defined($objdest->{$subobjs->[$j]->{uuid}})) {
	    			if (join("/",@{$objdest->{$subobjs->[$j]->{uuid}}}) ne $duser."/".$dworkspace."/".$dpath."/".$objects->[$i]->[3].$partialpath."/".$subobjs->[$j]->{name}) {
	    				$self->_error("Attempting to copy the same object to two different locations!");
	    			}
	    		} else {
	    			$objdest->{$subobjs->[$j]->{uuid}} = $newdest;
	    		}
	    		if (defined($destinations->{$duser}->{$dworkspace}->{$dpath."/".$objects->[$i]->[3].$partialpath}->{$subobjs->[$j]->{name}})) {
	    			my $curruid = $destinations->{$duser}->{$dworkspace}->{$dpath."/".$objects->[$i]->[3].$partialpath}->{$subobjs->[$j]->{name}}->{uuid};
	    			if ($curruid ne $subobjs->[$j]->{uuid}) {
	    				$self->_error("Attempting to copy two different objects to the same location!");
	    			}
	    		} else {
	    			$destinations->{$duser}->{$dworkspace}->{$dpath."/".$objects->[$i]->[3].$partialpath}->{$subobjs->[$j]->{name}} = $subobjs->[$j];
	    		}
	    	}
	    }
    	if (defined($objdest->{$obj->{uuid}})) {
    		if (join("/",@{$objdest->{$obj->{uuid}}}) ne $duser."/".$dworkspace."/".$dpath."/".$objects->[$i]->[3]) {
    			$self->_error("Attempting to copy the same object to two different locations!");
    		}
    	} else {
    		$objdest->{$obj->{uuid}} = [$duser,$dworkspace,$dpath,$objects->[$i]->[3]];
    	}
    	if (defined($destinations->{$duser}->{$dworkspace}->{$dpath}->{$objects->[$i]->[3]})) {
    		my $curruid = $destinations->{$duser}->{$dworkspace}->{$dpath}->{$objects->[$i]->[3]}->{uuid};
    		if ($curruid ne $obj->{uuid}) {
    			$self->_error("Attempting to copy two different objects to the same location!");
    		}
    	} else {
    		$destinations->{$duser}->{$dworkspace}->{$dpath}->{$objects->[$i]->[3]} = $obj;
    	}
    }	
    #Checking all destinations for objects and ensuring that they are not directories
	my $delete = [];
	my $deletews = [];
    foreach my $user (keys(%{$destinations})) {
    	foreach my $workspace (keys(%{$destinations->{$user}})) {
    		foreach my $path (keys(%{$destinations->{$user}->{$workspace}})) {
    			foreach my $name (keys(%{$destinations->{$user}->{$workspace}->{$path}})) {
    				my $obj = $self->_get_db_object({
				    	workspace_uuid => $workspaces->{$user}->{$workspace}->{uuid},
				    	path => $path,
				    	name => $name
				    },0);
				    if (defined($obj)) {
			    		if ($obj->{directory} == 1 && $destinations->{$user}->{$workspace}->{$path}->{$name}->{directory} == 0) {
			    			$self->_error("Cannot overwrite directory /".$user."/".$workspace."/".$path."/".$name." with non-directory on copy!");
			    		} elsif ($overwrite == 0) {
			    			$self->_error("Overwriting object /".$user."/".$workspace."/".$path."/".$name." and overwrite flag is not set!");
			    		}
			    		if ($obj->{directory} == 0) {
			    			push(@{$delete},$obj);
			    			push(@{$deletews},$workspaces->{$user}->{$workspace});
			    		} else {
			    			$destinations->{$user}->{$workspace}->{$path}->{$name}->{nocopy} = 1;
			    		}
			    	}
    			}
    		}
    	}
    }
    #Deleting all overwritten objects
    for (my $i=0; $i < @{$delete}; $i++) {
    	$self->_delete_object($delete->[$i],$deletews->[$i],1,1);
    }
    #Copying over objects
    foreach my $user (keys(%{$destinations})) {
    	foreach my $workspace (keys(%{$destinations->{$user}})) {
    		my $paths = [sort(keys(%{$destinations->{$user}->{$workspace}}))];
    		foreach my $path (@{$paths}) {
    			foreach my $name (keys(%{$destinations->{$user}->{$workspace}->{$path}})) {
					if (!defined($destinations->{$user}->{$workspace}->{$path}->{$name}->{nocopy})) {
	    				my $sobj = $destinations->{$user}->{$workspace}->{$path}->{$name};
	    				my $newobj;
	    				if ($move == 1) {
	    					my $oldpapth = $sobj->{path};
	    					my $oldname = $sobj->{name};
	    					my $oldws = $sobj->{workspace_uuid};
	    					$sobj->{path} = $path;
	    					$sobj->{name} = $name;
	    					$newobj = $self->_move_object($sobj,$workspaces->{$user}->{$workspace});
	    					$sobj->{name} = $oldname;
	    					$sobj->{path} = $oldpapth;
	    					$sobj->{workspace_uuid} = $oldws;
	    				} else {
	    					$newobj = $self->_create_new_object($workspaces->{$user}->{$workspace},{
					    		directory => $sobj->{directory},
								workspace_uuid => $workspaces->{$user}->{$workspace}->{uuid},
								workspace_owner => $workspaces->{$user}->{$workspace}->{owner},
								path => $path,
								name => $name,
								type => $sobj->{type},
								metadata => $sobj->{metadata},
								autometadata => $sobj->{autometadata}
					    	});
	    				}
				    	if ($sobj->{directory} == 0) {
				    		if ($move == 1) {
				    			move($self->_db_path()."/".$wshash->{$sobj->{workspace_uuid}}->{owner}."/".$wshash->{$sobj->{workspace_uuid}}->{name}."/".$sobj->{path}."/".$sobj->{name},$self->_db_path()."/".$user."/".$workspace."/".$path."/".$name);
				    		} else {
				    			copy($self->_db_path()."/".$wshash->{$sobj->{workspace_uuid}}->{owner}."/".$wshash->{$sobj->{workspace_uuid}}->{name}."/".$sobj->{path}."/".$sobj->{name},$self->_db_path()."/".$user."/".$workspace."/".$path."/".$name);
				    		}
				    	}
				    	push(@{$output},$self->_generate_object_meta($newobj,$workspaces->{$user}->{$workspace}));
					}
				}
    		}
    	}
    }
    return $output;
}

#This function creates an empty shock node, gives the logged user ACLs, and returns the node ID
sub _create_shock_node {
	my ($self) = @_;
	my $ua = LWP::UserAgent->new();
	my $res = $ua->post($self->_shockurl()."/node",Authorization => "OAuth ".$self->_wsauth());
	my $json = JSON::XS->new;
	my $data = $json->decode($res->content);
	print "create shock node output:\n".Data::Dumper->Dump([$data])."\n\n";
	my $res = $ua->put($self->_shockurl()."/node/".$data->{data}->{id}."/acl/all?users=".$self->_getUsername(),Authorization => "OAuth ".$self->_wsauth());
	print "authorizing shock node output:\n".Data::Dumper->Dump([$res])."\n\n";
	return $data->{data}->{id};
}

#This function clears away any exiting objects before saving new objects. Returns a hash of all workspaces involved
sub _clear_existing_objects_before_save {
	my ($self,$objects,$overwrite) = @_;
	my $workspaces = {};
    my $delete = [];
    my $deletews = [];
    for (my $i=0; $i < @{$objects}; $i++) {
    	my ($user,$workspace,$path) = $self->_parse_ws_path($objects->[$i]->[0]);
    	if (!defined($workspaces->{$user}->{$workspace})) {
    		$workspaces->{$user}->{$workspace} = $self->_get_db_ws({
    			name => $workspace,
    			owner => $user
    		});
    		$self->_check_ws_permissions($workspaces->{$user}->{$workspace},"w",1);
    	}
    	my $obj = $self->_get_db_object({
	    	workspace_uuid => $workspaces->{$user}->{$workspace}->{uuid},
	    	path => $path,
	    	name => $objects->[$i]->[1]
	    },0);
    	if (defined($obj)) {
    		if ($obj->{directory} == 1) {
    			$self->_error("Cannot overwrite directory /".$user."/".$workspace."/".$workspace."/".$objects->[$i]->[1]." on save!");
    		} elsif ($overwrite == 0) {
    			$self->_error("Overwriting object /".$user."/".$workspace."/".$workspace."/".$objects->[$i]->[1]." and overwrite flag is not set!");
    		}
    		push(@{$delete},$obj);
    		push(@{$deletews},$workspaces->{$user}->{$workspace});
    	}
    }
    for (my $i=0; $i < @{$delete}; $i++) {
    	$self->_delete_object($delete->[$i],$deletews->[$i],1,0);
    }
    return $workspaces;
}

#END_HEADER

sub new
{
    my($class, @args) = @_;
    my $self = {
    };
    bless $self, $class;
    #BEGIN_CONSTRUCTOR

    my $params = $args[0];
    my $paramlist = [qw(
    	shock-url
    	db-path
    	mongodb-database
    	mongodb-host
    	mongodb-user
    	mongodb-pwd
    	url
    	wsuser
    	wspassword
    )];
    if ((my $e = $ENV{KB_DEPLOYMENT_CONFIG}) && -e $ENV{KB_DEPLOYMENT_CONFIG}) {
		my $service = $ENV{KB_SERVICE_NAME};
		if (!defined($service)) {
			$service = "Workspace";
		}
		if (defined($service)) {
			my $c = Config::Simple->new();
			$c->read($e);
			for my $p (@{$paramlist}) {
			  	my $v = $c->param("$service.$p");
			    if ($v && !defined($params->{$p})) {
					$params->{$p} = $v;
					if ($v eq "null") {
						$params->{$p} = undef;
					}
			    }
			}
		}
    }    
	$params = $self->_validateargs($params,["db-path","wsuser","wspassword"],{
		"mongodb-host" => "localhost",
		"mongodb-database" => "P3Workspace",
		"mongodb-user" => undef,
		"mongodb-pwd" => undef,
		url => "http://kbase.us/services/P3workspace"
	});
	$params->{"db-path"} .= "/P3WSDB/";
	my $config = {
		host => $params->{"mongodb-host"},
		db_name => $params->{"mongodb-database"},
		auto_connect => 1,
		auto_reconnect => 1
	};
	if(defined $params->{"mongodb-user"} && defined $params->{"mongodb-pwd"}) {
		$config->{username} = $params->{"mongodb-user"};
		$config->{password} = $params->{"mongodb-pwd"};
	}
	my $conn = MongoDB::Connection->new(%$config);
	if (!defined($conn)) {
		$self->_error("Unable to connect to mongodb database!");
	}
	$self->{_mongodb} = $conn->get_database($params->{"mongodb-database"});
	$self->{_params} = $params;
	$self->{_params}->{"db-path"} =~ s/\/\//\//g;
	$self->{_params}->{"db-path"} =~ s/\/$//g;
    #END_CONSTRUCTOR

    if ($self->can('_init_instance'))
    {
	$self->_init_instance();
    }
    return $self;
}

=head1 METHODS



=head2 create_workspace

  $output = $obj->create_workspace($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a create_workspace_params
$output is a WorkspaceMeta
create_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a WorkspaceName
	permission has a value which is a WorkspacePerm
	metadata has a value which is a UserMetadata
WorkspaceName is a string
WorkspacePerm is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
Username is a string
Timestamp is a string

</pre>

=end html

=begin text

$input is a create_workspace_params
$output is a WorkspaceMeta
create_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a WorkspaceName
	permission has a value which is a WorkspacePerm
	metadata has a value which is a UserMetadata
WorkspaceName is a string
WorkspacePerm is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
Username is a string
Timestamp is a string


=end text



=item Description



=back

=cut

sub create_workspace
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to create_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_workspace');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN create_workspace
    $input = $self->_validateargs($input,["workspace"],{
		permission => "n",
		metadata => {}
	});
    $input->{workspace} = $self->_validate_workspace_name($input->{workspace});
    $input->{permission} = $self->_validate_workspace_permission($input->{permission});
    if (-d $self->_db_path()."/".$self->_getUsername()."/".$input->{workspace}) {
    	$self->_error("Workspace ".$self->_getUsername()."/".$input->{workspace}." already exists!");
    }
    #Creating workspace directory on disk
    File::Path::mkpath ($self->_db_path()."/".$self->_getUsername()."/".$input->{workspace});
    my $uuid = Data::UUID->new()->create_str();
    $self->_mongodb()->get_collection('workspaces')->insert({
		creation_date => DateTime->now()->datetime(),
		uuid => $uuid,
		name => $input->{workspace},
		owner => $self->_getUsername(),
		global_permission => $input->{permission},
		metadata => $input->{metadata},
		permissions => {}
	});
	my $ws = $self->_get_db_ws({
		name => $input->{workspace},
		owner => $self->_getUsername()
	});
	$output = $self->_generate_ws_meta($ws);
    #END create_workspace
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to create_workspace:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_workspace');
    }
    return($output);
}




=head2 save_objects

  $output = $obj->save_objects($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a save_objects_params
$output is a reference to a list where each element is an ObjectMeta
save_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 5 items:
	0: a WorkspacePath
	1: an ObjectName
	2: an ObjectData
	3: an ObjectType
	4: a UserMetadata

	overwrite has a value which is a bool
WorkspacePath is a string
ObjectName is a string
ObjectData is a reference to a hash where the following keys are defined:
	id has a value which is a string
ObjectType is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a save_objects_params
$output is a reference to a list where each element is an ObjectMeta
save_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 5 items:
	0: a WorkspacePath
	1: an ObjectName
	2: an ObjectData
	3: an ObjectType
	4: a UserMetadata

	overwrite has a value which is a bool
WorkspacePath is a string
ObjectName is a string
ObjectData is a reference to a hash where the following keys are defined:
	id has a value which is a string
ObjectType is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub save_objects
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to save_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'save_objects');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN save_objects
    $input = $self->_validateargs($input,["objects"],{
		overwrite => 1
	});
    my $wshash = $self->_clear_existing_objects_before_save($input->{objects},$input->{overwrite});
    for (my $i=0; $i < @{$input->{objects}}; $i++) {
    	my ($user,$workspace,$path) = $self->_parse_ws_path($input->{objects}->[$i]->[0]);
    	my $obj = $self->_create_new_object($wshash->{$user}->{$workspace},{
    		directory => 0,
			workspace_uuid => $wshash->{$user}->{$workspace}->{uuid},
			workspace_owner => $wshash->{$user}->{$workspace}->{owner},
			shock => 0,
			path => $path,
			name => $input->{objects}->[$i]->[1],
			type => $input->{objects}->[$i]->[3],
			metadata => $input->{objects}->[$i]->[4],
    	},$input->{objects}->[$i]->[2]);
    	push(@{$output},$self->_generate_object_meta($obj,$wshash->{$user}->{$workspace}))
    }
    #END save_objects
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to save_objects:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'save_objects');
    }
    return($output);
}




=head2 create_upload_node

  $output = $obj->create_upload_node($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a create_upload_node_params
$output is a reference to a list where each element is a string
create_upload_node_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 3 items:
	0: a WorkspacePath
	1: an ObjectName
	2: an ObjectType

	overwrite has a value which is a bool
WorkspacePath is a string
ObjectName is a string
ObjectType is a string
bool is an int

</pre>

=end html

=begin text

$input is a create_upload_node_params
$output is a reference to a list where each element is a string
create_upload_node_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 3 items:
	0: a WorkspacePath
	1: an ObjectName
	2: an ObjectType

	overwrite has a value which is a bool
WorkspacePath is a string
ObjectName is a string
ObjectType is a string
bool is an int


=end text



=item Description



=back

=cut

sub create_upload_node
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to create_upload_node:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_upload_node');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN create_upload_node
    $input = $self->_validateargs($input,["objects"],{
		overwrite => 1
	});
    my $wshash = $self->_clear_existing_objects_before_save($input->{objects},$input->{overwrite});
    for (my $i=0; $i < @{$input->{objects}}; $i++) {
    	my ($user,$workspace,$path) = $self->_parse_ws_path($input->{objects}->[$i]->[0]);
    	my $shocknode = $self->_shockurl()."/node/".$self->_create_shock_node();
    	my $obj = $self->_create_new_object($wshash->{$user}->{$workspace},{
    		directory => 0,
    		shock => 1,
    		shocknode => $shocknode,
			workspace_uuid => $wshash->{$user}->{$workspace}->{uuid},
			workspace_owner => $wshash->{$user}->{$workspace}->{owner},
			path => $path,
			name => $input->{objects}->[$i]->[1],
			type => $input->{objects}->[$i]->[2],
			metadata => $input->{objects}->[$i]->[3],
    	},undef);
    	push(@{$output},$shocknode);
    }
    #END create_upload_node
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to create_upload_node:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_upload_node');
    }
    return($output);
}




=head2 get_objects

  $output = $obj->get_objects($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a get_objects_params
$output is a reference to a list where each element is an ObjectDataInfo
get_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: a WorkspacePath
	1: an ObjectName

WorkspacePath is a string
ObjectName is a string
ObjectDataInfo is a reference to a hash where the following keys are defined:
	data has a value which is an ObjectData
	info has a value which is an ObjectMeta
ObjectData is a reference to a hash where the following keys are defined:
	id has a value which is a string
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a get_objects_params
$output is a reference to a list where each element is an ObjectDataInfo
get_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: a WorkspacePath
	1: an ObjectName

WorkspacePath is a string
ObjectName is a string
ObjectDataInfo is a reference to a hash where the following keys are defined:
	data has a value which is an ObjectData
	info has a value which is an ObjectMeta
ObjectData is a reference to a hash where the following keys are defined:
	id has a value which is a string
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub get_objects
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objects');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN get_objects
    $input = $self->_validateargs($input,["objects"],{metadata_only => 0});
    my $workspaces = {};
    for (my $i=0; $i < @{$input->{objects}}; $i++) {
    	my ($user,$workspace,$path) = $self->_parse_ws_path($input->{objects}->[$i]->[0]);
    	if (!defined($workspaces->{$user}->{$workspace})) {
    		$workspaces->{$user}->{$workspace} = $self->_get_db_ws({
    			name => $workspace,
    			owner => $user
    		});
    		$workspaces->{$user}->{$workspace}->{currperm} = $self->_check_ws_permissions($workspaces->{$user}->{$workspace},"r",0);
    	}
    	if ($workspaces->{$user}->{$workspace}->{currperm} == 1) {
	    	my $obj = $self->_get_db_object({
	    		workspace_uuid => $workspaces->{$user}->{$workspace}->{uuid},
	    		path => $path,
	    		name => $input->{objects}->[$i]->[1]
	    	});
	    	if ($input->{metadata_only} == 1) {
		    	push(@{$output},{
		    		info => $self->_generate_object_meta($obj,$workspaces->{$user}->{$workspace})
		    	});
	    	} else {
	    		push(@{$output},{
		    		info => $self->_generate_object_meta($obj,$workspaces->{$user}->{$workspace}),
	    			data => $self->_retrieve_object_data($obj,$workspaces->{$user}->{$workspace})
		    	});
	    	}
    	}
    }
    #END get_objects
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_objects:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objects');
    }
    return($output);
}




=head2 get_objects_by_reference

  $output = $obj->get_objects_by_reference($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a get_objects_by_reference_params
$output is a reference to a list where each element is an ObjectDataInfo
get_objects_by_reference_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is an ObjectID
ObjectID is a string
ObjectDataInfo is a reference to a hash where the following keys are defined:
	data has a value which is an ObjectData
	info has a value which is an ObjectMeta
ObjectData is a reference to a hash where the following keys are defined:
	id has a value which is a string
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
WorkspacePath is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a get_objects_by_reference_params
$output is a reference to a list where each element is an ObjectDataInfo
get_objects_by_reference_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is an ObjectID
ObjectID is a string
ObjectDataInfo is a reference to a hash where the following keys are defined:
	data has a value which is an ObjectData
	info has a value which is an ObjectMeta
ObjectData is a reference to a hash where the following keys are defined:
	id has a value which is a string
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
WorkspacePath is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub get_objects_by_reference
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to get_objects_by_reference:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objects_by_reference');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN get_objects_by_reference
    $input = $self->_validateargs($input,["objects"],{metadata_only => 0});
    my $query = {uuid => {'$in' => $input->{objects}}};
	my $objects = $self->_query_database($query,0);
	$output = [];
	my $wscache = {};
	for (my $i=0; $i < @{$objects}; $i++) {
		my $object = $objects->[$i];
		if (!defined($wscache->{$object->{workspace_uuid}})) {
			$wscache->{$object->{workspace_uuid}} = $self->_get_db_ws({
		    	uuid => $object->{workspace_uuid}
		    });
			$wscache->{$object->{workspace_uuid}}->{currperm} = $self->_check_ws_permissions($wscache->{$object->{workspace_uuid}},"r",0);
		}
		if ($wscache->{$object->{workspace_uuid}}->{currperm} == 1) {
			if ($input->{metadata_only} == 1) {
				push(@{$output},{
					info => $self->_generate_object_meta($object,$wscache->{$object->{workspace_uuid}}),
				});
			} else {
				push(@{$output},{
					info => $self->_generate_object_meta($object,$wscache->{$object->{workspace_uuid}}),
					data => $self->_retrieve_object_data($object,$wscache->{$object->{workspace_uuid}})
				});
			}
		}
	}
    #END get_objects_by_reference
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to get_objects_by_reference:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'get_objects_by_reference');
    }
    return($output);
}




=head2 list_workspace_contents

  $output = $obj->list_workspace_contents($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_workspace_contents_params
$output is a reference to a list where each element is an ObjectMeta
list_workspace_contents_params is a reference to a hash where the following keys are defined:
	directory has a value which is a WorkspacePath
	includeSubDirectories has a value which is a bool
	excludeObjects has a value which is a bool
	Recursive has a value which is a bool
WorkspacePath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a list_workspace_contents_params
$output is a reference to a list where each element is an ObjectMeta
list_workspace_contents_params is a reference to a hash where the following keys are defined:
	directory has a value which is a WorkspacePath
	includeSubDirectories has a value which is a bool
	excludeObjects has a value which is a bool
	Recursive has a value which is a bool
WorkspacePath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub list_workspace_contents
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_workspace_contents:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspace_contents');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN list_workspace_contents
    $input = $self->_validateargs($input,["directory"],{
    	includeSubDirectories => 1,
    	excludeObjects => 0,
    	Recursive => 1
    });
    my ($user,$workspace,$path) = $self->_parse_ws_path($input->{directory});
    my $ws = $self->_get_db_ws({
    	owner => $user,
    	name => $workspace
    });
    $self->_check_ws_permissions($ws,"r",1);
    my $query = {
   		workspace_uuid => $ws->{uuid},
   		path => $path
   	};
   	if ($input->{includeSubDirectories} == 0) {
   		$query->{directory} = 0;
   	}
   	if ($input->{excludeObjects} == 1) {
   		$query->{directory} = 1;
   	}
   	if ($input->{Recursive} == 1) {
   		if ($path eq "") {
   			delete $query->{path};
   		} else {
   			$query->{path} = qr/^$path/;
   		}	
   	}
   	$output = [];
   	my $objects = $self->_query_database($query,0);
   	for (my $i=0; $i < @{$objects}; $i++) {
		my $object = $objects->[$i];
		push(@{$output},$self->_generate_object_meta($object,$ws));
	}
    #END list_workspace_contents
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_workspace_contents:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspace_contents');
    }
    return($output);
}




=head2 list_workspace_hierarchical_contents

  $output = $obj->list_workspace_hierarchical_contents($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_workspace_hierarchical_contents_params
$output is a reference to a hash where the key is a WorkspacePath and the value is a reference to a list where each element is an ObjectMeta
list_workspace_hierarchical_contents_params is a reference to a hash where the following keys are defined:
	directory has a value which is a WorkspacePath
	includeSubDirectories has a value which is a bool
	excludeObjects has a value which is a bool
	Recursive has a value which is a bool
WorkspacePath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a list_workspace_hierarchical_contents_params
$output is a reference to a hash where the key is a WorkspacePath and the value is a reference to a list where each element is an ObjectMeta
list_workspace_hierarchical_contents_params is a reference to a hash where the following keys are defined:
	directory has a value which is a WorkspacePath
	includeSubDirectories has a value which is a bool
	excludeObjects has a value which is a bool
	Recursive has a value which is a bool
WorkspacePath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub list_workspace_hierarchical_contents
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_workspace_hierarchical_contents:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspace_hierarchical_contents');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN list_workspace_hierarchical_contents
    $input = $self->_validateargs($input,["directory"],{
    	includeSubDirectories => 1,
    	excludeObjects => 0,
    	Recursive => 1
    });
    my ($user,$workspace,$path) = $self->_parse_ws_path($input->{directory});
    my $ws = $self->_get_db_ws({
    	owner => $user,
    	name => $workspace
    });
    $self->_check_ws_permissions($ws,"r",1);
    my $query = {
   		workspace_uuid => $ws->{uuid},
   		path => $path
   	};
   	if ($input->{includeSubDirectories} == 0) {
   		$query->{directory} = 0;
   	}
   	if ($input->{excludeObjects} == 1) {
   		$query->{directory} = 1;
   	}
   	if ($input->{Recursive} == 1) {
   		if ($path eq "") {
   			delete $query->{path};
   		} else {
   			$query->{path} = qr/^$path/;
   		}	
   	}
   	$output = {};
   	my $objects = $self->_query_database($query,0);
   	for (my $i=0; $i < @{$objects}; $i++) {
		my $object = $objects->[$i];
		my $objpath = "/".$ws->{owner}."/".$ws->{name}."/".$object->{path};
		if (length($object->{path}) == 0) {
			$objpath = "/".$ws->{owner}."/".$ws->{name};
		}
		push(@{$output->{$objpath}},$self->_generate_object_meta($object,$ws));
	}
    #END list_workspace_hierarchical_contents
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_workspace_hierarchical_contents:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspace_hierarchical_contents');
    }
    return($output);
}




=head2 list_workspaces

  $output = $obj->list_workspaces($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_workspaces_params
$output is a reference to a list where each element is a WorkspaceMeta
list_workspaces_params is a reference to a hash where the following keys are defined:
	owned_only has a value which is a bool
	no_public has a value which is a bool
bool is an int
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
WorkspaceName is a string
Username is a string
Timestamp is a string
WorkspacePerm is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a list_workspaces_params
$output is a reference to a list where each element is a WorkspaceMeta
list_workspaces_params is a reference to a hash where the following keys are defined:
	owned_only has a value which is a bool
	no_public has a value which is a bool
bool is an int
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
WorkspaceName is a string
Username is a string
Timestamp is a string
WorkspacePerm is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub list_workspaces
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_workspaces:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspaces');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN list_workspaces
    $input = $self->_validateargs($input,[],{
    	owned_only => 0,
		no_public => 0
    });
    my $query = {
    	owner => $self->_getUsername()
    };
    if ($input->{owned_only} == 0) {
    	if ($input->{no_public} == 0) {
    		$query = { '$or' => [ {owner => $self->_getUsername()},{global_permission => {'$ne' => "n"} },{"permissions.".$self->_escape_username($self->_getUsername()) => {'$exists' => 1 } } ] };
    	} else {
    		$query = { '$or' => [ {owner => $self->_getUsername()},{"permissions.".$self->_escape_username($self->_getUsername()) => {'$exists' => 1 } } ] };
    	}
    }
    my $output = [];
    my $cursor = $self->_mongodb()->get_collection('workspaces')->find($query);
	while (my $object = $cursor->next) {
		push(@{$output},$self->_generate_ws_meta($object));
	}
    #END list_workspaces
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_workspaces:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspaces');
    }
    return($output);
}




=head2 search_for_workspaces

  $output = $obj->search_for_workspaces($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a search_for_workspaces_params
$output is a reference to a list where each element is a WorkspaceMeta
search_for_workspaces_params is a reference to a hash where the following keys are defined:
	workspace_query has a value which is a reference to a hash where the key is a string and the value is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
WorkspaceName is a string
Username is a string
Timestamp is a string
WorkspacePerm is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a search_for_workspaces_params
$output is a reference to a list where each element is a WorkspaceMeta
search_for_workspaces_params is a reference to a hash where the following keys are defined:
	workspace_query has a value which is a reference to a hash where the key is a string and the value is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
WorkspaceName is a string
Username is a string
Timestamp is a string
WorkspacePerm is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub search_for_workspaces
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to search_for_workspaces:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'search_for_workspaces');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN search_for_workspaces
    $input = $self->_validateargs($input,["workspace_query"],{});
    #END search_for_workspaces
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to search_for_workspaces:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'search_for_workspaces');
    }
    return($output);
}




=head2 search_for_workspace_objects

  $output = $obj->search_for_workspace_objects($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a search_for_workspace_objects_params
$output is a reference to a list where each element is an ObjectMeta
search_for_workspace_objects_params is a reference to a hash where the following keys are defined:
	workspace_query has a value which is a reference to a hash where the key is a string and the value is a string
	object_query has a value which is a reference to a hash where the key is a string and the value is a string
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
WorkspacePath is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a search_for_workspace_objects_params
$output is a reference to a list where each element is an ObjectMeta
search_for_workspace_objects_params is a reference to a hash where the following keys are defined:
	workspace_query has a value which is a reference to a hash where the key is a string and the value is a string
	object_query has a value which is a reference to a hash where the key is a string and the value is a string
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
WorkspacePath is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub search_for_workspace_objects
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to search_for_workspace_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'search_for_workspace_objects');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN search_for_workspace_objects
    $input = $self->_validateargs($input,["object_query"],{
    	workspace_query => {}
    });
    #END search_for_workspace_objects
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to search_for_workspace_objects:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'search_for_workspace_objects');
    }
    return($output);
}




=head2 create_workspace_directory

  $output = $obj->create_workspace_directory($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a create_workspace_directory_params
$output is an ObjectMeta
create_workspace_directory_params is a reference to a hash where the following keys are defined:
	directory has a value which is a WorkspacePath
	metadata has a value which is a UserMetadata
WorkspacePath is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a create_workspace_directory_params
$output is an ObjectMeta
create_workspace_directory_params is a reference to a hash where the following keys are defined:
	directory has a value which is a WorkspacePath
	metadata has a value which is a UserMetadata
WorkspacePath is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub create_workspace_directory
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to create_workspace_directory:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_workspace_directory');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN create_workspace_directory
    $input = $self->_validateargs($input,["directory"],{
    	metadata => {}
    });
    my ($user,$workspace,$path) = $self->_parse_ws_path($input->{directory});
    my $ws = $self->_get_db_ws({
    	owner => $user,
    	name => $workspace
    });
    $self->_check_ws_permissions($ws,"w");
    ($path,my $name) = $self->_parse_directory_name($path);
    my $obj = $self->_create_new_object($ws,{
		directory => 1,
		workspace_uuid => $ws->{uuid},
		workspace_owner => $ws->{owner},
		path => $path,
		name => $name,
		metadata => $input->{metadata},
		type => "Directory"
    });
    $output = $self->_generate_object_meta($obj,$ws);
    #END create_workspace_directory
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to create_workspace_directory:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'create_workspace_directory');
    }
    return($output);
}




=head2 copy_objects

  $output = $obj->copy_objects($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a copy_objects_params
$output is a reference to a list where each element is an ObjectMeta
copy_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
	0: (source) a WorkspacePath
	1: (origname) an ObjectName
	2: (destination) a WorkspacePath
	3: (newname) an ObjectName

	overwrite has a value which is a bool
	recursive has a value which is a bool
WorkspacePath is a string
ObjectName is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a copy_objects_params
$output is a reference to a list where each element is an ObjectMeta
copy_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
	0: (source) a WorkspacePath
	1: (origname) an ObjectName
	2: (destination) a WorkspacePath
	3: (newname) an ObjectName

	overwrite has a value which is a bool
	recursive has a value which is a bool
WorkspacePath is a string
ObjectName is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub copy_objects
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to copy_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'copy_objects');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN copy_objects
    $input = $self->_validateargs($input,["objects"],{
    	overwrite => 0,
    	recursive => 0
    });
    $output = $self->_copy_or_move_objects($input->{objects},$input->{overwrite},$input->{recursive},0);
    #END copy_objects
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to copy_objects:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'copy_objects');
    }
    return($output);
}




=head2 move_objects

  $output = $obj->move_objects($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a move_objects_params
$output is a reference to a list where each element is an ObjectMeta
move_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
	0: (source) a WorkspacePath
	1: (origname) an ObjectName
	2: (destination) a WorkspacePath
	3: (newname) an ObjectName

	overwrite has a value which is a bool
	recursive has a value which is a bool
WorkspacePath is a string
ObjectName is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a move_objects_params
$output is a reference to a list where each element is an ObjectMeta
move_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
	0: (source) a WorkspacePath
	1: (origname) an ObjectName
	2: (destination) a WorkspacePath
	3: (newname) an ObjectName

	overwrite has a value which is a bool
	recursive has a value which is a bool
WorkspacePath is a string
ObjectName is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub move_objects
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to move_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'move_objects');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN move_objects
    $input = $self->_validateargs($input,["objects"],{
    	overwrite => 0,
    	recursive => 0
    });
    $output = $self->_copy_or_move_objects($input->{objects},$input->{overwrite},$input->{recursive},1);
    #END move_objects
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to move_objects:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'move_objects');
    }
    return($output);
}




=head2 delete_workspace

  $output = $obj->delete_workspace($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a delete_workspace_params
$output is a WorkspaceMeta
delete_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a WorkspaceName
WorkspaceName is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
Username is a string
Timestamp is a string
WorkspacePerm is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a delete_workspace_params
$output is a WorkspaceMeta
delete_workspace_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a WorkspaceName
WorkspaceName is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
Username is a string
Timestamp is a string
WorkspacePerm is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub delete_workspace
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to delete_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_workspace');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN delete_workspace
    $input = $self->_validateargs($input,["workspace"],{});
    my $ws = $self->_get_db_ws({
    	raw_id => $input->{workspace}
    });
    $self->_check_ws_permissions($ws,"o");
    rmtree($self->_db_path()."/".$ws->{owner}."/".$ws->{name});
    $self->_mongodb()->get_collection('workspaces')->remove({uuid => $ws->{uuid}});
    $self->_mongodb()->get_collection('objects')->remove({workspace_uuid => $ws->{uuid}});
    $output = $self->_generate_ws_meta($ws);
    #END delete_workspace
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to delete_workspace:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_workspace');
    }
    return($output);
}




=head2 delete_objects

  $output = $obj->delete_objects($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a delete_objects_params
$output is a reference to a list where each element is an ObjectMeta
delete_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: a WorkspacePath
	1: an ObjectName

	delete_directories has a value which is a bool
	force has a value which is a bool
WorkspacePath is a string
ObjectName is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a delete_objects_params
$output is a reference to a list where each element is an ObjectMeta
delete_objects_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: a WorkspacePath
	1: an ObjectName

	delete_directories has a value which is a bool
	force has a value which is a bool
WorkspacePath is a string
ObjectName is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub delete_objects
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to delete_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_objects');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN delete_objects
    $input = $self->_validateargs($input,["objects"],{
    	delete_directories => 0,
    	force => 0
    });
    my $workspaces = {};
    my $objhash = {};
    for (my $i=0; $i < @{$input->{objects}}; $i++) {
    	my ($user,$workspace,$path) = $self->_parse_ws_path($input->{objects}->[$i]->[0]);
    	if (!defined($workspaces->{$user}->{$workspace})) {
    		$workspaces->{$user}->{$workspace} = $self->_get_db_ws({
    			name => $workspace,
    			owner => $user
    		});
    		$self->_check_ws_permissions($workspaces->{$user}->{$workspace},"w");
    	}    	
    	$objhash->{$user}->{$workspace}->{$path}->{$input->{objects}->[$i]->[1]} = $self->_get_db_object({
    		workspace_uuid => $workspaces->{$user}->{$workspace}->{uuid},
    		path => $path,
    		name => $input->{objects}->[$i]->[1]
    	});
    	push(@{$output},$self->_generate_object_meta($objhash->{$user}->{$workspace}->{$path}->{$input->{objects}->[$i]->[1]},$workspaces->{$user}->{$workspace}));
    	if ($objhash->{$user}->{$workspace}->{$path}->{$input->{objects}->[$i]->[1]}->{directory} == 1) {
    		if ($input->{delete_directories} == 0) {
    			$self->_error("Object list includes directories, and delete_directories flag was not set!");
    		} elsif ($input->{force} == 0 && $self->_count_directory_contents($objhash->{$user}->{$workspace}->{$path}->{$input->{objects}->[$i]->[1]},0) > 0) {
    			$self->_error("Deleting a non-empty directory, and force flag was not set!");
    		}
    	}
    }
    foreach my $user (keys(%{$objhash})) {
    	foreach my $workspace (keys(%{$objhash->{$user}})) {
    		my $paths = [reverse(sort(keys(%{$objhash->{$user}->{$workspace}})))];
    		foreach my $path (@{$paths}) {
    			foreach my $object (keys(%{$objhash->{$user}->{$workspace}->{$path}})) {
    				$self->_delete_object($objhash->{$user}->{$workspace}->{$path}->{$object},$workspaces->{$user}->{$workspace},1,1);
    			}
    		}
    	}
    }
    #END delete_objects
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to delete_objects:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_objects');
    }
    return($output);
}




=head2 delete_workspace_directory

  $output = $obj->delete_workspace_directory($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a delete_workspace_directory_params
$output is an ObjectMeta
delete_workspace_directory_params is a reference to a hash where the following keys are defined:
	directory has a value which is a WorkspacePath
	force has a value which is a bool
WorkspacePath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a delete_workspace_directory_params
$output is an ObjectMeta
delete_workspace_directory_params is a reference to a hash where the following keys are defined:
	directory has a value which is a WorkspacePath
	force has a value which is a bool
WorkspacePath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectID
	1: an ObjectName
	2: an ObjectType
	3: (creation_time) a Timestamp
	4: a WorkspaceReference
	5: (object_owner) a Username
	6: a WorkspaceID
	7: a WorkspaceName
	8: a WorkspacePath
	9: an ObjectSize
	10: a UserMetadata
	11: an AutoMetadata
ObjectID is a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
WorkspaceReference is a string
Username is a string
WorkspaceID is a string
WorkspaceName is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub delete_workspace_directory
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to delete_workspace_directory:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_workspace_directory');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN delete_workspace_directory
    $input = $self->_validateargs($input,["directory"],{
    	force => 0
    });
    my ($user,$workspace,$path) = $self->_parse_ws_path($input->{directory});
    my $ws = $self->_get_db_ws({
    	name => $workspace,
    	owner => $user
    });
    $self->_check_ws_permissions($ws,"w",1);
    ($path,my $name) = $self->_parse_directory_name($path);
    my $obj = $self->_get_db_object({
    	workspace_uuid => $ws->{uuid},
    	path => $path,
    	name => $name
    });
    if ($obj->{directory} == 0) {
    	$self->_error("Specified object is not a directory!");
    }
    if ($input->{force} == 0 && $self->_count_directory_contents($obj,0) > 0) {
    	$self->_error("Deleting a non-empty directory, and force flag was not set!");
    }
    $self->_delete_object($obj,$ws,1,1); 
    $output = $self->_generate_object_meta($obj,$ws);
    #END delete_workspace_directory
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to delete_workspace_directory:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'delete_workspace_directory');
    }
    return($output);
}




=head2 reset_global_permission

  $output = $obj->reset_global_permission($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a reset_global_permission_params
$output is a WorkspaceMeta
reset_global_permission_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a WorkspaceName
	global_permission has a value which is a WorkspacePerm
WorkspaceName is a string
WorkspacePerm is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
Username is a string
Timestamp is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a reset_global_permission_params
$output is a WorkspaceMeta
reset_global_permission_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a WorkspaceName
	global_permission has a value which is a WorkspacePerm
WorkspaceName is a string
WorkspacePerm is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
Username is a string
Timestamp is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub reset_global_permission
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to reset_global_permission:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'reset_global_permission');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN reset_global_permission
    $input = $self->_validateargs($input,["workspace","global_permission"],{});
    my $ws = $self->_get_db_ws({
    	raw_id => $input->{workspace}
    });
    $self->_check_ws_permissions($ws,"a",1);
    $input->{global_permission} = $self->_validate_workspace_permission($input->{global_permission});
    $self->_updateDB("workspaces",{uuid => $ws->{uuid}},{'$set' => {global_permission => $input->{global_permission}}});
    $ws->{global_permission} = $input->{global_permission};
    $output = $self->_generate_ws_meta($ws);
    #END reset_global_permission
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to reset_global_permission:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'reset_global_permission');
    }
    return($output);
}




=head2 set_workspace_permissions

  $output = $obj->set_workspace_permissions($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a set_workspace_permissions_params
$output is a WorkspaceMeta
set_workspace_permissions_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a WorkspaceName
	permissions has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm

WorkspaceName is a string
Username is a string
WorkspacePerm is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
Timestamp is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a set_workspace_permissions_params
$output is a WorkspaceMeta
set_workspace_permissions_params is a reference to a hash where the following keys are defined:
	workspace has a value which is a WorkspaceName
	permissions has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm

WorkspaceName is a string
Username is a string
WorkspacePerm is a string
WorkspaceMeta is a reference to a list containing 9 items:
	0: a WorkspaceID
	1: a WorkspaceName
	2: (workspace_owner) a Username
	3: (moddate) a Timestamp
	4: (num_objects) an int
	5: (user_permission) a WorkspacePerm
	6: (global_permission) a WorkspacePerm
	7: (num_directories) an int
	8: a UserMetadata
WorkspaceID is a string
Timestamp is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string


=end text



=item Description



=back

=cut

sub set_workspace_permissions
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to set_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_workspace_permissions');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN set_workspace_permissions
    $input = $self->_validateargs($input,["workspace","permissions"],{});
    my $ws = $self->_get_db_ws({
    	raw_id => $input->{workspace}
    });
    $self->_check_ws_permissions($ws,"a",1);
    for (my $i=0; $i < @{$input->{permissions}}; $i++) {
    	$input->{permissions}->[$i]->[1] = $self->_validate_workspace_permission($input->{permissions}->[$i]->[1]);
    	$input->{permissions}->[$i]->[0] = $self->_escape_username($input->{permissions}->[$i]->[0]);
    	if ($input->{permissions}->[$i]->[1] eq "n" && defined($ws->{permissions}->{$input->{permissions}->[$i]->[0]})) {
    		$self->_updateDB("workspaces",{owner => $self->_getUsername(),name => $input->{workspace}},{'$unset' => {'permissions.'.$input->{permissions}->[$i]->[0] => $ws->{permissions}->{$input->{permissions}->[$i]->[0]}}});
    	} else {
    		$self->_updateDB("workspaces",{owner => $self->_getUsername(),name => $input->{workspace}},{'$set' => {'permissions.'.$input->{permissions}->[$i]->[0] => $input->{permissions}->[$i]->[1]}});
    	}
    }
    $output = $self->_generate_ws_meta($ws);
    #END set_workspace_permissions
    my @_bad_returns;
    (ref($output) eq 'ARRAY') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to set_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'set_workspace_permissions');
    }
    return($output);
}




=head2 list_workspace_permissions

  $output = $obj->list_workspace_permissions($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_workspace_permissions_params
$output is a reference to a hash where the key is a string and the value is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm
list_workspace_permissions_params is a reference to a hash where the following keys are defined:
	workspaces has a value which is a reference to a list where each element is a WorkspaceName
WorkspaceName is a string
Username is a string
WorkspacePerm is a string

</pre>

=end html

=begin text

$input is a list_workspace_permissions_params
$output is a reference to a hash where the key is a string and the value is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm
list_workspace_permissions_params is a reference to a hash where the following keys are defined:
	workspaces has a value which is a reference to a list where each element is a WorkspaceName
WorkspaceName is a string
Username is a string
WorkspacePerm is a string


=end text



=item Description



=back

=cut

sub list_workspace_permissions
{
    my $self = shift;
    my($input) = @_;

    my @_bad_arguments;
    (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument \"input\" (value was \"$input\")");
    if (@_bad_arguments) {
	my $msg = "Invalid arguments passed to list_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspace_permissions');
    }

    my $ctx = $Bio::P3::Workspace::Service::CallContext;
    my($output);
    #BEGIN list_workspace_permissions
    $input = $self->_validateargs($input,["workspaces"],{});
    for (my $i=0; $i < @{$input->{workspaces}}; $i++) {
    	my $ws = $self->_get_db_ws({
	    	raw_id => $input->{workspaces}->[$i]
	    });
	    if ($self->_check_ws_permissions($ws,"r",0) == 1) {
		    foreach my $user (keys(%{$ws->{permissions}})) {
		    	push(@{$output->{"/".$ws->{owner}."/".$ws->{name}}},[$self->_unescape_username($user),$ws->{permissions}->{$user}]);
		    }
	    }
    }
    #END list_workspace_permissions
    my @_bad_returns;
    (ref($output) eq 'HASH') or push(@_bad_returns, "Invalid type for return variable \"output\" (value was \"$output\")");
    if (@_bad_returns) {
	my $msg = "Invalid returns passed to list_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_returns);
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
							       method_name => 'list_workspace_permissions');
    }
    return($output);
}




=head2 version 

  $return = $obj->version()

=over 4

=item Parameter and return types

=begin html

<pre>
$return is a string
</pre>

=end html

=begin text

$return is a string

=end text

=item Description

Return the module version. This is a Semantic Versioning number.

=back

=cut

sub version {
    return $VERSION;
}

=head1 TYPES



=head2 WorkspacePerm

=over 4



=item Description

User permission in worksace (e.g. w - write, r - read, a - admin, n - none)


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 Username

=over 4



=item Description

Login name for user


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 bool

=over 4



=item Description

Login name for user


=item Definition

=begin html

<pre>
an int
</pre>

=end html

=begin text

an int

=end text

=back



=head2 Timestamp

=over 4



=item Description

Indication of a system time


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ObjectName

=over 4



=item Description

Name assigned to an object saved to a workspace


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ObjectID

=over 4



=item Description

Unique UUID assigned to every object in a workspace on save - IDs never reused


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ObjectType

=over 4



=item Description

Specified type of an object (e.g. Genome)


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 ObjectSize

=over 4



=item Description

Size of the object


=item Definition

=begin html

<pre>
an int
</pre>

=end html

=begin text

an int

=end text

=back



=head2 ObjectData

=over 4



=item Description

Generic type containing object data


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
id has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
id has a value which is a string


=end text

=back



=head2 WorkspacePath

=over 4



=item Description

Path to a workspace or workspace subdirectory


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 WorkspaceID

=over 4



=item Description

Unique UUID for workspace


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 WorkspaceName

=over 4



=item Description

Name for workspace specified by user


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 WorkspaceReference

=over 4



=item Description

A URI that can be used to restfully retrieve a data object from the workspace


=item Definition

=begin html

<pre>
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 UserMetadata

=over 4



=item Description

This is a key value hash of user-specified metadata


=item Definition

=begin html

<pre>
a reference to a hash where the key is a string and the value is a string
</pre>

=end html

=begin text

a reference to a hash where the key is a string and the value is a string

=end text

=back



=head2 AutoMetadata

=over 4



=item Description

This is a key value hash of automated metadata populated based on object type


=item Definition

=begin html

<pre>
a reference to a hash where the key is a string and the value is a string
</pre>

=end html

=begin text

a reference to a hash where the key is a string and the value is a string

=end text

=back



=head2 WorkspaceMeta

=over 4



=item Description

WorkspaceMeta: tuple containing information about a workspace 

        WorkspaceID - a globally unique UUID assigned every workspace that will never change
        WorkspaceName - name of the workspace.
        Username workspace_owner - name of the user who owns (e.g. created) this workspace.
        timestamp moddate - date when the workspace was last modified.
        int num_objects - the approximate number of objects (including directories) in the workspace.
        WorkspacePerm user_permission - permissions for the authenticated user of this workspace.
        WorkspacePerm global_permission - whether this workspace is globally readable.
        int num_directories - number of directories in workspace.
        UserMetadata - arbitrary metadata for workspace


=item Definition

=begin html

<pre>
a reference to a list containing 9 items:
0: a WorkspaceID
1: a WorkspaceName
2: (workspace_owner) a Username
3: (moddate) a Timestamp
4: (num_objects) an int
5: (user_permission) a WorkspacePerm
6: (global_permission) a WorkspacePerm
7: (num_directories) an int
8: a UserMetadata

</pre>

=end html

=begin text

a reference to a list containing 9 items:
0: a WorkspaceID
1: a WorkspaceName
2: (workspace_owner) a Username
3: (moddate) a Timestamp
4: (num_objects) an int
5: (user_permission) a WorkspacePerm
6: (global_permission) a WorkspacePerm
7: (num_directories) an int
8: a UserMetadata


=end text

=back



=head2 ObjectMeta

=over 4



=item Description

ObjectMeta: tuple containing information about an object in the workspace 

        ObjectID - a globally unique UUID assigned to very object that will never change
        ObjectName - name selected for object in workspace
        ObjectType - type of the object in the workspace
        Timestamp creation_time - time when the object was created
        WorkspaceReference - restful reference permitting retrieval of object in workspace
        Username object_owner - name of object owner
        WorkspaceID - UUID of workspace containing object
        WorkspaceName - name of workspace containing object
        WorkspacePath - full path to object in workspace
        ObjectSize - size of the object in bytes
        UserMetadata - arbitrary user metadata associated with object
        AutoMetadata - automatically populated metadata generated from object data in automated way


=item Definition

=begin html

<pre>
a reference to a list containing 12 items:
0: an ObjectID
1: an ObjectName
2: an ObjectType
3: (creation_time) a Timestamp
4: a WorkspaceReference
5: (object_owner) a Username
6: a WorkspaceID
7: a WorkspaceName
8: a WorkspacePath
9: an ObjectSize
10: a UserMetadata
11: an AutoMetadata

</pre>

=end html

=begin text

a reference to a list containing 12 items:
0: an ObjectID
1: an ObjectName
2: an ObjectType
3: (creation_time) a Timestamp
4: a WorkspaceReference
5: (object_owner) a Username
6: a WorkspaceID
7: a WorkspaceName
8: a WorkspacePath
9: an ObjectSize
10: a UserMetadata
11: an AutoMetadata


=end text

=back



=head2 ObjectDataInfo

=over 4



=item Description

This is the struct returned by get_objects, which includes object data and metadata


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
data has a value which is an ObjectData
info has a value which is an ObjectMeta

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
data has a value which is an ObjectData
info has a value which is an ObjectMeta


=end text

=back



=head2 create_workspace_params

=over 4



=item Description

********* DATA LOAD FUNCTIONS *******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a WorkspaceName
permission has a value which is a WorkspacePerm
metadata has a value which is a UserMetadata

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a WorkspaceName
permission has a value which is a WorkspacePerm
metadata has a value which is a UserMetadata


=end text

=back



=head2 save_objects_params

=over 4



=item Description

This function receives a list of objects, names, and types and stores the objects in the workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 5 items:
0: a WorkspacePath
1: an ObjectName
2: an ObjectData
3: an ObjectType
4: a UserMetadata

overwrite has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 5 items:
0: a WorkspacePath
1: an ObjectName
2: an ObjectData
3: an ObjectType
4: a UserMetadata

overwrite has a value which is a bool


=end text

=back



=head2 create_upload_node_params

=over 4



=item Description

This function creates a node in shock that the user can upload to and links this node to a workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 3 items:
0: a WorkspacePath
1: an ObjectName
2: an ObjectType

overwrite has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 3 items:
0: a WorkspacePath
1: an ObjectName
2: an ObjectType

overwrite has a value which is a bool


=end text

=back



=head2 get_objects_params

=over 4



=item Description

********* DATA RETRIEVAL FUNCTIONS *******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: a WorkspacePath
1: an ObjectName


</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: a WorkspacePath
1: an ObjectName



=end text

=back



=head2 get_objects_by_reference_params

=over 4



=item Description

This function retrieves a list of objects from the workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is an ObjectID

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is an ObjectID


=end text

=back



=head2 list_workspace_contents_params

=over 4



=item Description

This function lists the contents of the specified workspace (e.g. ls)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
directory has a value which is a WorkspacePath
includeSubDirectories has a value which is a bool
excludeObjects has a value which is a bool
Recursive has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
directory has a value which is a WorkspacePath
includeSubDirectories has a value which is a bool
excludeObjects has a value which is a bool
Recursive has a value which is a bool


=end text

=back



=head2 list_workspace_hierarchical_contents_params

=over 4



=item Description

This function lists the contents of the specified workspace (e.g. ls)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
directory has a value which is a WorkspacePath
includeSubDirectories has a value which is a bool
excludeObjects has a value which is a bool
Recursive has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
directory has a value which is a WorkspacePath
includeSubDirectories has a value which is a bool
excludeObjects has a value which is a bool
Recursive has a value which is a bool


=end text

=back



=head2 list_workspaces_params

=over 4



=item Description

This function lists all workspace volumes accessible by user


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
owned_only has a value which is a bool
no_public has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
owned_only has a value which is a bool
no_public has a value which is a bool


=end text

=back



=head2 search_for_workspaces_params

=over 4



=item Description

Provides a list of all objects in all workspaces whose name or workspace or path match the input query


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace_query has a value which is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace_query has a value which is a reference to a hash where the key is a string and the value is a string


=end text

=back



=head2 search_for_workspace_objects_params

=over 4



=item Description

Provides a list of all objects in all workspaces whose name or workspace or path match the input query


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace_query has a value which is a reference to a hash where the key is a string and the value is a string
object_query has a value which is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace_query has a value which is a reference to a hash where the key is a string and the value is a string
object_query has a value which is a reference to a hash where the key is a string and the value is a string


=end text

=back



=head2 create_workspace_directory_params

=over 4



=item Description

********* REORGANIZATION FUNCTIONS ******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
directory has a value which is a WorkspacePath
metadata has a value which is a UserMetadata

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
directory has a value which is a WorkspacePath
metadata has a value which is a UserMetadata


=end text

=back



=head2 copy_objects_params

=over 4



=item Description

This function copies an object to a new workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
0: (source) a WorkspacePath
1: (origname) an ObjectName
2: (destination) a WorkspacePath
3: (newname) an ObjectName

overwrite has a value which is a bool
recursive has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
0: (source) a WorkspacePath
1: (origname) an ObjectName
2: (destination) a WorkspacePath
3: (newname) an ObjectName

overwrite has a value which is a bool
recursive has a value which is a bool


=end text

=back



=head2 move_objects_params

=over 4



=item Description

This function copies an object to a new workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
0: (source) a WorkspacePath
1: (origname) an ObjectName
2: (destination) a WorkspacePath
3: (newname) an ObjectName

overwrite has a value which is a bool
recursive has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
0: (source) a WorkspacePath
1: (origname) an ObjectName
2: (destination) a WorkspacePath
3: (newname) an ObjectName

overwrite has a value which is a bool
recursive has a value which is a bool


=end text

=back



=head2 delete_workspace_params

=over 4



=item Description

********* DELETION FUNCTIONS ******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a WorkspaceName

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a WorkspaceName


=end text

=back



=head2 delete_objects_params

=over 4



=item Description

This function deletes an object from a workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: a WorkspacePath
1: an ObjectName

delete_directories has a value which is a bool
force has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: a WorkspacePath
1: an ObjectName

delete_directories has a value which is a bool
force has a value which is a bool


=end text

=back



=head2 delete_workspace_directory_params

=over 4



=item Description

This function creates a new workspace volume - returns metadata of created workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
directory has a value which is a WorkspacePath
force has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
directory has a value which is a WorkspacePath
force has a value which is a bool


=end text

=back



=head2 reset_global_permission_params

=over 4



=item Description

********* FUNCTIONS RELATED TO SHARING *******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a WorkspaceName
global_permission has a value which is a WorkspacePerm

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a WorkspaceName
global_permission has a value which is a WorkspacePerm


=end text

=back



=head2 set_workspace_permissions_params

=over 4



=item Description

This function gives permissions to a workspace to new users (e.g. chmod)


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspace has a value which is a WorkspaceName
permissions has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: a Username
1: a WorkspacePerm


</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspace has a value which is a WorkspaceName
permissions has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: a Username
1: a WorkspacePerm



=end text

=back



=head2 list_workspace_permissions_params

=over 4



=item Description

Provides a list of all users who have access to the workspace


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
workspaces has a value which is a reference to a list where each element is a WorkspaceName

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
workspaces has a value which is a reference to a list where each element is a WorkspaceName


=end text

=back



=cut

1;
