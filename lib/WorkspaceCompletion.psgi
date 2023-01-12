use Data::Dumper;
use Bio::P3::Workspace::WorkspaceImpl;
use Bio::P3::Workspace::Service;
use Plack::Middleware::CrossOrigin;
use JSON::XS;
use P3AuthToken;
use P3TokenValidator;
use Time::HiRes 'gettimeofday';

use strict;

my $fields = { name => 1, owner=> 1, path => 1, size => 1, type => 1, uuid => 1, workspace_uuid => 1 };

my $json = JSON::XS->new->pretty();
my $validator = P3TokenValidator->new();

my $identifier_property = "path";

my $impl = Bio::P3::Workspace::WorkspaceImpl->new();

my %ws_cache;

my $handler = sub {
    my($env) = @_;

    my $req = Plack::Request->new($env);
    print Dumper($req);
    
    my $params = $req->parameters;
    my $headers = $req->headers;

    my $auth_token_str = $headers->header("Authorization");
    my $auth_token = P3AuthToken->new(token => $auth_token_str, ignore_authrc => 1);
    
    $auth_token or return [403, ['Content-Type' => 'text/plain'], ['Permission denied']];
    my($valid, $validate_err) = $validator->validate($auth_token);
    
    if (!$valid)
    {
        warn "Token validation error $validate_err\n";
	return [403, [], "Authentication failed"];
    }

    my $ctx = Bio::P3::Workspace::ServiceContext->new();
    $ctx->authenticated(1);
    $ctx->user_id($auth_token->user_id);
    $ctx->token($auth_token_str);
    
    local $Bio::P3::Workspace::Service::CallContext = $ctx;

    my $user = $auth_token->user_id;
    
    my $name = $params->{name};
    my $id = $params->{id};
    my @types = $req->body_parameters->get_all('type');
    my @workspaces = $req->body_parameters->get_all('workspaces');
    my $req_rows = $params->{count} // 20;
    my $req_start = $params->{start} // 0;

    my $perm_required = $params->{writableWorkspaces} ? 'w' : 'r';

    print Dumper($params, $name, $id, $user, \@types, \@workspaces, $perm_required, $params->{writableWorkspaces});

    # Default result is empty.
    my $qresult = {
	numRows => 0,
	items => [],
	identity => $identifier_property,
	identifier => $identifier_property,
    };
    

    if (defined($name) && $name !~ m,^/,)
    {
	#
	# Search by name. Name that starts with a non-slash is a search for a filename.
	#

	$name =~ s,/\*$,,;

	my @nquery = init_object_query($name, \@types);

	#
	# Handle an explicit workspace enumeration. We need to verify that the user
	# has permission to read the workspace data.
	# Note that we actually need to know if the data is to be read or written and
	# adjust appropriately here. This will need to filter all the way down from
	# the application using the workspace object selector.
	#
	if (@workspaces)
	{
	    my @orq;
	    my @req;
	    for my $ws (@workspaces)
	    {
		if (my($ws_owner, $ws_name) = $ws =~ m,^/([^@/]+@[^/]+)/([^/]+)$,)
		{
		    push(@req, [$ws_owner, $ws_name]);
		    if (!exists $ws_cache{$ws_owner, $ws_name})
		    {
			push(@orq, { owner => $ws_owner, name => $ws_name });
		    }
		}
	    }
	    if (@orq)
	    {
		my $col = $impl->_mongodb()->get_collection('workspaces');
		my $cur = $col->find({'$or' => \@orq});
		while (my $item = $cur->next)
		{
		    print Dumper($item);
		    $ws_cache{$item->{owner}, $item->{name}} = $item;
		}
	    }
	    my @ids;
	    for my $item (@req)
	    {
		my $wsobj = $ws_cache{$item->[0], $item->[1]};
		my $ok = $impl->_check_ws_permissions($wsobj, $perm_required);
		print "$wsobj->{owner} $wsobj->{name} ok=$ok\n";
		push(@ids, $wsobj->{uuid}) if $ok;
	    }
	    push(@nquery, 'workspace_uuid' => { '$in' => \@ids });
	}

	my $col = $impl->_mongodb()->get_collection('objects');
	my $query = {
	    @nquery,
	    owner => $user,
	    # creation_date => { '$gt' => '2021-08-19T21:39:59Z' },
	    };
	print Dumper($query);
	my $start = gettimeofday;
	my $cur = $col->find($query)->sort({ creation_date => -1 })->skip($req_start)->limit($req_rows);

	my $end = gettimeofday;
	$qresult = process_query_output($cur);
	my $n_res = @{$qresult->{items}};
	my $elap = $end - $start;
	print "$n_res results in $elap\n";
    }
    elsif ($name =~ m,^/([^@]+@[^/]+)/([^/]+)(/.*?)(\*?)$,)
    {
	my $ws_owner = $1;
	my $ws_name = $2;
	my $path = $3;
	my $wild = $4;
	my $name;

	$path =~ s,^/,,;
	print "PATH=$path\n";

	if ($path !~ m,/,) 
	{
	    $name = $path;
	    $path = '';
	    print "set 1\n";
	}
	else
	{
	    $path =~ s,^/,,;
	    ($path, $name) = $path =~ m,(.*)/([^/]*)$,;
	    print "set 2\n";
	}
	print "ws_owner=$ws_owner ws_name=$ws_name path=$path name=$name wild=$wild\n";

	#
	# Look up workspace.
	#
	my $wsobj = $ws_cache{$ws_owner, $ws_name};
	if (!$wsobj)
	{
	    my $col = $impl->_mongodb()->get_collection('workspaces');
	    $wsobj = $col->find_one({ owner => $ws_owner, name => $ws_name });
	    if ($wsobj)
	    {
		$ws_cache{$ws_owner, $ws_name} = $wsobj;
	    }
	    else
	    {
		warn "No ws found for $ws_owner $ws_name\n";
	    }
	}


	if ($wsobj)
	{
	    my $ok = $impl->_check_ws_permissions($wsobj, $perm_required);
	    if ($ok)
	    {
		print "$wsobj->{owner} $wsobj->{name} ok=$ok\n";
	    }
	    else
	    {
		undef $wsobj;
	    }
	    
	    my @nquery = init_object_query($name, [@types, 'folder']);
	    
	    my $col = $impl->_mongodb()->get_collection('objects');
	    my $query = {
		@nquery,
		path => $path,
		workspace_uuid => $wsobj->{uuid},
	    };
	    print Dumper($query);

	    my $cur = $col->find($query)->sort({ creation_date => -1 })->skip($req_start)->limit($req_rows);

	    $qresult = process_query_output($cur);
	}
    }
    elsif ($id =~ m,^[^@]+@[^/]+$,)
    {
	print "Check plain WS\n";
    }
    elsif ($id)
    {
	print "ID SEARCH $id\n";
	my $res = $impl->get({ objects => [$id], metaonly => 1 });
	if (@$res)
	{
	    my $meta = $res->[0]->[0];
	    my $data = meta_to_dict($meta);
	    
	    $qresult = {
		numRows => 1,
		items => [$data],
		identity => $identifier_property,
		identifier => $identifier_property,
	    };
	};
    }
    
    my $ret = [200, ['Content-Type' => 'application/json'], [$json->encode($qresult)]];
    print "RETURN total size $qresult->{numRows}\n";
    for my $item (@{$qresult->{items}})
    {
	print join("\t", (map { $_->{id}, $_->{type}, $_->{creation_time}, $_->{path} } $item)) . "\n";
    }
    return $ret;
};

