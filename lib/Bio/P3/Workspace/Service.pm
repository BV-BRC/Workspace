package Bio::P3::Workspace::Service;


use strict;
use Data::Dumper;
use Moose;
use POSIX;
use JSON;
use File::Temp;
use File::Slurp;
use Class::Load qw();
use Config::Simple;

my $get_time = sub { time, 0 };
eval {
    require Time::HiRes;
    $get_time = sub { Time::HiRes::gettimeofday(); };
};

use P3AuthToken;
use P3TokenValidator;

my $g_hostname = `hostname`;
chomp $g_hostname;
$g_hostname ||= 'unknown-host';

extends 'RPC::Any::Server::JSONRPC::PSGI';

has 'instance_dispatch' => (is => 'ro', isa => 'HashRef');
has 'user_auth' => (is => 'ro', isa => 'UserAuth');
has 'valid_methods' => (is => 'ro', isa => 'HashRef', lazy => 1,
			builder => '_build_valid_methods');
has 'validator' => (is => 'ro', isa => 'P3TokenValidator', lazy => 1, builder => '_build_validator');
our $CallContext;

our %return_counts = (
        'create' => 1,
        'update_metadata' => 1,
        'get' => 1,
        'update_auto_meta' => 1,
        'get_download_url' => 1,
        'get_archive_url' => 3,
        'ls' => 1,
        'copy' => 1,
        'delete' => 1,
        'set_permissions' => 1,
        'list_permissions' => 1,
        'version' => 1,
);

our %method_authentication = (
        'create' => 'required',
        'update_metadata' => 'required',
        'get' => 'optional',
        'update_auto_meta' => 'required',
        'get_download_url' => 'optional',
        'get_archive_url' => 'optional',
        'ls' => 'optional',
        'copy' => 'required',
        'delete' => 'required',
        'set_permissions' => 'required',
        'list_permissions' => 'optional',
);

sub _build_validator
{
    my($self) = @_;
    return P3TokenValidator->new();

}


sub _build_valid_methods
{
    my($self) = @_;
    my $methods = {
        'create' => 1,
        'update_metadata' => 1,
        'get' => 1,
        'update_auto_meta' => 1,
        'get_download_url' => 1,
        'get_archive_url' => 1,
        'ls' => 1,
        'copy' => 1,
        'delete' => 1,
        'set_permissions' => 1,
        'list_permissions' => 1,
        'version' => 1,
    };
    return $methods;
}

#
# Override method from RPC::Any::Server::JSONRPC 
# to eliminate the deprecation warning for Class::MOP::load_class.
#
sub _default_error {
    my ($self, %params) = @_;
    my $version = $self->default_version;
    $version =~ s/\./_/g;
    my $error_class = "JSON::RPC::Common::Procedure::Return::Version_${version}::Error";
    Class::Load::load_class($error_class);
    my $error = $error_class->new(%params);
    my $return_class = "JSON::RPC::Common::Procedure::Return::Version_$version";
    Class::Load::load_class($return_class);
    return $return_class->new(error => $error);
}


#override of RPC::Any::Server
sub handle_error {
    my ($self, $error) = @_;
    
    unless (ref($error) eq 'HASH' ||
           (blessed $error and $error->isa('RPC::Any::Exception'))) {
        $error = RPC::Any::Exception::PerlError->new(message => $error);
    }
    my $output;
    eval {
        my $encoded_error = $self->encode_output_from_exception($error);
        $output = $self->produce_output($encoded_error);
    };
    
    return $output if $output;
    
    die "$error\n\nAlso, an error was encountered while trying to send"
        . " this error: $@\n";
}

