package Bio::P3::Workspace::WorkspaceClient;

use JSON::RPC::Client;
use POSIX;
use strict;
use Data::Dumper;
use URI;
use Bio::KBase::Exceptions;
my $get_time = sub { time, 0 };
eval {
    require Time::HiRes;
    $get_time = sub { Time::HiRes::gettimeofday() };
};

use Bio::KBase::AuthToken;

# Client version should match Impl version
# This is a Semantic Version number,
# http://semver.org
our $VERSION = "0.1.0";

=head1 NAME

Bio::P3::Workspace::WorkspaceClient

=head1 DESCRIPTION





=cut

sub new
{
    my($class, $url, @args) = @_;
    

    my $self = {
	client => Bio::P3::Workspace::WorkspaceClient::RpcClient->new,
	url => $url,
	headers => [],
    };

    chomp($self->{hostname} = `hostname`);
    $self->{hostname} ||= 'unknown-host';

    #
    # Set up for propagating KBRPC_TAG and KBRPC_METADATA environment variables through
    # to invoked services. If these values are not set, we create a new tag
    # and a metadata field with basic information about the invoking script.
    #
    if ($ENV{KBRPC_TAG})
    {
	$self->{kbrpc_tag} = $ENV{KBRPC_TAG};
    }
    else
    {
	my ($t, $us) = &$get_time();
	$us = sprintf("%06d", $us);
	my $ts = strftime("%Y-%m-%dT%H:%M:%S.${us}Z", gmtime $t);
	$self->{kbrpc_tag} = "C:$0:$self->{hostname}:$$:$ts";
    }
    push(@{$self->{headers}}, 'Kbrpc-Tag', $self->{kbrpc_tag});

    if ($ENV{KBRPC_METADATA})
    {
	$self->{kbrpc_metadata} = $ENV{KBRPC_METADATA};
	push(@{$self->{headers}}, 'Kbrpc-Metadata', $self->{kbrpc_metadata});
    }

    if ($ENV{KBRPC_ERROR_DEST})
    {
	$self->{kbrpc_error_dest} = $ENV{KBRPC_ERROR_DEST};
	push(@{$self->{headers}}, 'Kbrpc-Errordest', $self->{kbrpc_error_dest});
    }

    #
    # This module requires authentication.
    #
    # We create an auth token, passing through the arguments that we were (hopefully) given.

    {
	my $token = Bio::KBase::AuthToken->new(@args);
	
	if (!$token->error_message)
	{
	    $self->{token} = $token->token;
	    $self->{client}->{token} = $token->token;
	}
        else
        {
	    #
	    # All methods in this module require authentication. In this case, if we
	    # don't have a token, we can't continue.
	    #
	    die "Authentication failed: " . $token->error_message;
	}
    }

    my $ua = $self->{client}->ua;	 
    my $timeout = $ENV{CDMI_TIMEOUT} || (30 * 60);	 
    $ua->timeout($timeout);
    bless $self, $class;
    #    $self->_validate_version();
    return $self;
}




=head2 create_workspace

  $return = $obj->create_workspace($workspace, $permission, $metadata)

=over 4

=item Parameter and return types

=begin html

<pre>
$workspace is a WorkspaceName
$permission is a WorkspacePerm
$metadata is a UserMetadata
$return is a WorkspaceMeta
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

$workspace is a WorkspaceName
$permission is a WorkspacePerm
$metadata is a UserMetadata
$return is a WorkspaceMeta
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

******** DATA LOAD FUNCTIONS *******************

=back

=cut

sub create_workspace
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 3)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function create_workspace (received $n, expecting 3)");
    }
    {
	my($workspace, $permission, $metadata) = @args;

	my @_bad_arguments;
        (!ref($workspace)) or push(@_bad_arguments, "Invalid type for argument 1 \"workspace\" (value was \"$workspace\")");
        (!ref($permission)) or push(@_bad_arguments, "Invalid type for argument 2 \"permission\" (value was \"$permission\")");
        (ref($metadata) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 3 \"metadata\" (value was \"$metadata\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to create_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'create_workspace');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.create_workspace",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'create_workspace',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method create_workspace",
					    status_line => $self->{client}->status_line,
					    method_name => 'create_workspace',
				       );
    }
}



=head2 save_objects

  $return = $obj->save_objects($objects, $overwrite)

=over 4

=item Parameter and return types

=begin html

