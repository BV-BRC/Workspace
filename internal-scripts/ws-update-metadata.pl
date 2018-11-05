
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::WorkspaceClientExt;
use Bio::P3::Workspace::WorkspaceImpl;
use File::Slurp;

use P3AuthLogin;

=head1 NAME

ws-update-metadata

=head1 SYNOPSIS

ws-update-metadata object-dir service-url

=head1 DESCRIPTION

Compute and load auto-metadata for object list

=head1 COMMAND-LINE OPTIONS

ws-update-metadata [-h] [long options...] object-dir service-url
	-h --help   Show this usage message
	
=cut

my @options = (
	       ["help|h", "Show this usage message"],
	      );

my($opt, $usage) = describe_options("%c %o object-dir service-url",
				    @options);

print($usage->text), exit if $opt->help;
die($usage->text) unless @ARGV == 2;

my $directory = $ARGV[0];
my $url = $ARGV[1];
#Reading config file
my $config;
my $service = $ENV{KB_SERVICE_NAME};
if (!defined($service))
{
    $service = "Workspace";
}

if ((my $e = $ENV{KB_DEPLOYMENT_CONFIG}) && -e $ENV{KB_DEPLOYMENT_CONFIG})
{
    $config = Config::Simple->new();
    $config->read($e);
}

#Getting script path and data path
my $scriptpath = $config->param("$service.script-path");
my $datapath = $config->param("$service.db-path")."/P3WSDB/";

#Logging in workspace user
my $token = P3AuthLogin::login_rast($config->param("$service.wsuser"), $config->param("$service.wspassword"));
$token or die "Failure logging in service user\n";

#Creating workspace object
my $ws;
our $ctxtwo;
if ($url eq "impl")
{
    $ctxtwo = Bio::P3::Workspace::ServiceContext->new($token,"test",$config->param("$service.wsuser"));
    $Bio::P3::Workspace::Service::CallContext = $ctxtwo;
    $ws = Bio::P3::Workspace::WorkspaceImpl->new();
}
else
{
	$ws = Bio::P3::Workspace::WorkspaceClient->new($url,$token);
}

#Opening object file
my $data = read_file("$directory/objects.json", err_mode => 'quiet');
$data or die "Cannot read $directory/objects.json: $!";

my $JSON = JSON::XS->new->utf8(1);
my $objs = $JSON->decode($data);

#Iterating over objects and computing metadata

my $obj_file = "$directory/object.txt";

for my $obj_rec (@$objs)
{
    my($obj, $script) = @$obj_rec;

    my $unlink = 0;

    my $obj_path = join("/",
			$obj->{wsobj}->{owner},
			$obj->{wsobj}->{name},
			$obj->{path},
			$obj->{name});
    
    if ($obj->{shock} == 1 && $obj->{size} > 0)
    {
	my $url = "$obj->{shocknode}?download";
	my $rc = system("curl",
			"-o", $obj_file,
			"--fail",
			"-X", "GET",
			"-H", "Authorization: OAuth $token",
			$url);
	if ($rc != 0)
	{
	    warn "Error downloading $url: $rc\n";
	    next;
	}
    }
    elsif ($obj->{shock} == 0 && $obj->{folder} == 0)
    {
	my $ws_file = join("/", $datapath, $obj_path);
	symlink($ws_file, $obj_file) or die "Cannot symlink $ws_file $obj_file: $!";
    }
    if (-f $obj_file)
    {
	print STDERR "Invoke $script on $obj_file for $obj_path\n";

	my $rc = system($script, $directory);
	if ($rc != 0)
	{
	    warn "Error $rc running $script on $obj_file  for $obj_path\n";
	    next;
	}
	my $data = read_file("$directory/meta.json", err_mode => 'quiet');
	if (!$data)
	{
	    warn "Cannot read generated $directory/meta.json: $!";
	    next;
	}
	my $metadata = eval { $JSON->decode($data); };
	if ($@)
	{
	    warn "Error parsing data from $directory/meta.json:\n$@";
	    next;
	}
	
	$ws->update_metadata({
	    objects => [["/obj_path", $data]],
	    autometadata => 1,
	    adminmode => 1
	    });
    }
}
continue
{
    unlink($obj_file);
    unlink("$directory/meta.json");
}
File::Path::rmtree($directory);

package Bio::P3::Workspace::ServiceContext;

use strict;

sub new {
    my($class,$token,$method,$user) = @_;
    my $self = {
        token => $token,
        method => $method,
        user_id => $user
    };
    return bless $self, $class;
}
sub user_id {
	my($self) = @_;
	return $self->{user_id};
}
sub token {
	my($self) = @_;
	return $self->{token};
}
sub method {
	my($self) = @_;
	return $self->{method};
}