#override of RPC::Any::JSONRPC
sub encode_output_from_exception {
    my ($self, $exception) = @_;
    my %error_params;
    if (ref($exception) eq 'HASH') {
        %error_params = %{$exception};
        if(defined($error_params{context})) {
            my @errlines;
            $errlines[0] = $error_params{message};
            push @errlines, split("\n", $error_params{data});
            delete $error_params{context};
        }
    } else {
        %error_params = (
            message => $exception->message,
            code    => $exception->code,
        );
    }
    my $json_error;
    if ($self->_last_call) {
        $json_error = $self->_last_call->return_error(%error_params);
    }
    # Default to default_version. This happens when we throw an exception
    # before inbound parsing is complete.
    else {
        $json_error = $self->_default_error(%error_params);
    }
    return $self->encode_output_from_object($json_error);
}

#
# another override.
#
sub get_package_isa {
    my ($self, $module) = @_;
    my $original_isa;
    { no strict 'refs'; $original_isa = \@{"${module}::ISA"}; }
    my @new_isa = @$original_isa;

    my $base = $self->package_base;
    if (not $module->isa($base)) {
        Class::Load::load_class($base);
        push(@new_isa, $base);
    }
    return \@new_isa;
}
sub trim {
    my ($str) = @_;
    if (!(defined $str)) {
        return $str;
    }
    $str =~ s/^\s+|\s+$//g;
    return $str;
}

sub getIPAddress {
    my ($self) = @_;
    my $xFF = trim($self->_plack_req->header("X-Forwarded-For"));
    my $realIP = trim($self->_plack_req->header("X-Real-IP"));
    # my $nh = $self->config->{"dont_trust_x_ip_headers"};
    my $nh;
    my $trustXHeaders = !(defined $nh) || $nh ne "true";

    if ($trustXHeaders) {
        if ($xFF) {
            my @tmp = split(",", $xFF);
            return trim($tmp[0]);
        }
        if ($realIP) {
            return $realIP;
        }
    }
    return $self->_plack_req->address;
}

#
# Ping method reflected from /ping on the service.
#
sub ping
{
    my($self, $env) = @_;
    return [ 200, ["Content-type" => "text/plain"], [ "OK\n" ] ];
}


#
# Authenticated ping method reflected from /auth_ping on the service.
#
sub auth_ping
{
    my($self, $env) = @_;

    my $req = Plack::Request->new($env);
    my $token = $req->header("Authorization");

    if (!$token)
    {
	return [401, [], ["Authentication required"]];
    }

    my $auth_token = P3AuthToken->new(token => $token, ignore_authrc => 1);
    my($valid, $validate_err) = $self->validator->validate($auth_token);

    if ($valid)
    {
	return [200, ["Content-type" => "text/plain"], ["OK " . $auth_token->user_id . "\n"]];
    }
    else
    {
        warn "Token validation error $validate_err\n";
	return [403, [], "Authentication failed"];
    }
}

