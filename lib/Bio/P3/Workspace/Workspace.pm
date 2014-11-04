package Bio::KBase::workspaceService::Workspace;
use strict;
use Bio::KBase::Exceptions;
use Data::UUID;
use Data::Dumper;

our $VERSION = "0";

=head1 NAME

Workspace

=head1 DESCRIPTION

=head1 Workspace

API for manipulating workspaces

=cut

=head3 new

Definition:
	Workspace = Bio::KBase::workspaceService::Workspace->new({}:workspace data);
Description:
	Returns a Workspace object

=cut

sub new {
	my ($class,$args) = @_;
	$args = Bio::KBase::workspaceService::Impl::_args([
		"parent",
		"id",
		"owner",
		"moddate",
		"defaultPermissions",
		"objects"
	],{},$args);
	my $self = {
		_id => $args->{id},
		_parent => $args->{parent},
		_owner => $args->{owner},
		_moddate => $args->{moddate},
		_defaultPermissions => $args->{defaultPermissions},
		_objects => {}
	};
	foreach my $safeid (keys(%{$args->{objects}})) {
		my $realid = $safeid;
		$realid =~ s/_DOT_/./g;
		$self->{_objects}->{$realid} = $args->{objects}->{$safeid};
	}
	bless $self;
	$self->_validateID($args->{id});
	$self->_validatePermission($args->{defaultPermissions}, 1);
	return $self;
}

=head3 id

Definition:
	string = id()
Description:
	Returns the id for the workspace

=cut

sub id {
	my ($self) = @_;
	return $self->{_id};
}

=head3 parent

Definition:
	string = parent()
Description:
	Returns the parent workspace implementation

=cut

sub parent {
	my ($self) = @_;
	return $self->{_parent};
}

=head3 owner

Definition:
	string = owner()
Description:
	Returns the owner for the workspace

=cut

sub owner {
	my ($self) = @_;
	return $self->{_owner};
}

=head3 moddate

Definition:
	string = moddate()
Description:
	Returns the moddate for the workspace

=cut

sub moddate {
	my ($self) = @_;
	return $self->{_moddate};
}

=head3 defaultPermissions

Definition:
	string = defaultPermissions()
Description:
	Returns the defaultPermissions for the workspace

=cut

sub defaultPermissions {
	my ($self) = @_;
	return $self->{_defaultPermissions};
}

=head3 isWorldReadable

Definition:
	boolean = isWorldReadable()
Description:
	Returns true if the workspace is world readable.

=cut

sub isWorldReadable {
	my ($self) = @_;
	return $self->{_defaultPermissions} eq 'r';
}

=head3 objects

Definition:
	{} = objects();
Description:
	Returns the workspace objects hash

=cut

sub objects {
	my ($self,$type,$alias) = @_;
	return $self->{_objects};
}

=head3 metadata

Definition:
	{} = metadata();
Description:
	Returns the metadata object for workspace

=cut

sub metadata {
	my ($self,$ashash) = @_;
	$self->checkPermissions(['r', 'w', 'a']);
	my $objects += keys(%{$self->objects()});
#	foreach my $key (keys(%{$self->objects()})) {
#		$objects += keys(%{$self->objects()->{$key}});
#	}
	if (defined($ashash) && $ashash == 1) {
		return {
			id => $self->id(),
			owner => $self->owner(),
			moddate => $self->moddate(),
			objects => $objects,
			user_permission => $self->currentPermission(),
			global_permission => $self->defaultPermissions()
		};
	}
	return [
		$self->id(),
		$self->owner(),
		$self->moddate(),
		$objects,
		$self->currentPermission(),
		$self->defaultPermissions()
	];
}

=head3 currentPermission

Definition:
	string = currentPermission()
Description:
	Returns the current permissions for access to this workspace

=cut

sub currentPermission {
	my ($self) = @_;
	if (!defined($self->{_currentPermission})) {
		my $userObj = $self->parent()->_getCurrentUserObj();
		if (!defined($userObj)) {
			$self->{_currentPermission} = $self->defaultPermissions();
		} elsif ($userObj->id() eq $self->owner()) {
			$self->{_currentPermission} = "a";
		} elsif ($userObj->id() eq "workspaceroot") {
			$self->{_currentPermission} = "a";
		} else {
			$self->{_currentPermission} = $userObj->getWorkspacePermission($self);
		}
	}
	return $self->{_currentPermission};
}