<pre>
$objects is a reference to a list where each element is a reference to a list containing 5 items:
	0: a WorkspacePath
	1: an ObjectName
	2: an ObjectData
	3: an ObjectType
	4: a UserMetadata
$overwrite is a bool
$return is a reference to a list where each element is an ObjectMeta
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

$objects is a reference to a list where each element is a reference to a list containing 5 items:
	0: a WorkspacePath
	1: an ObjectName
	2: an ObjectData
	3: an ObjectType
	4: a UserMetadata
$overwrite is a bool
$return is a reference to a list where each element is an ObjectMeta
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

This function receives a list of objects, names, and types and stores the objects in the workspace

=back

=cut

sub save_objects
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 2)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function save_objects (received $n, expecting 2)");
    }
    {
	my($objects, $overwrite) = @args;

	my @_bad_arguments;
        (ref($objects) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument 1 \"objects\" (value was \"$objects\")");
        (!ref($overwrite)) or push(@_bad_arguments, "Invalid type for argument 2 \"overwrite\" (value was \"$overwrite\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to save_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'save_objects');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.save_objects",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'save_objects',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method save_objects",
					    status_line => $self->{client}->status_line,
					    method_name => 'save_objects',
				       );
    }
}



=head2 create_upload_node

  $output = $obj->create_upload_node($objects, $overwrite)

=over 4

=item Parameter and return types

=begin html

<pre>
$objects is a reference to a list where each element is a reference to a list containing 3 items:
	0: a WorkspacePath
	1: an ObjectName
	2: an ObjectType
$overwrite is a bool
$output is a reference to a list where each element is a string
WorkspacePath is a string
ObjectName is a string
ObjectType is a string
bool is an int

</pre>

=end html

=begin text

$objects is a reference to a list where each element is a reference to a list containing 3 items:
	0: a WorkspacePath
	1: an ObjectName
	2: an ObjectType
$overwrite is a bool
$output is a reference to a list where each element is a string
WorkspacePath is a string
ObjectName is a string
ObjectType is a string
bool is an int


=end text

=item Description

This function creates a node in shock that the user can upload to and links this node to a workspace

=back

=cut

sub create_upload_node
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 2)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function create_upload_node (received $n, expecting 2)");
    }
    {
	my($objects, $overwrite) = @args;

	my @_bad_arguments;
        (ref($objects) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument 1 \"objects\" (value was \"$objects\")");
        (!ref($overwrite)) or push(@_bad_arguments, "Invalid type for argument 2 \"overwrite\" (value was \"$overwrite\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to create_upload_node:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'create_upload_node');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.create_upload_node",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'create_upload_node',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method create_upload_node",
					    status_line => $self->{client}->status_line,
					    method_name => 'create_upload_node',
				       );
    }
}



=head2 get_objects

  $output = $obj->get_objects($objects)

=over 4

=item Parameter and return types

=begin html

<pre>
$objects is a reference to a list where each element is a reference to a list containing 2 items:
	0: a WorkspacePath
	1: an ObjectName
$output is a reference to a list where each element is an ObjectDataInfo
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

$objects is a reference to a list where each element is a reference to a list containing 2 items:
	0: a WorkspacePath
	1: an ObjectName
$output is a reference to a list where each element is an ObjectDataInfo
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

******** DATA RETRIEVAL FUNCTIONS *******************

=back

=cut

sub get_objects
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_objects (received $n, expecting 1)");
    }
    {
	my($objects) = @args;

	my @_bad_arguments;
        (ref($objects) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument 1 \"objects\" (value was \"$objects\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get_objects');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.get_objects",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'get_objects',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get_objects",
					    status_line => $self->{client}->status_line,
					    method_name => 'get_objects',
				       );
    }
}



=head2 get_objects_by_reference

  $output = $obj->get_objects_by_reference($objects)

=over 4

=item Parameter and return types

=begin html

<pre>
$objects is a reference to a list where each element is an ObjectID
$output is a reference to a list where each element is an ObjectDataInfo
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

$objects is a reference to a list where each element is an ObjectID
$output is a reference to a list where each element is an ObjectDataInfo
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

This function retrieves a list of objects from the workspace

=back

=cut

