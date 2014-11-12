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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function create_workspace (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function save_objects (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function create_upload_node (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_objects (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_objects_by_reference (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspace_contents (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspace_hierarchical_contents (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspaces (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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

  $output = $obj->search_for_workspaces($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a search_for_workspaces_params
$output is a reference to a list where each element is a WorkspaceMeta
search_for_workspaces_params is a reference to a hash where the following keys are defined:
	query has a value which is a reference to a hash where the key is a string and the value is a string
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
	query has a value which is a reference to a hash where the key is a string and the value is a string
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function search_for_workspaces (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function search_for_workspace_objects (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function create_workspace_directory (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function copy_objects (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function move_objects (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete_workspace (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete_objects (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete_workspace_directory (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function reset_global_permission (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function set_workspace_permissions (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_workspace_permissions (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
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
query has a value which is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
query has a value which is a reference to a hash where the key is a string and the value is a string


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