=head3 currentUser

Definition:
	string = currentUser()
Description:
	Returns the current user accessing this workspace

=cut

sub currentUser {
	my ($self) = @_;
	return $self->parent()->_getUsername();
}

=head3 setDefaultPermissions

Definition:
	void setDefaultPermissions(string:permission)
Description:
	Alters the default permissions for workspace

=cut

sub setDefaultPermissions {
	my ($self,$perm) = @_;
	$self->_validatePermission($perm, 1);
	$self->checkPermissions(["a"]);
	$self->{_defaultPermissions} = $perm;
	$self->parent()->_updateDB("workspaces",{id => $self->id()},{'$set' => {'defaultPermissions' => $perm}});
}

=head3 getObject

Definition:
	Bio::KBase::workspaceService::Object = getObject(string:type,string:alias)
Description:
	Returns a Workspace object

=cut

sub getObject {
	my ($self,$type,$id,$options) = @_;
	$self->checkPermissions(["r","w","a"]);
	my $objects = $self->objects();
	if (!defined($objects->{$id})) {
		if (defined($options->{throwErrorIfMissing}) && $options->{throwErrorIfMissing} == 1) {
			Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Specified object not found in the workspace!",
									method_name => 'getObject');
		}
		return undef;
	}
	my $obj;
	if (defined($options->{instance})) {
		$obj = $self->parent()->_getObjectByID($id,$type,$self->id(),$options->{instance});
	} else {
		my $uuid = $objects->{$id};
		$obj = $self->parent()->_getObject($uuid);
	}
	if (!defined($obj) && defined($options->{throwErrorIfMissing}) && $options->{throwErrorIfMissing} == 1) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object ".$self->id()."/".$type."/".$id." not found in database!",
									method_name => 'getObject');
	}
	return $obj;
}

=head3 getObjects

Definition:
	Bio::KBase::workspaceService::Object = getObjects([string]:types,[string]:aliases,[int]:instances)
Description:
	Returns Workspace objects

=cut

sub getObjects {
	my ($self,$types,$ids,$instances,$options) = @_;
	$self->checkPermissions(["r","w","a"]);
	my $objects = $self->objects();
	my $output = [];
	my $uuidRef = {};
	my $inst = {ids => [],types => [],instances => [],wss => [],indecies => {}};
	for (my $i=0; $i < @{$types}; $i++) {
		if (!defined($objects->{$ids->[$i]})) {
			if (defined($options->{throwErrorIfMissing}) && $options->{throwErrorIfMissing} == 1) {
				Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Specified object ".$self->id()."/".$ids->[$i]." not found in the workspace!",
								       method_name => 'getObject');
			}
			$output->[$i] = undef;
		} elsif (defined($instances->[$i])) {
			push(@{$inst->{ids}},$ids->[$i]);
			push(@{$inst->{types}},$types->[$i]);
			push(@{$inst->{instances}},$instances->[$i]);
			push(@{$inst->{wss}},$self->id());
			$inst->{indecies}->{$ids->[$i]}->{$types->[$i]}->{$instances->[$i]} = $i;
		} else {
			$uuidRef->{$objects->{$ids->[$i]}} = $i;
		}
	}
	if (keys(%{$uuidRef}) > 0) {
		my $objs = $self->parent()->_getObjects([keys(%{$uuidRef})],$options);
		for (my $i=0; $i < @{$objs}; $i++) {
			$output->[$uuidRef->{$objs->[$i]->uuid()}] = $objs->[$i];
		}	
	}
	if (@{$inst->{ids}} > 0) {
		my $objs = $self->parent()->_getObjectsByID($inst->{ids},$inst->{types},$inst->{wss},$inst->{instances},$options);
		for (my $i=0; $i < @{$objs}; $i++) {
			$output->[$inst->{indecies}->{$inst->{ids}->[$i]}->{$inst->{instances}->[$i]}] = $objs->[$i];
		}
	}
	return $output;
}

=head3 getObjectHistory

Definition:
	Bio::KBase::workspaceService::Object = getObjectHistory(string:type,string:alias)
