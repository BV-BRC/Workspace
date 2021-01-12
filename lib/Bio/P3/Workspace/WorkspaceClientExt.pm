package Bio::P3::Workspace::WorkspaceClientExt;

use Data::Dumper;
use strict;
use base 'Bio::P3::Workspace::WorkspaceClient';
use LWP::UserAgent;
use File::stat ();
use File::Basename;
use File::Slurp;
use Cwd qw(getcwd abs_path);
use File::Find;
use Fcntl ':mode';
use JSON::XS;

our %folder_types = (folder => 1,
		     modelfolder => 1 );

sub file_is_gzipped
{
    my($self, $ws_path) = @_;

    my $res = eval { $self->get({ objects => [$ws_path], metadata_only => 1 }); };
    return undef if $@ =~ /_ERROR_/;

    my($obj_meta, $obj_data) = @{$res->[0]};
    my($name, $type, $path, $ts, $oid, $owner, $size, $usermeta, $autometa,
       $user_perm, $global_perm, $shockurl) = @$obj_meta;

    if (!$shockurl)
    {
	return 0;
    }

    my %comp_map = ("\x1f\x8b" => 'gzip',
		    "BZ" => 'bzip2');

    my $hdr = $self->shock_read_bytes($shockurl, 0, 2);
    return $comp_map{$hdr};
}

#
# Read some number of bytes from the given shock url.
#
sub shock_read_bytes
{
    my($self, $url, $offset, $length) = @_;

    my $ua = LWP::UserAgent->new();
    my @auth = (Authorization => "OAuth " . $self->{token});

    my $get_url = "$url?download&seek=$offset&length=$length";
    my $res = $ua->get($get_url, @auth);
    if ($res->is_success)
    {
	return $res->content;
    }
    else
    {
	warn "Get failed: " . $res->status_line . ": " . $res->content;
	return undef;
    }
       
}
    

sub download_file
{
    my($self, $ws_path, $local_file, $use_shock, $token, $opts) = @_;

    $token //= $self->{token};
       
    open(my $fh, ">", $local_file) or die "WorkspaceClientExt::download_file: cannot write $local_file: $!";
    $self->copy_files_to_handles($use_shock, $token, [[$ws_path, $fh]], $opts);
    close($fh);
}

=item B<upload_folder>

    $res = $ws->upload_folder($local_path, $ws_path, $suffix_type_map)

 local: /home/user/foo/bar
 ws: /u@p.org/xx
 Dest path is /u@p.org/xx/bar

 local: /home/user/foo/bar/.
 ws: /u@p.org/xx
 Dest path is /u@p.org/xx


=cut

sub upload_folder
{
    my($self, $local_path, $ws_path_base, $opts) = @_;

    my $suffix_type_map = $opts->{type_map} // {};
    my $exclude = $opts->{exclude} // [];

    my $abs_local = abs_path($local_path);

    my $cwd = getcwd();
    $local_path .= "." if ($local_path =~ m,/$,);

    my $last = basename($local_path);
    my $top;
    if ($last eq '.')
    {
	chdir($local_path) or die "Cannot chdir $local_path: $!";
	$top = ".";
    }
    else
    {
	my $d = dirname($local_path);
	chdir($d) or die "Cannot chdir $d: $!";
	$top = $last;
    }

    my $proc = sub {
	# $File::Find::dir is the dirname
	# $_ is the filename
	# $ File::Find::name is the pathame


	for my $e (@$exclude)
	{
	    if (/$e/)
	    {
		print "Exclude $_\n";
		$File::Find::prune = 1;
		return;
	    }
	}

	my $ws_path = "$ws_path_base/$File::Find::name";
	$ws_path =~ s,/\./,/,g;

#	print "'$ws_path' '$_'  '$File::Find::name\n";
	if (-d $_)
	{
	    if (!$self->exists($ws_path))
	    {
		print "Create $ws_path\n";
		$self->create({objects => [[$ws_path, 'folder']]});
	    }
	}
	elsif (-f $_)
	{
	    my($suffix) = /\.([^.]+)$/;
	    my $type = $suffix_type_map->{$suffix} // 'txt';
	    print "Copy $_ => $ws_path with type $type\n";
	    $self->save_file_to_file($_, { original_path => dirname($abs_local) . "/" . $File::Find::name }, $ws_path, $type, 1,
	     (-s > 1000 ? 1 : 0), $self->{token});
	}
    };
    find($proc, $top);
    chdir($cwd);
}

sub exists
{
    my($self, $path) = @_;

    my $cur = eval { $self->get( { objects => [$path], metadata_only => 1 } ); };
    return ($cur && @$cur == 1);
}
    

sub download_file_to_string
{
    my($self, $path, $token) = @_;

    $token //= $self->{token};
       
    my $str;
    open(my $fh, ">", \$str) or die "Cannot open string reference filehandle: $!";

    eval {
	$self->copy_files_to_handles(1, $token, [[$path, $fh]]);
    };
    if ($@)
    {
	my($err) = $@ =~ /_ERROR_(.*)_ERROR_/;
	$err //= $@;
	die "Bio::P3::Workspace::WorkspaceClientExt::download_file_to_string: failed to load $path: $err\n";
    }
    close($fh);

    return $str;
}

