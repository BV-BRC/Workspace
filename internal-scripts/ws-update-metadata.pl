
use strict;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::WorkspaceImpl;

=head1 NAME

ws-update-metadata

=head1 SYNOPSIS

ws-update-metadata <filename> <script path> <data path> <url>

=head1 DESCRIPTION

Compute and load auto-metadata for object list

=head1 COMMAND-LINE OPTIONS

ws-update-metadata [-h] [long options...]
	-h --help   Show this usage message
	
=cut

my @options = (
	       ["help|h", "Show this usage message"],
	      );

my($opt, $usage) = describe_options("%c %o",
				    @options);

print($usage->text), exit if $opt->help;

my $directory = $ARGV[0];
my $url = $ARGV[1];
#Reading config file
my $config;
my $service = $ENV{KB_SERVICE_NAME};
if (!defined($service)) {
	$service = "Workspace";
}
if ((my $e = $ENV{KB_DEPLOYMENT_CONFIG}) && -e $ENV{KB_DEPLOYMENT_CONFIG}) {
	$config = Config::Simple->new();
	$config->read($e);
}
#Getting script path and data path
my $scriptpath = $config->param("$service.script-path");
my $datapath = $config->param("$service.db-path")."/P3WSDB/";
#Logging in workspace user
my $tokenObj = Bio::KBase::AuthToken->new(
	user_id => $config->param("$service.wsuser"), password => $config->param("$service.wspassword"),ignore_authrc => 1
);
#Creating workspace object
my $ws;
our $ctxtwo;
if ($url eq "impl") {
	$ctxtwo = Bio::P3::Workspace::ServiceContext->new($tokenObj->token(),"test",$config->param("$service.wsuser"));
	$Bio::P3::Workspace::Service::CallContext = $ctxtwo;
	$ws = Bio::P3::Workspace::WorkspaceImpl->new();
} else {
	$ws = Bio::P3::Workspace::WorkspaceClient->new($url,$tokenObj->token());
}
#Opening object file
open (my $fh,"<",$directory."/objects.json");
my $data;
while (my $line = <$fh>) {
	$data .= $line;	
}
close($fh);
my $JSON = JSON::XS->new->utf8(1);
my $objs = $JSON->decode($data);
#Iterating over objects and computing metadata
for (my $i=0; $i < @{$objs}; $i++) {
	if (-e $scriptpath."/ws-autometa-".$objs->[$i]->{type}.".pl") {
		if ($objs->[$i]->{shock} == 1 && $objs->[$i]->{size} > 0) {
			print 'curl -X GET -H "Authorization: OAuth '.$tokenObj->token().'" '.$objs->[$i]->{shocknode}.'?download > '.$directory.'/object.txt'."\n";
			system('curl -X GET -H "Authorization: OAuth '.$tokenObj->token().'" '.$objs->[$i]->{shocknode}.'?download > '.$directory.'/object.txt');
		} elsif ($objs->[$i]->{shock} == 0 && $objs->[$i]->{folder} == 0) {
			my $filename = $datapath."/".$objs->[$i]->{wsobj}->{owner}."/".$objs->[$i]->{wsobj}->{name}."/".$objs->[$i]->{path}."/".$objs->[$i]->{name};
			print "cp \"".$filename."\" \"".$directory."/object.txt\"\n";
			system("cp \"".$filename."\" \"".$directory."/object.txt\"");
		}
		if (-e $directory."/object.txt") {
			print "perl ".$scriptpath."/ws-autometa-".$objs->[$i]->{type}.".pl ".$directory."\n";
			system("perl ".$scriptpath."/ws-autometa-".$objs->[$i]->{type}.".pl ".$directory);
			open (my $fh,"<",$directory."/meta.json");
			my $data;
			while (my $line = <$fh>) {
				$data .= $line;	
			}
			close($fh);
			my $data = $JSON->decode($data);
			$ws->update_metadata({
				objects => [["/".$objs->[$i]->{wsobj}->{owner}."/".$objs->[$i]->{wsobj}->{name}."/".$objs->[$i]->{path}."/".$objs->[$i]->{name},$data]],
				autometadata => 1,
				adminmode => 1
			});
		}
	}
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