Description:
	Returns an array with complete object history

=cut

sub getObjectHistory {
	my ($self,$type,$id) = @_;
	$self->checkPermissions(["r","w","a"]);
	my $objects = $self->objects();
	if (!defined($objects->{$id})) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Specified object not found in the workspace!",
		method_name => 'getObject');
	}
	return $self->parent()->_getObjectsByID($id,$type,$self->id());
}

=head3 getAllObjects

Definition:
	Bio::KBase::workspaceService::Object = getAllObjects(string:type)
Description:
	Returns all workspace objects of the specified type

=cut

sub getAllObjects {
	my ($self,$type,$options) = @_;
	if($type) {
		$options->{type} = $type;
	}
	$self->checkPermissions(["r","w","a"]);
	my $uuids = [];
	my $objects = $self->objects();
#	if (!defined($type)) {
#		foreach my $type (keys(%{$objects})) {
			foreach my $alias (keys(%{$objects})) {
				push(@{$uuids},$objects->{$alias});
			}
#		}
#	} else {
#		foreach my $alias (keys(%{$objects->{$type}})) {
#			push(@{$uuids},$objects->{$type}->{$alias});	
#		}
#	}
	return $self->parent()->_getObjects($uuids,$options); 
}

=head3 saveObject

Definition:
	Bio::KBase::workspaceService::Object = saveObject(string:type)
Description:
	Returns saved object.

=cut

sub saveObject {
	my ($self,$type,$id,$data,$command,$meta) = @_;
	$self->checkPermissions(["w","a"]);
	$self->_validateType($type);
	my $continue = 1;
	my ($ancestor,$instance,$owner);
	my $uuid = Data::UUID->new()->create_str();
	my $olduuid = undef;
	while($continue == 1) {
		$ancestor = undef;
		$instance = 0;
		$owner = $self->currentUser();
		my $obj = $self->getObject($type,$id);
		$olduuid = undef;
		if (defined($obj)) {
			if (!defined($meta)) {
				$meta = $obj->meta();
			}
			$ancestor = $obj->uuid();
			$owner = $obj->owner();
			$instance = ($obj->instance()+1);
			$olduuid = $obj->uuid();
		}
		if ($self->_updateObjects($type,$id,$uuid,$olduuid) == 1) {
			$continue = 0;
		};
	}
	my $newObject;
	eval {
		$newObject = $self->parent()->_createObject({
			uuid => $uuid,
			type => $type,
			workspace => $self->id(),
			parent => $self->parent(),
			ancestor => $ancestor,
			owner => $owner,
			lastModifiedBy => $self->currentUser(),
			command => $command,
			id => $id,
			instance => $instance,
			rawdata => $data,
			meta => $meta
		});
	};
	if ($@ || !defined($newObject)) {
		my $errmsg = $@;
		#Deleting the object to prevent the database from getting into a bad state
		$self->_updateObjects($type,$id,$olduuid,$uuid);
		my $msg = "Save failed for ".$self->id()."/".$type."/".$id."!\n";
		$msg .= $errmsg;
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'saveObject');
	}
	return $newObject;
}

=head3 revertObject

Definition:
	Bio::KBase::workspaceService::Object = revertObject(string:type)
Description:
	Returns previous object in object history

=cut