Plack::Middleware::CrossOrigin->wrap( $handler, origins => "*", headers => "*");



sub meta_to_dict
{
    my($meta) = @_;
    return {
	id => $meta->[4],
	path => $meta->[2] . $meta->[0],
	name => $meta->[0],
	type => $meta->[1],
	creation_time => $meta->[3],
	link_reference => $meta->[11],
	owner_id => $meta->[5],
	size => $meta->[6],
	userMeta => $meta->[7],
	autoMeta => $meta->[8],
	user_permission => $meta->[9],
	global_permission => $meta->[10],
    };
}

sub init_object_query
{
    my($name, $types, $wildcard) = @_;
    my @nquery;
    if ($name eq '*')
    {
	# empty query
    }
    elsif ($name =~ s/\*$// || $wildcard)
    {
	@nquery = (name => qr/^$name/);
    }
    elsif ($name)
    {
	@nquery = (name => $name);
    }
    
    if (@$types)
    {
	push(@nquery, '$or' => [ map { { type => $_ } } @$types ]);
    }
    return @nquery;
}

sub process_query_output
{
    my($cursor) = @_;

    my $count = $cursor->count();
    my @data;
    while (my $item = $cursor->next)
    {
	delete $item->{_id};
	$item->{wsobj} = $impl->_wscache("_uuid",$item->{workspace_uuid});
	my $meta = $impl->_generate_object_meta($item);
	push(@data, meta_to_dict($meta));
    }

    my $qresult = {
	numRows => $count,
	items => \@data,
	identity => $identifier_property,
	identifier => $identifier_property,
    };
    return $qresult;
}