sub get_objects_by_reference
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_objects_by_reference (received $n, expecting 1)");
    }
    {
	my($objects) = @args;

	my @_bad_arguments;
        (ref($objects) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument 1 \"objects\" (value was \"$objects\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get_objects_by_reference:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get_objects_by_reference');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.get_objects_by_reference",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'get_objects_by_reference',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get_objects_by_reference",
					    status_line => $self->{client}->status_line,
					    method_name => 'get_objects_by_reference',
				       );
    }
}



=head2 list_workspace_contents

  $output = $obj->list_workspace_contents($directory, $includeSubDirectories, $excludeObjects, $Recursive)

=over 4

=item Parameter and return types

=begin html

<pre>
$directory is a WorkspacePath
$includeSubDirectories is a bool
$excludeObjects is a bool
$Recursive is a bool
$output is a reference to a list where each element is an ObjectMeta
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

$directory is a WorkspacePath
$includeSubDirectories is a bool
$excludeObjects is a bool
$Recursive is a bool
$output is a reference to a list where each element is an ObjectMeta
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

This function lists the contents of the specified workspace (e.g. ls)

=back

=cut

sub list_workspace_contents
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 4)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspace_contents (received $n, expecting 4)");
    }
    {
	my($directory, $includeSubDirectories, $excludeObjects, $Recursive) = @args;

	my @_bad_arguments;
        (!ref($directory)) or push(@_bad_arguments, "Invalid type for argument 1 \"directory\" (value was \"$directory\")");
        (!ref($includeSubDirectories)) or push(@_bad_arguments, "Invalid type for argument 2 \"includeSubDirectories\" (value was \"$includeSubDirectories\")");
        (!ref($excludeObjects)) or push(@_bad_arguments, "Invalid type for argument 3 \"excludeObjects\" (value was \"$excludeObjects\")");
        (!ref($Recursive)) or push(@_bad_arguments, "Invalid type for argument 4 \"Recursive\" (value was \"$Recursive\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to list_workspace_contents:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'list_workspace_contents');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.list_workspace_contents",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'list_workspace_contents',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method list_workspace_contents",
					    status_line => $self->{client}->status_line,
					    method_name => 'list_workspace_contents',
				       );
    }
}



=head2 list_workspace_hierarchical_contents

  $output = $obj->list_workspace_hierarchical_contents($directory, $includeSubDirectories, $excludeObjects, $Recursive)

=over 4

=item Parameter and return types

=begin html

<pre>
$directory is a WorkspacePath
$includeSubDirectories is a bool
$excludeObjects is a bool
$Recursive is a bool
$output is a reference to a hash where the key is a WorkspacePath and the value is a reference to a list where each element is an ObjectMeta
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

$directory is a WorkspacePath
$includeSubDirectories is a bool
$excludeObjects is a bool
$Recursive is a bool
$output is a reference to a hash where the key is a WorkspacePath and the value is a reference to a list where each element is an ObjectMeta
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

This function lists the contents of the specified workspace (e.g. ls)

=back

=cut

sub list_workspace_hierarchical_contents
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 4)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspace_hierarchical_contents (received $n, expecting 4)");
    }
    {
	my($directory, $includeSubDirectories, $excludeObjects, $Recursive) = @args;

	my @_bad_arguments;
        (!ref($directory)) or push(@_bad_arguments, "Invalid type for argument 1 \"directory\" (value was \"$directory\")");
        (!ref($includeSubDirectories)) or push(@_bad_arguments, "Invalid type for argument 2 \"includeSubDirectories\" (value was \"$includeSubDirectories\")");
        (!ref($excludeObjects)) or push(@_bad_arguments, "Invalid type for argument 3 \"excludeObjects\" (value was \"$excludeObjects\")");
        (!ref($Recursive)) or push(@_bad_arguments, "Invalid type for argument 4 \"Recursive\" (value was \"$Recursive\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to list_workspace_hierarchical_contents:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'list_workspace_hierarchical_contents');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.list_workspace_hierarchical_contents",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'list_workspace_hierarchical_contents',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method list_workspace_hierarchical_contents",
					    status_line => $self->{client}->status_line,
					    method_name => 'list_workspace_hierarchical_contents',
				       );
    }
}



=head2 list_workspaces

  $output = $obj->list_workspaces($owned_only, $no_public)

=over 4

=item Parameter and return types

=begin html

<pre>
$owned_only is a bool
$no_public is a bool
$output is a reference to a list where each element is a WorkspaceMeta
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

$owned_only is a bool
$no_public is a bool
$output is a reference to a list where each element is a WorkspaceMeta
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

