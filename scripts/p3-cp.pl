use strict;
use Bio::P3::Workspace::WorkspaceClientExt;
use P3AuthToken;
use Getopt::Long;
use Data::Dumper;
use Date::Parse;
use File::Basename;
use Pod::Usage;

=head1 Copy files between local computer and PATRIC workspace

    p3-cp [options] source_file target_file
    p3-cp [options] source_file ... target_directory
    p3-cp -R [options] source_file ... target_directory

In the first form, copy source_file to target_file. Here, neither parameter may be a directory.

In the second form, copy all source_file items to target_directory.

In the third form, recursively copy all source_file items to target_directory.

Source and destination file and directories may either be files local 
to the current computer or in the PATRIC workspace. Names in the workspace
are denoted with a ws: prefix.

=head1 Usage synopsis

    p3-cp [options] source dest
    p3-cp [options] source... directory
    p3-cp [options] -t directory source...

Copy source to dest, or multiple source(s) to directory.

Source and destination file and directories may either be files local 
to the current computer or in the PATRIC workspace. Names in the workspace
are denoted with a ws: prefix.

The following options may be provided:

    -r or --recursive	           	If source is a directory, copies the directory and its contents.
				   	If source ends in /, copy the contents of the directory.
    -p or --workspace-path-prefix STR	Prefix for relative workspace pathnames specified with ws: 
    -f or --overwrite			If a file to be uploaded already exists, overwrite it.
    -m or --map-suffix suffix=type	When copying to workspace, map a file with the given
    					suffix to the given type.
    -t or --default-type TYPE		If no other type is defined, use the given type as the default
    --creation-date STR			If copying to the workspace, set the creation date to the given date.
    
=cut

my %suffix_map = ("fa" => "reads",
		  "fasta" => "reads",
		  "fq" => "reads",
		  "fastq" => "reads",
		  "fq.gz" => "reads",
		  "fastq.gz" => "reads",
		  "tgz" => "tar_gz",
		  "tar.gz" => "tar_gz",
		  "fna" => "contigs",
		  "faa" => "feature_protein_fasta",
		  "txt" => "txt",
		  "html" => "html",
		 );


my $workspace_path_prefix;
my $recursive;
my $overwrite;
my $admin;
my $default_type;
my $creation_epoch;

my @sources;
my $dest;


my $token = P3AuthToken->new();
if (!$token->token())
{
    die "You must be logged in to PATRIC via the p3-login command to use p3-cp.\n";
}
my @paths;

my $ws = Bio::P3::Workspace::WorkspaceClientExt->new();

GetOptions("workspace-path-prefix|p=s" => \$workspace_path_prefix,
	   "overwrite|f" => \$overwrite,
	   "recursive|r" => \$recursive,
	   "target|t" => \$dest,
	   "map-suffix|m=s\%" => \%suffix_map,
	   "default-type|T=s" => \$default_type,
	   "administrator|A" => \$admin,
	   "creation-date=s" => sub {
	       my $date = $_[1];
	       $creation_epoch = str2time($date);
	       if (!$creation_epoch)
	       {
		   die "Cannot parse creation date \"$date\"\n";
	       }
	   },
	   "url=s" => sub { $ws->{url} = $_[1]; },
	   "<>" => sub { process_pathname($_[0], $workspace_path_prefix, \@paths, $ws, $admin) },
	   "help|h" => sub {
	       print pod2usage(-sections => 'Usage synopsis', -verbose => 99, -exitval => 0);
	   },
	   );

if (@paths < 2)
{
    print pod2usage(-sections => 'Usage synopsis', -verbose => 99, -exitval => 1);
}



#
# Handle the three cases listed in the synopsis.
#

