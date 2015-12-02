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
    
    if (!defined($url))
    {
	$url = 'http://p3.theseed.org/services/Workspace';
    }

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

    #{
	#my $token = Bio::KBase::AuthToken->new(@args);
	
	#if (!$token->error_message)
	#{
	#    $self->{token} = $token->token;
	#    $self->{client}->{token} = $token->token;
	#}
    #}
    $self->{token} = $args[1];
	$self->{client}->{token} = $args[1];

    my $ua = $self->{client}->ua;	 
    my $timeout = $ENV{CDMI_TIMEOUT} || (30 * 60);	 
    $ua->timeout($timeout);
    bless $self, $class;
    #    $self->_validate_version();
    return $self;
}




=head2 create

  $output = $obj->create($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a create_params
$output is a reference to a list where each element is an ObjectMeta
create_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 5 items:
	0: a FullObjectPath
	1: an ObjectType
	2: a UserMetadata
	3: an ObjectData
	4: (creation_time) a Timestamp

	permission has a value which is a WorkspacePerm
	createUploadNodes has a value which is a bool
	downloadLinks has a value which is a bool
	overwrite has a value which is a bool
	adminmode has a value which is a bool
	setowner has a value which is a string
FullObjectPath is a string
ObjectType is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
ObjectData is a string
Timestamp is a string
WorkspacePerm is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectID is a string
Username is a string
ObjectSize is an int
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a create_params
$output is a reference to a list where each element is an ObjectMeta
create_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 5 items:
	0: a FullObjectPath
	1: an ObjectType
	2: a UserMetadata
	3: an ObjectData
	4: (creation_time) a Timestamp

	permission has a value which is a WorkspacePerm
	createUploadNodes has a value which is a bool
	downloadLinks has a value which is a bool
	overwrite has a value which is a bool
	adminmode has a value which is a bool
	setowner has a value which is a string
FullObjectPath is a string
ObjectType is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
ObjectData is a string
Timestamp is a string
WorkspacePerm is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectID is a string
Username is a string
ObjectSize is an int
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text

=item Description



=back

=cut

sub create
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function create (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to create:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'create');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.create",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'create',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method create",
					    status_line => $self->{client}->status_line,
					    method_name => 'create',
				       );
    }
}



=head2 update_metadata

  $output = $obj->update_metadata($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is an update_metadata_params
$output is a reference to a list where each element is an ObjectMeta
update_metadata_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
	0: a FullObjectPath
	1: a UserMetadata
	2: an ObjectType
	3: (creation_time) a Timestamp

	autometadata has a value which is a bool
	adminmode has a value which is a bool
FullObjectPath is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
ObjectType is a string
Timestamp is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectID is a string
Username is a string
ObjectSize is an int
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string

</pre>

=end html

=begin text

$input is an update_metadata_params
$output is a reference to a list where each element is an ObjectMeta
update_metadata_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
	0: a FullObjectPath
	1: a UserMetadata
	2: an ObjectType
	3: (creation_time) a Timestamp

	autometadata has a value which is a bool
	adminmode has a value which is a bool
FullObjectPath is a string
UserMetadata is a reference to a hash where the key is a string and the value is a string
ObjectType is a string
Timestamp is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectID is a string
Username is a string
ObjectSize is an int
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string


=end text

=item Description



=back

=cut

sub update_metadata
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function update_metadata (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to update_metadata:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'update_metadata');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.update_metadata",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'update_metadata',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method update_metadata",
					    status_line => $self->{client}->status_line,
					    method_name => 'update_metadata',
				       );
    }
}



=head2 get

  $output = $obj->get($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a get_params
$output is a reference to a list where each element is a reference to a list containing 2 items:
	0: an ObjectMeta
	1: an ObjectData
get_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	metadata_only has a value which is a bool
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string
ObjectData is a string

</pre>

=end html

=begin text

$input is a get_params
$output is a reference to a list where each element is a reference to a list containing 2 items:
	0: an ObjectMeta
	1: an ObjectData
get_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	metadata_only has a value which is a bool
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string
ObjectData is a string


=end text

=item Description



=back

=cut

sub get
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.get",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'get',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get",
					    status_line => $self->{client}->status_line,
					    method_name => 'get',
				       );
    }
}