sub revertObject {
	my ($self,$type,$id,$instance) = @_;
	$self->checkPermissions(["w","a"]);
	my $origObj = $self->getObject($type,$id,{throwErrorIfMissing => 1});
	if (!defined($origObj)) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object not found!",
		method_name => 'revertObject');
	}
	my $currInst = $origObj->instance();
	my $count = $currInst-$instance;
	my $obj;
	if (defined($instance)) {
		$obj = $origObj;
		if ($count == 0) {
			return $origObj;
		} elsif ($count < 0) {
			my $msg = "Input instance not valid!";
			Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,method_name => 'revertObject');
		} else {
			$obj = $self->parent()->_getObjectByID($id,$type,$self->id(),$instance,{throwErrorIfMissing => 1});
			#for (my $i=0; $i < $count; $i++) {
			#	$obj = $self->parent()->_getObject($obj->ancestor(),{throwErrorIfMissing => 1});
			#}
		}
	} else {
		$obj = $self->parent()->_getObject($origObj->ancestor(),{throwErrorIfMissing => 1});
	} 
	if (!defined($obj)) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Ancestor object not found!",
		method_name => 'revertObject');
	}
	my $uuid = Data::UUID->new()->create_str();
	if ($self->_updateObjects($type,$id,$uuid,$origObj->uuid()) == 0) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "State of object was altered during revert process. Revert aborted!",
			method_name => 'revertObject');
	}
	my $newObject;
	eval {
		$newObject = $self->parent()->_createObject({
			uuid => $uuid,
			type => $type,
			workspace => $self->id(),
			parent => $self->parent(),
			ancestor => $obj->ancestor(),
			owner => $obj->owner(),
			lastModifiedBy => $self->currentUser(),
			command => "revert:".$currInst.":".$obj->instance(),
			id => $id,
			instance => ($currInst+1),
			chsum => $obj->chsum(),
			meta => $obj->meta()
		});
	};
	if (!defined($newObject)) {
		#Restoring the old object if the object generation failed
		$self->_updateObjects($type,$id,$origObj->uuid(),$uuid);
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Revert failed for ".$self->id()."/".$type."/".$id."!",method_name => 'revertObject');
	}
	return $newObject;
}

=head3 deleteObject

Definition:
	Bio::KBase::workspaceService::Object = deleteObject(string:type,string:id)
Description:
	Deletes the specified object from the workspacee, leaving a stub that can be reverted.

=cut

sub deleteObject {
	my ($self,$type,$id) = @_;
	$self->checkPermissions(["w","a"]);
	my $obj = $self->getObject($type,$id,{throwErrorIfMissing => 1});
	if ($obj->command() eq "delete") {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object already in a deleted state!",
			method_name => 'deleteObject');
	}
	my $uuid = Data::UUID->new()->create_str();
	if ($self->_updateObjects($type,$id,$uuid,$obj->uuid()) == 0) {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "State of object was altered during delete process. Delete aborted!",
			method_name => 'deleteObject');
	}
	my $newObject;
	eval {
		$newObject = $self->parent()->_createObject({
			uuid => $uuid,
			type => $type,
			workspace => $self->id(),
			parent => $self->parent(),
			ancestor => $obj->uuid(),
			owner => $obj->owner(),
			lastModifiedBy => $self->currentUser(),
			command => "delete",
			id => $id,
			instance => ($obj->instance()+1),
			chsum => $obj->chsum(),
			meta => $obj->meta()
		});
	};
	if (!defined($newObject)) {
		#Restoring the old object if the object generation failed
		$self->_updateObjects($type,$id,$obj->uuid(),$uuid);
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Delete failed for ".$self->id()."/".$type."/".$id."!",method_name => 'deleteObject');
	}
	return $newObject;
}

=head3 deleteObjectPermanently

Definition:
	Bio::KBase::workspaceService::Object = deleteObject(string:type,string:id)
Description:
	Deletes the specified object from the workspacee and database permanently and irreversibly.
	The object must already be in a "deleted" state in the workspace.

=cut

sub deleteObjectPermanently {
	my ($self,$type,$id) = @_;
	$self->checkPermissions(["a"]);
	my $obj = $self->getObject($type,$id);
	if (defined($obj)) {
		if ($obj->command() ne "delete") {
			Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Object must be in a deleted state before it can be permanently deleted!",
										method_name => 'deleteObjectPermanently');
		}
		if ($self->_updateObjects($type,$id,undef,$obj->uuid()) == 0) {
			Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "State of object was altered during delete process. Delete aborted!",
										method_name => 'deleteObjectPermanently');	
		}
		$obj->permanentDelete();
	} elsif (defined($self->objects()->{$type}->{$id})) {
		if ($self->_updateObjects($type,$id,undef,$self->objects()->{$type}->{$id}) == 0) {
			Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "State of object was altered during delete process. Delete aborted!",
										method_name => 'deleteObjectPermanently');	
		}
	}
	return $obj;
}

=head3 setUserPermissions

Definition:
	void setUserPermissions([string]:usernames,string:permission)
Description:
	Sets user permissions

=cut