PROCESS:
{
    if ($recursive)
    {
	my $dest = pop(@paths);

	if (@paths == 1)
	{
	    my $src = $paths[0];
	    if (!$src->exists())
	    {
		die "Source path $src does not exist\n";
	    }
	    if ($src->is_dir() && $dest->is_file())
	    {
		die "Destination path $dest is not a directory\n";
	    }

	    if ($dest->is_dir())
	    {
		$dest = $dest->append(basename($src->path()));
	    }

	    do_copy_recursive($src, $dest, $creation_epoch);
	    last PROCESS;
	}
	
	if (!$dest->is_dir())
	{
	    die "Destination path $dest is not a directory\n";
	}
	for my $p (@paths)
	{
	    if (!$p->exists())
	    {
		warn "Source path $p does not exist\n";
		next;
	    }
	    do_copy_recursive($p, $dest, $creation_epoch);
	}
    }
    else
    {
	if (@paths == 2)
	{
	    my($src, $dest) = @paths;
	    
	    if (!$src->is_dir() && !$dest->is_dir())
	    {
		# case 1
		if ($src->path() eq $dest->path())
		{
		    warn "Not copying a file onto itself\n";
		}
		elsif (!$src->exists())
		{
		    warn "Source path $src does not exist\n";
		}
		elsif ($dest->exists() && !$overwrite)
		{
		    warn "Not overwriting existing path $dest\n";
		}
		else
		{
		    do_copy($src, $dest, $creation_epoch);
		}
		last PROCESS;
	    }
	}
	#
	# Case 2.
	#
	my $dest = pop(@paths);
	if (!$dest->exists())
	{
	    warn "Destination path $dest does not exist\n";
	    last PROCESS unless $admin;
	}
	if (!$dest->is_dir())
	{
	    warn "Destination path $dest is not a directory\n";
	    last PROCESS;
	}
	for my $p (@paths)
	{
	    if (!$p->exists())
	    {
		warn "Source path $p does not exist\n";
		next unless $admin;
	    }
	    if ($p->is_dir())
	    {
		warn "Source path $p is a directory and -R was not specified\n";
		next;
	    }
	    do_copy($p, $dest->append(basename($p->path())), $creation_epoch);
	}
    }
}

sub do_copy
{
    my($src, $dest, $creation_date) = @_;
    # print "Copy $src => $dest\n";

    $src->copy_to($dest, $creation_date);
}

#
# Copy src to dest, recursively.
# If src and dest are not the same type (file/dir), fail
#
sub do_copy_recursive
{
    my($src, $dest) = @_;
    # print "Copy recursive $src => $dest\n";

    if ($src->is_file())
    {
	if ($dest->exists() && !$dest->is_file())
	{
	    warn "Cannot overwrite $dest with $src\n";
	    return;
	}
	do_copy($src, $dest);
    }
    elsif ($src->is_dir())
    {
	if ($dest->is_file())
	{
	    warn "Cannot overwrite $dest with $src\n";
	    return;
	}
	if (!$dest->exists())
	{
	    $dest->mkdir();
	}
	
	my $dh = $src->opendir();
	$dh or die "Opendir $src failed\n";
	while (defined(my $p = $dh->read()))
	{
	    next if $p eq '.' || $p eq '..';
	    do_copy_recursive($src->append($p), $dest->append($p));
	}
    }
}

sub process_pathname
{
    my($path, $ws_prefix, $path_list, $ws, $admin) = @_;
    my $wspath;
    my $item;
    if ($path =~ /^ws:(.*)/)
    {
	$wspath = $1;
	if ($wspath !~ m,^/,)
	{
	    if (!$ws_prefix)
	    {
		die "Cannot process $path: no workspace path prefix set (--workspace-path-prefix parameter)\n";
	    }
	    $wspath = $ws_prefix . "/" . $wspath;
	}
	$item = new WsFile($wspath, $ws, $admin);
    }
    else
    {
	$item = new LocalFile($path, $ws);
    }
    push(@$path_list, $item);
}

package FileWrapper;
use strict;
use Fcntl ':mode';
sub new
{
    my($class, $path, $ws, $admin) = @_;
    my $self = {
	path => $path,
	ws => $ws,
	admin => $admin,
    };
    return bless $self, $class;
}
sub ws { return $_[0]->{ws}; }
sub admin { return $_[0]->{admin}; }

#
# Create a new wrapper with an extended path.
#
sub append
{
    my($self, $path) = @_;
    my $new = bless { %$self }, ref $self;
    $new->{path} = $self->{path} . "/" . $path;
    delete $new->{stat};
    return $new;
}
     

sub path
{
    my($self) = @_;
    return $self->{path};
}

sub exists
{
    my($self) = @_;
    my $s = $self->stat();
    return defined $s;
}

sub is_file
{
    my($self) = @_;
    my $s = $self->stat();
    return $s && S_ISREG($s->mode);
}