=head2 update_auto_meta

  $output = $obj->update_auto_meta($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is an update_auto_meta_params
$output is a reference to a list where each element is an ObjectMeta
update_auto_meta_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string

</pre>

=end html

=begin text

$input is an update_auto_meta_params
$output is a reference to a list where each element is an ObjectMeta
update_auto_meta_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string


=end text

=item Description



=back

=cut

sub update_auto_meta
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function update_auto_meta (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to update_auto_meta:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'update_auto_meta');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.update_auto_meta",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'update_auto_meta',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method update_auto_meta",
					    status_line => $self->{client}->status_line,
					    method_name => 'update_auto_meta',
				       );
    }
}



=head2 get_download_url

  $urls = $obj->get_download_url($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a get_download_url_params
$urls is a reference to a list where each element is a string
get_download_url_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
FullObjectPath is a string

</pre>

=end html

=begin text

$input is a get_download_url_params
$urls is a reference to a list where each element is a string
get_download_url_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
FullObjectPath is a string


=end text

=item Description



=back

=cut

sub get_download_url
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_download_url (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get_download_url:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get_download_url');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.get_download_url",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'get_download_url',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get_download_url",
					    status_line => $self->{client}->status_line,
					    method_name => 'get_download_url',
				       );
    }
}



=head2 get_archive_url

  $url = $obj->get_archive_url($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a get_archive_url_params
$url is a string
get_archive_url_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	recursive has a value which is a bool
	archive_name has a value which is a string
	archive_type has a value which is a string
FullObjectPath is a string
bool is an int

</pre>

=end html

=begin text

$input is a get_archive_url_params
$url is a string
get_archive_url_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	recursive has a value which is a bool
	archive_name has a value which is a string
	archive_type has a value which is a string
FullObjectPath is a string
bool is an int


=end text

=item Description



=back

=cut

sub get_archive_url
{
    my($self, @args) = @_;

# Authentication: none

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function get_archive_url (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to get_archive_url:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'get_archive_url');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.get_archive_url",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'get_archive_url',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method get_archive_url",
					    status_line => $self->{client}->status_line,
					    method_name => 'get_archive_url',
				       );
    }
}



=head2 ls

  $output = $obj->ls($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_params
$output is a reference to a hash where the key is a FullObjectPath and the value is a reference to a list where each element is an ObjectMeta
list_params is a reference to a hash where the following keys are defined:
	paths has a value which is a reference to a list where each element is a FullObjectPath
	excludeDirectories has a value which is a bool
	excludeObjects has a value which is a bool
	recursive has a value which is a bool
	fullHierachicalOutput has a value which is a bool
	query has a value which is a reference to a hash where the key is a string and the value is a reference to a list where each element is a string
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string

</pre>

=end html

=begin text

$input is a list_params
$output is a reference to a hash where the key is a FullObjectPath and the value is a reference to a list where each element is an ObjectMeta
list_params is a reference to a hash where the following keys are defined:
	paths has a value which is a reference to a list where each element is a FullObjectPath
	excludeDirectories has a value which is a bool
	excludeObjects has a value which is a bool
	recursive has a value which is a bool
	fullHierachicalOutput has a value which is a bool
	query has a value which is a reference to a hash where the key is a string and the value is a reference to a list where each element is a string
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string


=end text

=item Description



=back

=cut

sub ls
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function ls (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to ls:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'ls');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.ls",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'ls',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method ls",
					    status_line => $self->{client}->status_line,
					    method_name => 'ls',
				       );
    }
}



=head2 copy

  $output = $obj->copy($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a copy_params
$output is a reference to a list where each element is an ObjectMeta
copy_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: (source) a FullObjectPath
	1: (destination) a FullObjectPath

	overwrite has a value which is a bool
	recursive has a value which is a bool
	move has a value which is a bool
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string

</pre>

=end html

=begin text

$input is a copy_params
$output is a reference to a list where each element is an ObjectMeta
copy_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: (source) a FullObjectPath
	1: (destination) a FullObjectPath

	overwrite has a value which is a bool
	recursive has a value which is a bool
	move has a value which is a bool
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string


=end text

=item Description



=back

=cut

sub copy
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function copy (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to copy:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'copy');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.copy",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'copy',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method copy",
					    status_line => $self->{client}->status_line,
					    method_name => 'copy',
				       );
    }
}