This function lists all workspace volumes accessible by user

=back

=cut

sub list_workspaces
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 2)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspaces (received $n, expecting 2)");
    }
    {
	my($owned_only, $no_public) = @args;

	my @_bad_arguments;
        (!ref($owned_only)) or push(@_bad_arguments, "Invalid type for argument 1 \"owned_only\" (value was \"$owned_only\")");
        (!ref($no_public)) or push(@_bad_arguments, "Invalid type for argument 2 \"no_public\" (value was \"$no_public\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to list_workspaces:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'list_workspaces');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.list_workspaces",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'list_workspaces',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method list_workspaces",
					    status_line => $self->{client}->status_line,
					    method_name => 'list_workspaces',
				       );
    }
}



=head2 search_for_workspaces

  $output = $obj->search_for_workspaces($query)

=over 4

=item Parameter and return types

=begin html

<pre>
$query is a reference to a hash where the key is a string and the value is a string
$output is a reference to a list where each element is a WorkspaceMeta
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

$query is a reference to a hash where the key is a string and the value is a string
$output is a reference to a list where each element is a WorkspaceMeta
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

Provides a list of all objects in all workspaces whose name or workspace or path match the input query

=back

=cut

sub search_for_workspaces
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function search_for_workspaces (received $n, expecting 1)");
    }
    {
	my($query) = @args;

	my @_bad_arguments;
        (ref($query) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"query\" (value was \"$query\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to search_for_workspaces:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'search_for_workspaces');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.search_for_workspaces",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'search_for_workspaces',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method search_for_workspaces",
					    status_line => $self->{client}->status_line,
					    method_name => 'search_for_workspaces',
				       );
    }
}



=head2 search_for_workspace_objects

  $output = $obj->search_for_workspace_objects($query)

=over 4

=item Parameter and return types

=begin html

<pre>
$query is a reference to a hash where the key is a string and the value is a string
$output is a reference to a list where each element is an ObjectMeta
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

$query is a reference to a hash where the key is a string and the value is a string
$output is a reference to a list where each element is an ObjectMeta
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

Provides a list of all objects in all workspaces whose name or workspace or path match the input query

=back

=cut

sub search_for_workspace_objects
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function search_for_workspace_objects (received $n, expecting 1)");
    }
    {
	my($query) = @args;

	my @_bad_arguments;
        (ref($query) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"query\" (value was \"$query\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to search_for_workspace_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'search_for_workspace_objects');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.search_for_workspace_objects",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'search_for_workspace_objects',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method search_for_workspace_objects",
					    status_line => $self->{client}->status_line,
					    method_name => 'search_for_workspace_objects',
				       );
    }
}



=head2 create_workspace_directory

  $output = $obj->create_workspace_directory($directory, $metadata)

=over 4

=item Parameter and return types

=begin html

<pre>
$directory is a WorkspacePath
$metadata is a UserMetadata
$output is an ObjectMeta
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

$directory is a WorkspacePath
$metadata is a UserMetadata
$output is an ObjectMeta
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

******** REORGANIZATION FUNCTIONS ******************

=back

=cut

sub create_workspace_directory
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 2)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function create_workspace_directory (received $n, expecting 2)");
    }
    {
	my($directory, $metadata) = @args;

	my @_bad_arguments;
        (!ref($directory)) or push(@_bad_arguments, "Invalid type for argument 1 \"directory\" (value was \"$directory\")");
        (ref($metadata) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 2 \"metadata\" (value was \"$metadata\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to create_workspace_directory:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'create_workspace_directory');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.create_workspace_directory",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'create_workspace_directory',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method create_workspace_directory",
					    status_line => $self->{client}->status_line,
					    method_name => 'create_workspace_directory',
				       );
    }
}



=head2 copy_objects

  $output = $obj->copy_objects($objects, $overwrite, $recursive)

=over 4

=item Parameter and return types

=begin html

<pre>
$objects is a reference to a list where each element is a reference to a list containing 4 items:
	0: (source) a WorkspacePath
	1: (origname) an ObjectName
	2: (destination) a WorkspacePath
	3: (newname) an ObjectName
$overwrite is a bool
$recursive is a bool
$output is a reference to a list where each element is an ObjectMeta
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

$objects is a reference to a list where each element is a reference to a list containing 4 items:
	0: (source) a WorkspacePath
	1: (origname) an ObjectName
	2: (destination) a WorkspacePath
	3: (newname) an ObjectName