sub is_dir
{
    my($self) = @_;
    my $s = $self->stat();
    return $s && S_ISDIR($s->mode);
}

package LocalFile;

use strict;
use base 'FileWrapper';
use File::stat qw();
use DirHandle;

use overload '""' => sub { $_[0]->{path} };

sub stat
{
    my($self) = @_;
    return $self->{stat} if $self->{stat};
    my $s = File::stat::stat($self->{path});
    $self->{stat} = $s;
    return $s;
}

sub opendir
{
    my($self) = @_;

    return new DirHandle($self->path);
}

sub mkdir
{
    my($self) = @_;
    print "mkdir $self->{path}\n";
    mkdir($self->{path}) or die "Cannot mkdir $self->{path}: $!";
}

#
# Copy myself to dest.
#
sub copy_to
{
    my($self, $dest, $creation_date) = @_;

    if ($dest->exists() && !$overwrite)
    {
	warn "Not overwriting existing file $dest\n";
	return;
    }

    if (ref($dest) eq 'WsFile')
    {
	my($suffix) = $self->{path} =~ /\.([^.]+)$/;
	my $type = $suffix_map{$suffix};
	if (!$type)
	{
	    for my $suffix (grep { /\./ } keys %suffix_map)
	    {
		if ($self->{path} =~ /\.$suffix$/)
		{
		    $type = $suffix_map{$suffix};
		    last;
		}
	    }
	}
		
	$type //= $default_type;
	$type //= "unspecified";
	print "Copy $self to $dest with type=$type\n";
	my $res;
	eval {
	    my $shock = (-s $self->{path}) > 5000 ? 1 : 0;
	    $res = $self->ws->save_file_to_file($self->{path}, {}, $dest->path(),
						$type, $overwrite, $shock, $token->token(), $admin, $creation_date);
	};

	if ($@)
	{
	    my $err = $@;
	    if ($err =~ /_ERROR_(.*)_ERROR_/)
	    {
		$err = $1;
	    }
	    warn "Failure uploading $self to $dest: $err\n";
	}
	delete $dest->{stat};
    }
    else
    {
	system("cp", "$self", "$dest");
    }
	
}

package WsFile;

use strict;
use Data::Dumper;
use base 'FileWrapper';
use overload '""' => sub { "ws:" . $_[0]->{path} };

sub stat
{
    my($self) = @_;
    return $self->{stat} if $self->{stat};
    my $s = $self->{ws}->stat($self->{path}, $self->admin);
    $self->{stat} = $s;
    return $s;
}

sub opendir
{
    my($self) = @_;

    return new WsDirHandle($self->ws, $self->path);
}

sub mkdir
{
    my($self) = @_;
    eval {
	$self->ws->create({ objects => [[$self->{path}, 'folder']] });
    };
    if ($@)
    {
	my ($err) = $@ =~ /_ERROR_(.*)_ERROR_/;
	die "Error creating directory  $self->{path}: $err\n";
    }
}

#
# Copy myself to dest.
#
sub copy_to
{
    my($self, $dest, $creation_date) = @_;

    my $opts;
    $opts->{admin} = 1 if $admin;

    print "Copy $self to $dest\n";
    if (ref($dest) eq 'WsFile')
    {
	eval {
	    $self->ws->copy({ objects => [[$self->path(), $dest->path()]],
				  overwrite => ($overwrite ? 1 : 0),
			      adminmode => ($admin ? 1 : 0)});
	};
	if ($@)
	{
	    my ($err) = $@ =~ /_ERROR_(.*)_ERROR_/;
	    die "Error copying $self to $dest: $err\n";
	}
    }
    else
    {
	open(OUT, ">", $dest->path()) or die "Cannot open $dest for writing: $!\n";
	$self->ws->copy_files_to_handles(1, $token->token(), [[$self->path(), \*OUT]],
					$opts);
	close(OUT);
    }
	
}

package WsDirHandle;
use strict;
sub new
{
    my($class, $ws, $path) = @_;
    my $self = {
	ws => $ws,
	path => $path,
    };

    eval
    {
	my $dh = $ws->opendir($path, $admin);
	$self->{dh} = $dh;
    };
    if ($@)
    {
	warn "Opendir $path failed\n";
	return undef;
    }
    return bless $self, $class;
}

sub read
{
    my($self) = @_;
    return $self->{ws}->readdir($self->{dh});
}