sub setUserPermissions {
	my ($self,$users,$perm) = @_;
	$self->_validatePermission($perm);
	$self->checkPermissions(["a"]);
	my $userObjects = $self->parent()->_getWorkspaceUsers($users,{
		throwErrorIfMissing => 0,
		createIfMissing => 1
	});
	foreach my $u (@{$userObjects}) {
		if($self->currentUser() eq $self->owner() ||
			$u->id() ne $self->owner()) {
			$u->setWorkspacePermission($self->id(), $perm);
		}
	}
}

=head3 getWorkspaceUserPermissions

Definition:
	{string:username => string:permission} getWorkspaceUserPermissions()
Description:
	Returns a hash of all set user permissions for a workspace

=cut

sub getWorkspaceUserPermissions {
	my ($self) = @_;
	$self->checkPermissions(["r","w","a"]);
	my $output = {"~global" => $self->defaultPermissions()};
	my $wsus = $self->parent()->_getAllWorkspaceUsersByWorkspace($self->id());
	for (my $i=0; $i < @{$wsus}; $i++) {
		$output->{$wsus->[$i]->id()} = $wsus->[$i]->workspaces()->{$self->id()};
	}
	if($self->currentPermission() ne 'a') {
		my $cu = $self->currentUser();
		if(!defined $output->{$cu}) {
			return {$cu => 'n'};
		}
		return {$cu => $output->{$cu}};
	}
	return $output;
}

=head3 permanentDelete

Definition:
	void permanentDelete()
Description:
	Permanently deletes workspace and all objects in it (DANGEROUS TO CALL!!!!)

=cut

sub permanentDelete {
	my ($self) = @_;
	if ($self->currentUser() ne $self->owner() && $self->currentUser() ne "workspaceroot") {
		Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "Only workspace owner can delete workspace!",
									method_name => 'permanentDelete');
	}
	my $objs = $self->getAllObjects();
	for (my $i=0; $i < @{$objs}; $i++) {
		$objs->[$i]->permanentDelete();
	}
	my $wsus = $self->parent()->_getAllWorkspaceUsersByWorkspace($self->id());
	$self->parent()->_deleteWorkspace($self->id());
	for (my $i=0; $i < @{$wsus}; $i++) {
		$wsus->[$i]->setWorkspacePermission($self->id(),"n");
	}
}

=head3 checkPermissions

Definition:
	void checkPermissions(string:required permissions)
Description:
	Throws an exception if the user does not have needed permissions for the workspace
	
=cut

sub checkPermissions {
	my ($self,$perms) = @_;
	my $currperm = $self->currentPermission();
	for (my $i=0; $i < @{$perms}; $i++) {
		if ($currperm eq $perms->[$i]) {
			return;
		}
	}
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error => "User lacks permissions for the specified activity!",method_name => 'checkPermissions');
}

=head3 _updateObjects

Definition:
	bool _updateObjects(string:type,string:id,string:uuid,string:olduuid)
Description:
	Updates object uuid in the database if the old uuid still retains the specified value. Otherwise, nothing is done.
	Returns "1" if successful, "0" otherwise.
	This avoid race conditions. You must check if the return is "1"; if not, then the update failed.
=cut

sub _updateObjects {
	my ($self,$type,$id,$uuid,$olduuid) = @_;
	my $result;
	my $saveid = $id;
	$saveid =~ s/\./_DOT_/g;
	if (!defined($uuid)) {
		if ($self->parent()->_updateDB("workspaces",{id => $self->id(),'objects.'.$saveid => $olduuid},{'$unset' => {'objects.'.$saveid => $olduuid}}) == 0) {
			return 0;
		}
		delete $self->objects()->{$id};
	} else {
		if ($self->parent()->_updateDB("workspaces",{id => $self->id(),'objects.'.$saveid => $olduuid},{'$set' => {'objects.'.$saveid => $uuid}}) == 0) {
			return 0;
		}
		$self->objects()->{$id} = $uuid;
	}
	return 1;
}

sub _validateID {
	my ($self,$id) = @_;
	$self->parent()->_validateWorkspaceID($id);
}

sub _validatePermission {
	my ($self,$permission, $default) = @_;
	$self->parent()->_validatePermission($permission, $default);
}

sub _validateType {
	my ($self,$type) = @_;
	$self->parent()->_validateObjectType($type);
}

1;