$overwrite is a bool
$recursive is a bool
$output is a reference to a list where each element is an ObjectMeta
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

This function copies an object to a new workspace

=back

=cut

sub copy_objects
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 3)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function copy_objects (received $n, expecting 3)");
    }
    {
	my($objects, $overwrite, $recursive) = @args;

	my @_bad_arguments;
        (ref($objects) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument 1 \"objects\" (value was \"$objects\")");
        (!ref($overwrite)) or push(@_bad_arguments, "Invalid type for argument 2 \"overwrite\" (value was \"$overwrite\")");
        (!ref($recursive)) or push(@_bad_arguments, "Invalid type for argument 3 \"recursive\" (value was \"$recursive\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to copy_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'copy_objects');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.copy_objects",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'copy_objects',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method copy_objects",
					    status_line => $self->{client}->status_line,
					    method_name => 'copy_objects',
				       );
    }
}



=head2 move_objects

  $output = $obj->move_objects($objects, $overwrite, $recursive)

=over 4

=item Parameter and return types

=begin html

<pre>
$objects is a reference to a list where each element is a reference to a list containing 4 items:
	0: (source) a WorkspacePath
	1: (origname) an ObjectName
	2: (destination) a WorkspacePath
	3: (newname) an ObjectName
$overwrite is a bool
$recursive is a bool
$output is a reference to a list where each element is an ObjectMeta
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

$objects is a reference to a list where each element is a reference to a list containing 4 items:
	0: (source) a WorkspacePath
	1: (origname) an ObjectName
	2: (destination) a WorkspacePath
	3: (newname) an ObjectName
$overwrite is a bool
$recursive is a bool
$output is a reference to a list where each element is an ObjectMeta
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

This function copies an object to a new workspace

=back

=cut

sub move_objects
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 3)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function move_objects (received $n, expecting 3)");
    }
    {
	my($objects, $overwrite, $recursive) = @args;

	my @_bad_arguments;
        (ref($objects) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument 1 \"objects\" (value was \"$objects\")");
        (!ref($overwrite)) or push(@_bad_arguments, "Invalid type for argument 2 \"overwrite\" (value was \"$overwrite\")");
        (!ref($recursive)) or push(@_bad_arguments, "Invalid type for argument 3 \"recursive\" (value was \"$recursive\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to move_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'move_objects');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.move_objects",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'move_objects',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method move_objects",
					    status_line => $self->{client}->status_line,
					    method_name => 'move_objects',
				       );
    }
}



=head2 delete_workspace

  $output = $obj->delete_workspace($workspace)

=over 4

=item Parameter and return types

=begin html

<pre>
$workspace is a WorkspaceName
$output is a WorkspaceMeta
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

$workspace is a WorkspaceName
$output is a WorkspaceMeta
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

******** DELETION FUNCTIONS ******************

=back

=cut

sub delete_workspace
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete_workspace (received $n, expecting 1)");
    }
    {
	my($workspace) = @args;

	my @_bad_arguments;
        (!ref($workspace)) or push(@_bad_arguments, "Invalid type for argument 1 \"workspace\" (value was \"$workspace\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to delete_workspace:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'delete_workspace');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.delete_workspace",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'delete_workspace',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method delete_workspace",
					    status_line => $self->{client}->status_line,
					    method_name => 'delete_workspace',
				       );
    }
}



=head2 delete_objects

  $output = $obj->delete_objects($objects, $delete_directories, $force)

=over 4

=item Parameter and return types

=begin html

<pre>
$objects is a reference to a list where each element is a reference to a list containing 2 items:
	0: a WorkspacePath
	1: an ObjectName
$delete_directories is a bool
$force is a bool
$output is a reference to a list where each element is an ObjectMeta
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

$objects is a reference to a list where each element is a reference to a list containing 2 items:
	0: a WorkspacePath
	1: an ObjectName
$delete_directories is a bool
$force is a bool
$output is a reference to a list where each element is an ObjectMeta
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

This function deletes an object from a workspace

=back

=cut