=head2 delete

  $output = $obj->delete($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a delete_params
$output is a reference to a list where each element is an ObjectMeta
delete_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	deleteDirectories has a value which is a bool
	force has a value which is a bool
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string

</pre>

=end html

=begin text

$input is a delete_params
$output is a reference to a list where each element is an ObjectMeta
delete_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	deleteDirectories has a value which is a bool
	force has a value which is a bool
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
Username is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string
WorkspacePerm is a string


=end text

=item Description



=back

=cut

sub delete
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function delete (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to delete:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'delete');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.delete",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'delete',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method delete",
					    status_line => $self->{client}->status_line,
					    method_name => 'delete',
				       );
    }
}



=head2 set_permissions

  $output = $obj->set_permissions($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a set_permissions_params
$output is an ObjectMeta
set_permissions_params is a reference to a hash where the following keys are defined:
	path has a value which is a FullObjectPath
	permissions has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm

	new_global_permission has a value which is a WorkspacePerm
	adminmode has a value which is a bool
FullObjectPath is a string
Username is a string
WorkspacePerm is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string

</pre>

=end html

=begin text

$input is a set_permissions_params
$output is an ObjectMeta
set_permissions_params is a reference to a hash where the following keys are defined:
	path has a value which is a FullObjectPath
	permissions has a value which is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm

	new_global_permission has a value which is a WorkspacePerm
	adminmode has a value which is a bool
FullObjectPath is a string
Username is a string
WorkspacePerm is a string
bool is an int
ObjectMeta is a reference to a list containing 12 items:
	0: an ObjectName
	1: an ObjectType
	2: a FullObjectPath
	3: (creation_time) a Timestamp
	4: an ObjectID
	5: (object_owner) a Username
	6: an ObjectSize
	7: a UserMetadata
	8: an AutoMetadata
	9: (user_permission) a WorkspacePerm
	10: (global_permission) a WorkspacePerm
	11: (shockurl) a string
ObjectName is a string
ObjectType is a string
Timestamp is a string
ObjectID is a string
ObjectSize is an int
UserMetadata is a reference to a hash where the key is a string and the value is a string
AutoMetadata is a reference to a hash where the key is a string and the value is a string


=end text

=item Description



=back

=cut

sub set_permissions
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function set_permissions (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to set_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'set_permissions');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.set_permissions",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'set_permissions',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method set_permissions",
					    status_line => $self->{client}->status_line,
					    method_name => 'set_permissions',
				       );
    }
}



=head2 list_permissions

  $output = $obj->list_permissions($input)

=over 4

=item Parameter and return types

=begin html

<pre>
$input is a list_permissions_params
$output is a reference to a hash where the key is a string and the value is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm
list_permissions_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
Username is a string
WorkspacePerm is a string

</pre>

=end html

=begin text

$input is a list_permissions_params
$output is a reference to a hash where the key is a string and the value is a reference to a list where each element is a reference to a list containing 2 items:
	0: a Username
	1: a WorkspacePerm
list_permissions_params is a reference to a hash where the following keys are defined:
	objects has a value which is a reference to a list where each element is a FullObjectPath
	adminmode has a value which is a bool
FullObjectPath is a string
bool is an int
Username is a string
WorkspacePerm is a string


=end text

=item Description



=back

=cut