sub download_json
{
    my($self, $path, $token, $options) = @_;

    $token //= $self->{token};
       
    my $str;
    open(my $fh, ">", \$str) or die "Cannot open string reference filehandle: $!";

    eval {
	$self->copy_files_to_handles(1, $token, [[$path, $fh]], $options);
    };
    if ($@)
    {
	my($err) = $@ =~ /_ERROR_(.*)_ERROR_/;
	$err //= $@;
	die "Bio::P3::Workspace::WorkspaceClientExt::download_json: failed to load $path: $err\n";
    }
    close($fh);

    my $doc = eval { decode_json($str) };

    if ($@)
    {
	die "Error parsing json: $@";
    }
    return $doc;
}

sub copy_files_to_handles
{
    my($self, $use_shock, $token, $file_handle_pairs, $opts) = @_;

    $opts //= {};

    $token //= $self->{token};
       
    my $ua;
    if ($use_shock)
    {
	$ua = LWP::UserAgent->new();
	$token = $token->token if ref($token);
    }
    my @get_opts;
    if ($opts->{admin})
    {
	push(@get_opts, adminmode => 1);
    }

    for my $pair (@$file_handle_pairs)
    {
	my($filename, $fh) = @$pair;
	my $res = eval { $self->get({ @get_opts, objects => [ $filename ] }) };
	if (!$res)
	{
	    #
	    # This might have failed to the pathname needing utf8 decoding.
	    #
	    utf8::decode($filename);
	    print STDERR "Retry download after decoding $filename\n";
	    $res = eval { $self->get({@get_opts, objects => [$filename]}); };
	    if (!$res)
	    {
		die "Workspace object not found for $filename\n";
	    }
	}
	my $ent = $res->[0];
	my($meta, $data) = @$ent;

	bless $meta, 'Bio::P3::Workspace::ObjectMeta';

	if ($use_shock && $meta->shock_url)
	{
	    my $cb = sub {
		my($data) = @_;
		print $fh $data;
	    };

	    my $qry = '?download';
	    if (my $o = $opts->{offset})
	    {
		$qry .= "&seek=$o";
	    }
	    if (my $o = $opts->{length})
	    {
		$qry .= "&length=$o";
	    }

	    my $res = $ua->get($meta->shock_url . $qry,
			       Authorization => "OAuth " . $token,
			       ':content_cb' => $cb);
	    if (!$res->is_success)
	    {
		warn "Error retrieving " . $meta->shock_url . ": " . $res->content . "\n";
	    }
	}
	else
	{
	    print $fh $data;
	}
    }
}


sub save_data_to_file
{
    my($self, $data, $metadata, $path, $type, $overwrite, $use_shock, $token) = @_;

    $token //= $self->{token};
       
    $type ||= 'unspecified';

    my $obj;
    if ($use_shock)
    {
	local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;

	$token = $token->token if ref($token);
	my $ua = LWP::UserAgent->new();

	my $res = $self->create({ objects => [[$path, $type, $metadata ]],
				overwrite => ($overwrite ? 1 : 0),
				createUploadNodes => 1 });
	if (!ref($res) || @$res == 0)
	{
	    die "Create failed";
	}
	$res = $res->[0];
	$obj = $res;
	my $shock_url = $res->[11];
	$shock_url or die "Workspace did not return shock url. Return object: " . Dumper($res);
	
	my $req = HTTP::Request::Common::POST($shock_url, 
					      Authorization => "OAuth " . $token,
					      Content_Type => 'multipart/form-data',
					      Content => [upload => [undef, 'file', Content => $data]]);
	$req->method('PUT');
	my $sres = $ua->request($req);
	if (!$sres->is_success)
	{
	    die "Failure writing to shock at $shock_url: " . $sres->code . " " . $sres->content;
	}
#	print STDERR Dumper($sres->content);
    }
    else
    {
	my $res = $self->create({ objects => [[$path, $type, $metadata, $data ]],
				overwrite => ($overwrite ? 1 : 0) });
	$obj = $res->[0];
#	print STDERR Dumper($res);
    }
    return $obj;
}

sub save_file_to_file
{
    my($self, $local_file, $metadata, $path, $type, $overwrite, $use_shock, $token) = @_;

    $token //= $self->{token};
       
    $type ||= 'unspecified';

    my $obj;
    if ($use_shock)
    {
	local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;

	$token = $token->token if ref($token);
	my $ua = LWP::UserAgent->new();
	$ua->timeout(86400);

	print STDERR "Create $path\n";
	my $res = $self->create({ objects => [[$path, $type, $metadata ]],
				overwrite => ($overwrite ? 1 : 0),
				createUploadNodes => 1 });
	print STDERR "create returns " . Dumper($res);
	if (!ref($res) || @$res == 0)
	{
	    die "Create failed";
	}
	$res = $res->[0];
	my $shock_url = $res->[11];
	
	my $req = HTTP::Request::Common::POST($shock_url, 
					      Authorization => "OAuth " . $token,
					      Content_Type => 'multipart/form-data',
					      Content => [upload => [$local_file]]);
	$req->method('PUT');
	my $sres = $ua->request($req);
	print STDERR "shock finishes\n";
	if (!$sres->is_success)
	{
	    die "Failure uploading $local_file to shock: " . $sres->status_line;
	}
	$obj = $res;
    }
    else
    {
	my $res = eval {
	    $self->create({ objects => [[$path, $type, $metadata, scalar read_file($local_file) ]],
				overwrite => ($overwrite ? 1 : 0) });
	};
	if ($@)
	{
	    die "Failure uploading $local_file: $@";
	}
	$obj = $res->[0];
    }
    return $obj;
}