sub call_method {
    my ($self, $data, $method_info) = @_;

    my ($module, $method, $modname) = @$method_info{qw(module method modname)};
    
    my $ctx = Bio::P3::Workspace::ServiceContext->new(client_ip => $self->getIPAddress());
    $ctx->module($modname);
    $ctx->method($method);
    $ctx->call_id($self->{_last_call}->{id});
    
    my $args = $data->{arguments};

{
    # Service Workspace requires authentication.

    my $method_auth = $method_authentication{$method};
    $ctx->authenticated(0);
    if ($method_auth eq 'none')
    {
	# No authentication required here. Move along.
    }
    else
    {
	my $token = $self->_plack_req->header("Authorization");

	if (!$token && $method_auth eq 'required')
	{
	    $self->exception('PerlError', "Authentication required for Workspace but no authentication header was passed");
	}

	my $auth_token = P3AuthToken->new(token => $token, ignore_authrc => 1);
	my($valid, $validate_err) = $self->validator->validate($auth_token);
	# Only throw an exception if authentication was required and it fails
	if ($method_auth eq 'required' && !$valid)
	{
	    $self->exception('PerlError', "Token validation failed: $validate_err");
	} elsif ($valid) {
	    $ctx->authenticated(1);
	    $ctx->user_id($auth_token->user_id);
	    $ctx->token( $token);
	}
    }
}
    my $new_isa = $self->get_package_isa($module);
    no strict 'refs';
    local @{"${module}::ISA"} = @$new_isa;
    local $CallContext = $ctx;
    my @result;
    {
	# 
	# Process tag and metadata information if present.
	#
	my $tag = $self->_plack_req->header("Kbrpc-Tag");
	if (!$tag)
	{
	    $self->{hostname} ||= $g_hostname;

	    my ($t, $us) = &$get_time();
	    $us = sprintf("%06d", $us);
	    my $ts = strftime("%Y-%m-%dT%H:%M:%S.${us}Z", gmtime $t);
	    $tag = "S:$self->{hostname}:$$:$ts";
	}
	local $ENV{KBRPC_TAG} = $tag;
	my $kb_metadata = $self->_plack_req->header("Kbrpc-Metadata");
	my $kb_errordest = $self->_plack_req->header("Kbrpc-Errordest");
	local $ENV{KBRPC_METADATA} = $kb_metadata if $kb_metadata;
	local $ENV{KBRPC_ERROR_DEST} = $kb_errordest if $kb_errordest;

	my $stderr = Bio::P3::Workspace::ServiceStderrWrapper->new($ctx, $get_time);
	$ctx->stderr($stderr);

	#
	# Set up environment for user-level error reporting.
	#
	my $user_error = File::Temp->new(UNLINK => 1);
	close($user_error);
	$ENV{P3_USER_ERROR_DESTINATION} = "$user_error";

        my $xFF = $self->_plack_req->header("X-Forwarded-For");
	
        my $err;
        eval {
	    local $SIG{__WARN__} = sub {
		my($msg) = @_;
		print STDERR $msg;
	    };

            @result = $module->$method(@{ $data->{arguments} });
        };
	
        if ($@)
        {
            my $err = $@;
	    $stderr->log($err);
	    $ctx->stderr(undef);
	    undef $stderr;
            my $nicerr;
	    my $str = "$err";
	    my $msg = $str;
	    $msg =~ s/ at [^\s]+.pm line \d+.\n$//;
	    
	    # If user-level error present, replace message with that
	    if (-s "$user_error")
	    {
	        $msg = read_file("$user_error");
		$str = $msg;
	    }
	    $nicerr =  {code => -32603, # perl error from RPC::Any::Exception
                            message => $msg,
                            data => $str,
                            context => $ctx
                            };
            die $nicerr;
        }
	$ctx->stderr(undef);
	undef $stderr;
    }
    my $result;
    if ($return_counts{$method} == 1)
    {
        $result = [[$result[0]]];
    }
    else
    {
        $result = \@result;
    }
    return $result;
}


sub get_method
{
    my ($self, $data) = @_;
    
    my $full_name = $data->{method};
    
    $full_name =~ /^(\S+)\.([^\.]+)$/;
    my ($package, $method) = ($1, $2);
    
    if (!$package || !$method) {
	$self->exception('NoSuchMethod',
			 "'$full_name' is not a valid method. It must"
			 . " contain a package name, followed by a period,"
			 . " followed by a method name.");
    }

    if (!$self->valid_methods->{$method})
    {
	$self->exception('NoSuchMethod',
			 "'$method' is not a valid method in service Workspace.");
    }
	
    my $inst = $self->instance_dispatch->{$package};
    my $module;
    if ($inst)
    {
	$module = $inst;
    }
    else
    {
	$module = $self->get_module($package);
	if (!$module) {
	    $self->exception('NoSuchMethod',
			     "There is no method package named '$package'.");
	}
	
	Class::Load::load_class($module);
    }
    
    if (!$module->can($method)) {
	$self->exception('NoSuchMethod',
			 "There is no method named '$method' in the"
			 . " '$package' package.");
    }
    
    return { module => $module, method => $method, modname => $package };
}

package Bio::P3::Workspace::ServiceContext;

use strict;

=head1 NAME

Bio::P3::Workspace::ServiceContext

head1 DESCRIPTION

A KB RPC context contains information about the invoker of this
service. If it is an authenticated service the authenticated user
record is available via $context->user. The client IP address
is available via $context->client_ip.