sub delete_objects
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 3)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete_objects (received $n, expecting 3)");
    }
    {
	my($objects, $delete_directories, $force) = @args;

	my @_bad_arguments;
        (ref($objects) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument 1 \"objects\" (value was \"$objects\")");
        (!ref($delete_directories)) or push(@_bad_arguments, "Invalid type for argument 2 \"delete_directories\" (value was \"$delete_directories\")");
        (!ref($force)) or push(@_bad_arguments, "Invalid type for argument 3 \"force\" (value was \"$force\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to delete_objects:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'delete_objects');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.delete_objects",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'delete_objects',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method delete_objects",
					    status_line => $self->{client}->status_line,
					    method_name => 'delete_objects',
				       );
    }
}



=head2 delete_workspace_directory

  $output = $obj->delete_workspace_directory($directory, $force)

=over 4

=item Parameter and return types

=begin html

<pre>
$directory is a WorkspacePath
$force is a bool
$output is an ObjectMeta
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

$directory is a WorkspacePath
$force is a bool
$output is an ObjectMeta
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

This function creates a new workspace volume - returns metadata of created workspace

=back

=cut

sub delete_workspace_directory
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 2)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete_workspace_directory (received $n, expecting 2)");
    }
    {
	my($directory, $force) = @args;

	my @_bad_arguments;
        (!ref($directory)) or push(@_bad_arguments, "Invalid type for argument 1 \"directory\" (value was \"$directory\")");
        (!ref($force)) or push(@_bad_arguments, "Invalid type for argument 2 \"force\" (value was \"$force\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to delete_workspace_directory:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'delete_workspace_directory');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.delete_workspace_directory",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'delete_workspace_directory',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method delete_workspace_directory",
					    status_line => $self->{client}->status_line,
					    method_name => 'delete_workspace_directory',
				       );
    }
}



=head2 reset_global_permission

  $output = $obj->reset_global_permission($workspace, $global_permission)

=over 4

=item Parameter and return types

=begin html

<pre>
$workspace is a WorkspaceName
$global_permission is a WorkspacePerm
$output is a WorkspaceMeta
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

$workspace is a WorkspaceName
$global_permission is a WorkspacePerm
$output is a WorkspaceMeta
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

******** FUNCTIONS RELATED TO SHARING *******************

=back

=cut

sub reset_global_permission
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 2)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function reset_global_permission (received $n, expecting 2)");
    }
    {
	my($workspace, $global_permission) = @args;

	my @_bad_arguments;
        (!ref($workspace)) or push(@_bad_arguments, "Invalid type for argument 1 \"workspace\" (value was \"$workspace\")");
        (!ref($global_permission)) or push(@_bad_arguments, "Invalid type for argument 2 \"global_permission\" (value was \"$global_permission\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to reset_global_permission:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'reset_global_permission');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.reset_global_permission",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'reset_global_permission',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method reset_global_permission",
					    status_line => $self->{client}->status_line,
					    method_name => 'reset_global_permission',
				       );
    }
}



=head2 set_workspace_permissions

  $output = $obj->set_workspace_permissions($workspace, $permissions)

=over 4

=item Parameter and return types

=begin html

<pre>
$workspace is a WorkspaceName
$permissions is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm
$output is a WorkspaceMeta
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

$workspace is a WorkspaceName
$permissions is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm
$output is a WorkspaceMeta
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

This function gives permissions to a workspace to new users (e.g. chmod)

=back

=cut

sub set_workspace_permissions
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 2)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function set_workspace_permissions (received $n, expecting 2)");
    }
    {
	my($workspace, $permissions) = @args;

	my @_bad_arguments;
        (!ref($workspace)) or push(@_bad_arguments, "Invalid type for argument 1 \"workspace\" (value was \"$workspace\")");
        (ref($permissions) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument 2 \"permissions\" (value was \"$permissions\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to set_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'set_workspace_permissions');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.set_workspace_permissions",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'set_workspace_permissions',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method set_workspace_permissions",
					    status_line => $self->{client}->status_line,
					    method_name => 'set_workspace_permissions',
				       );
    }
}



=head2 list_workspace_permissions

  $output = $obj->list_workspace_permissions($workspaces)

=over 4

=item Parameter and return types

=begin html

<pre>
$workspaces is a reference to a list where each element is a WorkspaceName
$output is a reference to a hash where the key is a string and the value is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm
WorkspaceName is a string
Username is a string
WorkspacePerm is a string

</pre>

=end html

=begin text

$workspaces is a reference to a list where each element is a WorkspaceName
$output is a reference to a hash where the key is a string and the value is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm
WorkspaceName is a string
Username is a string
WorkspacePerm is a string