sub list_permissions
{
    my($self, @args) = @_;

# Authentication: required

    if ((my $n = @args) != 1)
    {
	Bio::KBase::Exceptions::ArgumentValidationError->throw(error =>
							       "Invalid argument count for function list_permissions (received $n, expecting 1)");
    }
    {
	my($input) = @args;

	my @_bad_arguments;
        (ref($input) eq 'HASH') or push(@_bad_arguments, "Invalid type for argument 1 \"input\" (value was \"$input\")");
        if (@_bad_arguments) {
	    my $msg = "Invalid arguments passed to list_permissions:\n" . join("", map { "\t$_\n" } @_bad_arguments);
	    Bio::KBase::Exceptions::ArgumentValidationError->throw(error => $msg,
								   method_name => 'list_permissions');
	}
    }

    my $result = $self->{client}->call($self->{url}, $self->{headers}, {
	method => "Workspace.list_permissions",
	params => \@args,
    });
    if ($result) {
	if ($result->is_error) {
	    Bio::KBase::Exceptions::JSONRPC->throw(error => $result->error_message,
					       code => $result->content->{error}->{code},
					       method_name => 'list_permissions',
					       data => $result->content->{error}->{error} # JSON::RPC::ReturnObject only supports JSONRPC 1.1 or 1.O
					      );
	} else {
	    return wantarray ? @{$result->result} : $result->result->[0];
	}
    } else {
        Bio::KBase::Exceptions::HTTP->throw(error => "Error invoking method list_permissions",
					    status_line => $self->{client}->status_line,
					    method_name => 'list_permissions',
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
                method_name => 'list_permissions',
            );
        } else {
            return wantarray ? @{$result->result} : $result->result->[0];
        }
    } else {
        Bio::KBase::Exceptions::HTTP->throw(
            error => "Error invoking method list_permissions",
            status_line => $self->{client}->status_line,
            method_name => 'list_permissions',
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
a string
</pre>

=end html

=begin text

a string

=end text

=back



=head2 FullObjectPath

=over 4



=item Description

Path to any object in workspace database


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



=head2 ObjectMeta

=over 4



=item Description

ObjectMeta: tuple containing information about an object in the workspace 

        ObjectName - name selected for object in workspace
        ObjectType - type of the object in the workspace
        FullObjectPath - full path to object in workspace, including object name
        Timestamp creation_time - time when the object was created
        ObjectID - a globally unique UUID assigned to every object that will never change even if the object is moved
        Username object_owner - name of object owner
        ObjectSize - size of the object in bytes or if object is directory, the number of objects in directory
        UserMetadata - arbitrary user metadata associated with object
        AutoMetadata - automatically populated metadata generated from object data in automated way
        WorkspacePerm user_permission - permissions for the authenticated user of this workspace.
        WorkspacePerm global_permission - whether this workspace is globally readable.
        string shockurl - shockurl included if object is a reference to a shock node


=item Definition

=begin html

<pre>
a reference to a list containing 12 items:
0: an ObjectName
1: an ObjectType
2: a FullObjectPath
3: (creation_time) a Timestamp
4: an ObjectID
5: (object_owner) a Username
6: an ObjectSize
7: a UserMetadata
8: an AutoMetadata
9: (user_permission) a WorkspacePerm
10: (global_permission) a WorkspacePerm
11: (shockurl) a string

</pre>

=end html

=begin text

a reference to a list containing 12 items:
0: an ObjectName
1: an ObjectType
2: a FullObjectPath
3: (creation_time) a Timestamp
4: an ObjectID
5: (object_owner) a Username
6: an ObjectSize
7: a UserMetadata
8: an AutoMetadata
9: (user_permission) a WorkspacePerm
10: (global_permission) a WorkspacePerm
11: (shockurl) a string


=end text

=back



=head2 create_params

=over 4



=item Description

********* DATA LOAD FUNCTIONS *******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 5 items:
0: a FullObjectPath
1: an ObjectType
2: a UserMetadata
3: an ObjectData
4: (creation_time) a Timestamp

permission has a value which is a WorkspacePerm
createUploadNodes has a value which is a bool
downloadLinks has a value which is a bool
overwrite has a value which is a bool
adminmode has a value which is a bool
setowner has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 5 items:
0: a FullObjectPath
1: an ObjectType
2: a UserMetadata
3: an ObjectData
4: (creation_time) a Timestamp

permission has a value which is a WorkspacePerm
createUploadNodes has a value which is a bool
downloadLinks has a value which is a bool
overwrite has a value which is a bool
adminmode has a value which is a bool
setowner has a value which is a string


=end text

=back



=head2 update_metadata_params

=over 4



=item Description

"update_metadata" command
Description: 
This function permits the alteration of metadata associated with an object

Parameters:
list<tuple<FullObjectPath,UserMetadata>> objects - list of object paths and new metadatas
bool autometadata - this flag can only be used by the workspace itself
bool adminmode - run this command as an admin, meaning you can set permissions on anything anywhere


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
0: a FullObjectPath
1: a UserMetadata
2: an ObjectType
3: (creation_time) a Timestamp

autometadata has a value which is a bool
adminmode has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 4 items:
0: a FullObjectPath
1: a UserMetadata
2: an ObjectType
3: (creation_time) a Timestamp

autometadata has a value which is a bool
adminmode has a value which is a bool


=end text

=back



=head2 get_params

=over 4



=item Description

********* DATA RETRIEVAL FUNCTIONS *******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
metadata_only has a value which is a bool
adminmode has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
metadata_only has a value which is a bool
adminmode has a value which is a bool


=end text

=back



=head2 update_auto_meta_params

=over 4



=item Description

"update_shock_meta" command
Description:
Call this function to trigger an immediate update of workspace metadata for an object,
which should typically take place once the upload of a file into shock has completed

Parameters:
list<FullObjectPath> objects - list of full paths to objects for which shock nodes should be updated


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
adminmode has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
adminmode has a value which is a bool


=end text

=back



=head2 get_download_url_params

=over 4



=item Description

"get_download_url" command
Description:
This function returns a URL from which an object may be downloaded
without any other authentication required. The download URL will only be
valid for a limited amount of time. 

Parameters:
list<FullObjectPath> objects - list of full paths to objects for which URLs are to be constructed


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath


=end text

=back



=head2 get_archive_url_params

=over 4



=item Description

"get_archive_url" command
Description:
This function returns a URL from which an archive of the given 
objects may be downloaded. The download URL will only be valid for a limited
amount of time.

Parameters:
list<FullObjectPath> objects - list of full paths to objects to be archived
bool recursive - if true, recurse into folders
string archive_name - name to be given to the archive file
string archive_type - type of archive, one of "zip", "tar.gz", "tar.bz2"


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
recursive has a value which is a bool
archive_name has a value which is a string
archive_type has a value which is a string

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
recursive has a value which is a bool
archive_name has a value which is a string
archive_type has a value which is a string


=end text

=back



=head2 list_params

=over 4



=item Description

"list" command
Description: 
This function retrieves a list of all objects and directories below the specified paths with optional ability to filter by search

Parameters:
list<FullObjectPath> paths - list of full paths for which subobjects should be listed
bool excludeDirectories - don't return directories with output (optional; default = "0")
bool excludeObjects - don't return objects with output (optional; default = "0")
bool recursive - recursively list contents of all subdirectories; will not work above top level directory (optional; default "0")
bool fullHierachicalOutput - return a hash of all directories with contents of each; only useful with "recursive" (optional; default = "0")
mapping<string,string> query - filter output object lists by specified key/value query (optional; default = {})
bool adminmode - run this command as an admin, meaning you can see anything anywhere


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
paths has a value which is a reference to a list where each element is a FullObjectPath
excludeDirectories has a value which is a bool
excludeObjects has a value which is a bool
recursive has a value which is a bool
fullHierachicalOutput has a value which is a bool
query has a value which is a reference to a hash where the key is a string and the value is a reference to a list where each element is a string
adminmode has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
paths has a value which is a reference to a list where each element is a FullObjectPath
excludeDirectories has a value which is a bool
excludeObjects has a value which is a bool
recursive has a value which is a bool
fullHierachicalOutput has a value which is a bool
query has a value which is a reference to a hash where the key is a string and the value is a reference to a list where each element is a string
adminmode has a value which is a bool


=end text

=back



=head2 copy_params

=over 4



=item Description

********* REORGANIZATION FUNCTIONS ******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: (source) a FullObjectPath
1: (destination) a FullObjectPath

overwrite has a value which is a bool
recursive has a value which is a bool
move has a value which is a bool
adminmode has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: (source) a FullObjectPath
1: (destination) a FullObjectPath

overwrite has a value which is a bool
recursive has a value which is a bool
move has a value which is a bool
adminmode has a value which is a bool


=end text

=back



=head2 delete_params

=over 4



=item Description

********* DELETION FUNCTIONS ******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
deleteDirectories has a value which is a bool
force has a value which is a bool
adminmode has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
deleteDirectories has a value which is a bool
force has a value which is a bool
adminmode has a value which is a bool


=end text

=back



=head2 set_permissions_params

=over 4



=item Description

********* FUNCTIONS RELATED TO SHARING *******************


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
path has a value which is a FullObjectPath
permissions has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: a Username
1: a WorkspacePerm

new_global_permission has a value which is a WorkspacePerm
adminmode has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
path has a value which is a FullObjectPath
permissions has a value which is a reference to a list where each element is a reference to a list containing 2 items:
0: a Username
1: a WorkspacePerm

new_global_permission has a value which is a WorkspacePerm
adminmode has a value which is a bool


=end text

=back



=head2 list_permissions_params

=over 4



=item Description

"list_permissions" command
Description: 
This function lists permissions for the specified objects

Parameters:
list<FullObjectPath> objects - path to objects for which permissions are to be listed
bool adminmode - run this command as an admin, meaning you can list permissions on anything anywhere


=item Definition

=begin html

<pre>
a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
adminmode has a value which is a bool

</pre>

=end html

=begin text

a reference to a hash where the following keys are defined:
objects has a value which is a reference to a list where each element is a FullObjectPath
adminmode has a value which is a bool


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