sub opendir
{
    my($self, $path) = @_;

    my $res = $self->ls({paths => [$path]});
    my $info = $res->{$path};
    if ($info)
    {
	#
	# Need to treat root path names differently than others
	# because it lists workspaces (/username/workspacename)
	# and not the visible usernames as one might expect.
	# Here we are modeling a file hierarchy so an opendir
	# on / should return the user names that are visible.
	#

	if ($path =~ m,^/+$,)
	{
	    #
	    # We need to manipulate the output here to force everything
	    # to folders named with the username; we also need to make
	    # that list of usernames unique.
	    #
	    # Perms are all 'r' as one cannot create a user.
	    #

	    my %users = map { my $n = $_->[2]; $n =~ s,^/,,; $n =~ s,/$,,; ($n => $_->[3]) } @$info;
	    $info = [ map { [$_, 'folder', '/', $users{$_}, undef, $_, 0, {}, {}, 'r', 'r', '' ]} sort keys %users];
	}
	return [$info, 0];
    }
}

sub readdir
{
    my($self, $handle, $details) = @_;
    if (wantarray)
    {
	my $contents = $handle->[0];
	my $idx = $handle->[1];
	return undef if $idx >= @$contents;
	$handle->[1] = $#$contents;
	return map { $details ? $_ : $_->[0] } @$contents[$idx..$#$contents];
    }
    else
    {
	my $idx = $handle->[1]++;
	return $details ? $handle->[0]->[$idx] : $handle->[0]->[$idx]->[0];
    }
}

# my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
#            $atime,$mtime,$ctime,$blksize,$blocks)
#           = stat($filename);
#              0 dev      device number of filesystem
#              1 ino      inode number
#              2 mode     file mode  (type and permissions)
#              3 nlink    number of (hard) links to the file
#              4 uid      numeric user ID of file's owner
#              5 gid      numeric group ID of file's owner
#              6 rdev     the device identifier (special files only)
#              7 size     total size of file, in bytes
#              8 atime    last access time in seconds since the epoch
#              9 mtime    last modify time in seconds since the epoch
#             10 ctime    inode change time in seconds since the epoch (*)
#             11 blksize  preferred I/O size in bytes for interacting with the
#                         file (may vary from file to file)
#             12 blocks   actual number of system-specific blocks allocated
#                         on disk (often, but not always, 512 bytes each)

sub stat
{
    my($self, $path) = @_;
    my $res = eval { $self->get({ objects => [$path], metadata_only => 1 }); };

    return undef if $@ =~ /_ERROR_/ || !defined($res);

    my($obj_meta, $obj_data) = @{$res->[0]};
    return undef if @$obj_meta == 0;
    my($name, $type, $path, $ts, $oid, $owner, $size, $usermeta, $autometa,
       $user_perm, $global_perm, $shockurl) = @$obj_meta;


    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$atime,$mtime,$ctime,$blksize,$blocks);

    $mode = 0;
    if ($user_perm eq 'r') {
	$mode |= S_IRUSR;
    }
    if ($user_perm eq 'w' || $user_perm eq 'o') {
	$mode |= S_IWUSR | S_IRUSR;
    }
    if ($global_perm eq 'r') {
	$mode |= S_IROTH;
    }
    if ($global_perm eq 'w') {
	$mode |= S_IWOTH | S_IROTH;
    }

    if ($folder_types{$type}) {
	$mode |= S_IFDIR;
    }
    else
    {
	$mode |= S_IFREG;
    }

    if ($shockurl)
    {
	$dev = 'shock';
	$ino = $shockurl;
    }
    else
    {
	$dev = 'ws';
    }

    $uid = $owner;

    my @stat = ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks);
    if (wantarray)
    {
	return @stat;
    }
    else
    {
	return File::stat::populate(@stat);
    }
}

package Bio::P3::Workspace::ObjectMeta;
sub name { return $_[0]->[0] };
sub type { return $_[0]->[1] };
sub path { return $_[0]->[2] };
sub full_path { return join("", @{$_[0]}[2,0]); }
sub creation_time { return $_[0]->[3] };
sub id { return $_[0]->[4] };
sub owner { return $_[0]->[5] };
sub size { return $_[0]->[6] };
sub user_metadata { return $_[0]->[7] };
sub auto_metadata { return $_[0]->[8] };
sub user_permission { return $_[0]->[9] };
sub global_permission { return $_[0]->[10] };
sub shock_url { return $_[0]->[11] };
1;