=end text

=item Description

Provides a list of all users who have access to the workspace

=back

=cut

sub list_workspace_permissions
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspace_permissions (received $n, expecting 1)");
    }
    {
	my($workspaces) = @args;

	my @_bad_arguments;
        (ref($workspaces) eq 'ARRAY') or push(@_bad_arguments, "Invalid type for argument 1 \"workspaces\" (value was \"$workspaces\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to list_workspace_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'list_workspace_permissions');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.list_workspace_permissions",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'list_workspace_permissions',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method list_workspace_permissions",
					    status_line => $self->{client}->status_line,
					    method_name => 'list_workspace_permissions',
				       );
    }
}



sub version {
    my ($self) = @_;
    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
        method => "Workspace.version",
        params => [],
    });
    if ($result) {
        if ($result->is_error) {
            Bio::KBase::Exceptions::JSONRPC->throw(
                error => $result->error_message,
                code => $result->content->{code},
                method_name => 'list_workspace_permissions',
            );
        } else {
            return wantarray ? @{$result->result} : $result->result->[0];
        }
    } else {
        Bio::KBase::Exceptions::HTTP->throw(
            error => "Error invoking method list_workspace_permissions",
            status_line => $self->{client}->status_line,
            method_name => 'list_workspace_permissions',
        );
    }
}

sub _validate_version {
    my ($self) = @_;
    my $svr_version = $self->version();
    my $client_version = $VERSION;
    my ($cMajor, $cMinor) = split(/\./, $client_version);
    my ($sMajor, $sMinor) = split(/\./, $svr_version);
    if ($sMajor != $cMajor) {
        Bio::KBase::Exceptions::ClientServerIncompatible->throw(
            error => "Major version numbers differ.",
            server_version => $svr_version,
            client_version => $client_version
        );
    }
    if ($sMinor < $cMinor) {
        Bio::KBase::Exceptions::ClientServerIncompatible->throw(
            error => "Client minor version greater than Server minor version.",
            server_version => $svr_version,
            client_version => $client_version
        );
    }
    if ($sMinor > $cMinor) {
        warn "New client version available for Bio::P3::Workspace::WorkspaceClient\n";
    }
    if ($sMajor == 0) {
        warn "Bio::P3::Workspace::WorkspaceClient version is $svr_version. API subject to change.\n";
    }
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



=cut

package Bio::P3::Workspace::WorkspaceClient::RpcClient;
use base 'JSON::RPC::Client';
use POSIX;
use strict;

#
# Override JSON::RPC::Client::call because it doesn't handle error returns properly.
#

sub call {
    my ($self, $uri, $headers, $obj) = @_;
    my $result;


    {
	if ($uri =~ /\?/) {
	    $result = $self->_get($uri);
	}
	else {
	    Carp::croak "not hashref." unless (ref $obj eq 'HASH');
	    $result = $self->_post($uri, $headers, $obj);
	}

    }

    my $service = $obj->{method} =~ /^system\./ if ( $obj );

    $self->status_line($result->status_line);

    if ($result->is_success) {

        return unless($result->content); # notification?

        if ($service) {
            return JSON::RPC::ServiceObject->new($result, $self->json);
        }

        return JSON::RPC::ReturnObject->new($result, $self->json);
    }
    elsif ($result->content_type eq 'application/json')
    {
        return JSON::RPC::ReturnObject->new($result, $self->json);
    }
    else {
        return;
    }
}


sub _post {
    my ($self, $uri, $headers, $obj) = @_;
    my $json = $self->json;

    $obj->{version} ||= $self->{version} || '1.1';

    if ($obj->{version} eq '1.0') {
        delete $obj->{version};
        if (exists $obj->{id}) {
            $self->id($obj->{id}) if ($obj->{id}); # if undef, it is notification.
        }
        else {
            $obj->{id} = $self->id || ($self->id('JSON::RPC::Client'));
        }
    }
    else {
        # $obj->{id} = $self->id if (defined $self->id);
	# Assign a random number to the id if one hasn't been set
	$obj->{id} = (defined $self->id) ? $self->id : substr(rand(),2);
    }

    my $content = $json->encode($obj);

    $self->ua->post(
        $uri,
        Content_Type   => $self->{content_type},
        Content        => $content,
        Accept         => 'application/json',
	@$headers,
	($self->{token} ? (Authorization => $self->{token}) : ()),
    );
}



1;