=cut

use base 'Class::Accessor';

__PACKAGE__->mk_accessors(qw(user_id client_ip authenticated token
                             module method call_id hostname stderr));

sub new
{
    my($class, @opts) = @_;

    if (!defined($opts[0]) || ref($opts[0]))
    {
        # We were invoked by old code that stuffed a logger in here.
	# Strip that option.
	shift @opts;
    }
    
    my $self = {
        hostname => $g_hostname,
        @opts,
    };

    return bless $self, $class;
}

package Bio::P3::Workspace::ServiceStderrWrapper;

use strict;
use POSIX;
use Time::HiRes 'gettimeofday';

sub new
{
    my($class, $ctx, $get_time) = @_;
    my $self = {
	get_time => $get_time,
    };
    my $dest = $ENV{KBRPC_ERROR_DEST} if exists $ENV{KBRPC_ERROR_DEST};
    my $tag = $ENV{KBRPC_TAG} if exists $ENV{KBRPC_TAG};
    my ($t, $us) = gettimeofday();
    $us = sprintf("%06d", $us);
    my $ts = strftime("%Y-%m-%dT%H:%M:%S.${us}Z", gmtime $t);

    my $name = join(".", $ctx->module, $ctx->method, $ctx->hostname, $ts);

    if ($dest && $dest =~ m,^/,)
    {
	#
	# File destination
	#
	my $fh;

	if ($tag)
	{
	    $tag =~ s,/,_,g;
	    $dest = "$dest/$tag";
	    if (! -d $dest)
	    {
		mkdir($dest);
	    }
	}
	if (open($fh, ">", "$dest/$name"))
	{
	    $self->{file} = "$dest/$name";
	    $self->{dest} = $fh;
	}
	else
	{
	    warn "Cannot open log file $dest/$name: $!";
	}
    }
    else
    {
	#
	# Log to string.
	#
	my $stderr;
	$self->{dest} = \$stderr;
    }
    
    bless $self, $class;

    for my $e (sort { $a cmp $b } keys %ENV)
    {
	$self->log_cmd($e, $ENV{$e});
    }
    return $self;
}

sub redirect
{
    my($self) = @_;
    if ($self->{dest})
    {
	return("2>", $self->{dest});
    }
    else
    {
	return ();
    }
}

sub redirect_both
{
    my($self) = @_;
    if ($self->{dest})
    {
	return(">&", $self->{dest});
    }
    else
    {
	return ();
    }
}

sub timestamp
{
    my($self) = @_;
    my ($t, $us) = $self->{get_time}->();
    $us = sprintf("%06d", $us);
    my $ts = strftime("%Y-%m-%dT%H:%M:%S.${us}Z", gmtime $t);
    return $ts;
}

sub log
{
    my($self, $str) = @_;
    my $d = $self->{dest};
    my $ts = $self->timestamp();
    if (ref($d) eq 'SCALAR')
    {
	$$d .= "[$ts] " . $str . "\n";
	return 1;
    }
    elsif ($d)
    {
	print $d "[$ts] " . $str . "\n";
	return 1;
    }
    return 0;
}

sub log_cmd
{
    my($self, @cmd) = @_;
    my $d = $self->{dest};
    my $str;
    my $ts = $self->timestamp();
    if (ref($cmd[0]))
    {
	$str = join(" ", @{$cmd[0]});
    }
    else
    {
	$str = join(" ", @cmd);
    }
    if (ref($d) eq 'SCALAR')
    {
	$$d .= "[$ts] " . $str . "\n";
    }
    elsif ($d)
    {
	print $d "[$ts] " . $str . "\n";
    }
	 
}

sub dest
{
    my($self) = @_;
    return $self->{dest};
}

sub text_value
{
    my($self) = @_;
    if (ref($self->{dest}) eq 'SCALAR')
    {
	my $r = $self->{dest};
	return $$r;
    }
    else
    {
	return $self->{file};
    }
}


1;
