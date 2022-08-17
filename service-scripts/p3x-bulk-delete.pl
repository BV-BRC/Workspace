use Data::Dumper;
use strict;
use MongoDB::Connection;
use File::Path 'remove_tree';
use Bio::P3::DeploymentConfig;
use Getopt::Long::Descriptive;

my($opt, $usage) = describe_options("%c %o owner workspace path",
				    ["execute", "Perform the deletion"],
				    ["help|h", "Show this help message"]);

print($usage->text), exit 0 if $opt->help;
die($usage->text) if @ARGV != 3;

my $owner = shift;
my $ws = shift;
my $path = shift;

$owner ne '' or die "Owner may not be empty\n";
$ws ne '' or die "Workspace may not be empty\n";
$path ne '' or die "Path may not be empty\n";

my $cfg = Bio::P3::DeploymentConfig->new("Workspace");

my $data_dir = '/disks/shock/Shock/data';

my $shock_mongo = MongoDB::Connection->new(host => 'fir.mcs.anl.gov', 
						port => 27018,
						db_name => 'HemlockShock');
$shock_mongo or die "error connecting\n";
my $db = $shock_mongo->get_database('HemlockShock');
my $col = $db->get_collection('Nodes');

my %users;
my $users = $db->get_collection('Users')->find({});
while (my $u = $users->next)
{
    $users{$u->{uuid}} = $u;
}

my $ws_mongo = MongoDB::Connection->new(host => $cfg->setting("mongodb-host"),
					db_name => $cfg->setting("mongodb-database"),
					username => $cfg->setting("mongodb-user"),
				        password => $cfg->setting("mongodb-pwd"));
$ws_mongo or die "Error connecting to WS mongo";

my $ws_col = $ws_mongo->get_database($cfg->setting("mongodb-database"))->get_collection("workspaces");
my $obj_col = $ws_mongo->get_database($cfg->setting("mongodb-database"))->get_collection("objects");

my $q = { owner => $owner, name => $ws };
print Dumper($q);
my $res = $ws_col->find($q);
#print Dumper($res);
my $ws_id;
while (my $ent = $res->next())
{
    if (defined($ws_id))
    {
	die "non-unique query '$owner' '$ws'\n";
    }
    $ws_id = $ent->{uuid};
}
print "WS $ws_id\n";
if (!$ws_id)
{
    die "No workspace found for owner $owner name $ws\n";
}
my $do_query = sub {
    print "qry path=$path ws=$ws_id\n";
    return $obj_col->find({path => qr/^$path/, workspace_uuid => $ws_id, shock => 1,
#				   size => {'$gt' => 1_000_000 },
		    });
};


my $total = 0;

my $file_res = $do_query->();
while (1)
{
    my $ent = eval { $file_res->next; };
    if ($@)
    {
	if ($@ =~ /cursor not found/)
	{
	    $file_res = $do_query->();
	    next;
	}
	else
	{
	    die $@;
	}
    }
#     print Dumper(ENT=>$ent);
    last unless $ent;
    
    my($_id, $uuid, $size, $shocknode, $type, $path, $name) =
	@{$ent}{qw(_id uuid size shocknode type path name)};
    my($id) = $shocknode =~ m,/node/([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})$,i;

    eval {
	ref($_id) or die "id not a ref\n";
	
	$id  or die "No id found in '$shocknode'\n";
	$uuid or die "No uuid $uuid\n";
	
	$total += $size;
	print join("\t", $uuid, $size, $id, $name, $type, $path), "\n";
	
	
	# Shock lookup
	
	my $node = $col->find_one({id => $id});
	if (!$node)
	{
	    warn "Not found: ", join("\t", $uuid, $size, $id, $name, $type, $path),  "\n";
	    next;
	}
	
	# Validate
	
	if (0)
	{
	    my $virt = $col->find_one({"file.virtual_parts" => $id});
	    if ($virt)
	    {
		warn "node is referenced by virtual node \n";
		next;
	    }
	}
	
	my $path = get_path($id);
	my $data_file = "$path/$id.data";
	#    if (! -f $data_file)
	#    {
	#	warn "No $data_file\n";
	#    }
	
	if (0)
	{
	    my $dups = $col->find({"file.path" => $data_file});
	    my @dups;
	    while (my $n = $dups->next)
	    {
		push(@dups, $n);
	    }
	    if (@dups)
	    {
		warn "skipping dups for $id\n";
		next;
	    }
	}
	
	my $owner = $users{$node->{acl}->{owner}};
	print "$path\t$node->{file}->{name}\t$owner->{username}\n";
	# print "    $node->{attributes}->{app_id}\t$node->{attributes}->{task_file_id}\n";
	#system("ls", "-l", $data_file);
	
	my $err;
	my $res;
	# system("du", "-hs", $path);
	
	if ($opt->execute)
	{
	    my $ret = remove_tree($path, { verbose => 0, safe => 1, error => \$err, result => \$res});
	    if ($err && @$err)
	    {
		die "error on remove: @$err\n";
	    }
	    if ($ret == 0)
	    {
		print "Did not remove any files\n";
		next;
	    }
	    print "Removed: $ret\n";
	}
	else
	{
	    print "Would remove $path\n";
	}
	
	if ($opt->execute)
	{
	    my $result = $col->remove({id => $id}, { safe => 1});
	    if (!$result->{ok} || $result->{n} != 1)
	    {
		die "Remove failed at line $. $_: " . Dumper($result);
	    }
	    
	    my $res = $obj_col->remove({_id => $_id}, { safe => 1});
	    # print "Deleted $res->{n} from objects\n";
	    die if $res->{n} > 1;
	}
	else
	{
	    print "Would remove shock $id and ws $_id\n";
	}
	print "cur total " . $total / 1e9 . "\n";
    };
    if ($@)
    {
	print "Skip $uuid $path $name due to eval error: $@";
    }
}
	
    
    
    
sub get_path
{
    my($id) = @_;
    my $path = join("/", $data_dir, substr($id, 0, 2), substr($id, 2, 2), substr($id, 4, 2), $id);
    return $path;
}

