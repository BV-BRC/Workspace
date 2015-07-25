package Bio::P3::Workspace::ScriptHelpers;
use strict;
use warnings;
use Getopt::Long::Descriptive;
use Data::Dumper;
use Text::Table;
use JSON::XS;
use HTTP::Request::Common;
use LWP::UserAgent;
use Bio::P3::Workspace::WorkspaceClient;
use Bio::P3::Workspace::WorkspaceClientExt;
use Bio::ModelSEED::ProbModelSEED::ProbModelSEEDClient;

our $defaultWSURL   = "http://p3.theseed.org/services/Workspace";
our $defaultAPPURL = "http://p3.theseed.org/services/app_service";
our $defaultMSURL = "https://p3.theseed.org/services/ProbModelSEED";
our $overrideWSURL = undef;
our $adminmode = undef;

=head3 options
Definition:
	void Bio::P3::Workspace::ScriptHelpers::options(string,[]);
Description:
	Returns usage and options and handles standard options and help

=cut
sub options {
    my($use,$opts) = @_;
    push(@{$opts},["wsurl=s", 'Workspace URL']);
    push(@{$opts},["admin|a", "Run as administrator"]);
    push(@{$opts},["help|h", "Show this usage message"]);
    my($opt, $usage) = describe_options($use,@{$opts});
	print($usage->text), exit if $opt->help;
	if ($opt->wsurl) {
		$overrideWSURL = $opt->wsurl;
	}
	if ($opt->admin) {
		$adminmode = 1;
	}
	return ($opt, $usage);
}

=head3 print_wsmeta_table
Definition:
	void Bio::P3::Workspace::ScriptHelpers::print_wsmeta_table([]);
Description:
	Prints the workspace meta table to file

=cut
sub print_wsmeta_table {
	my($objs,$shock) = @_;
	my $tbl = [];   
	for my $file (@$objs) {
		my($name, $type, $path, $created, $id, $owner, $size, $user_meta, $auto_meta, $user_perm,
		$global_perm, $shockurl) = @$file;
		push(@$tbl, [$name, $owner, $type, $created, $size, $user_perm, $global_perm, ($shock ? $shockurl  : ())]);
	}
	my $table = Text::Table->new(
		"Name","Owner","Type","Moddate","Size","User perm","Global perm", ($shock ? "Shock URL" : ())
	);
	$table->load(@{$tbl});
	print $table."\n";
}

=head3 ConfigFilename
Definition:
	void Bio::P3::Workspace::ScriptHelpers::ConfigFilename;
Description:
	Returns the filename where the config file is currently stashed

=cut
sub ConfigFilename {
    my $filename = glob "~/.patric_config";
    if (defined($ENV{ P3_CLIENT_CONFIG })) {
    	$filename = $ENV{ P3_CLIENT_CONFIG };
    } elsif (defined($ENV{ HOME })) {
    	$filename = $ENV{ HOME }."/.patric_config";
    }
   	return $filename;
}

=head3 GetConfigs
Definition:
	void Bio::P3::Workspace::ScriptHelpers::GetConfigs;
Description:
	Loads the local config file if it exists, and creates default config file if not

=cut
sub GetConfigs {
    my $filename = ConfigFilename();
    my $c;
    if (!-e $filename) {
    	SetDefaultConfig("P3Client");
    }
	$c = Config::Simple->new( filename => $filename);
    if (!defined($c->param("P3Client.wsurl")) || length($c->param("P3Client.wsurl")) == 0 || $c->param("P3Client.wsurl") =~ m/ARRAY/) {
    	SetDefaultConfig("P3Client");
    	$c = GetConfigs();
    }
    return $c;
}

=head3 GetConfigParam
Definition:
	string = Bio::P3::Workspace::ScriptHelpers::GetConfigParam;
Description:
	Returns a single config parameter

=cut
sub GetConfigParam {
	my($param) = @_;
	my $c = GetConfigs();
    return $c->param($param);
}

=head3 SetDefaultConfig
Definition:
	void Bio::P3::Workspace::ScriptHelpers::SetDefaultConfig;
Description:
	Sets default configurations using parameters specified in ScriptConfig

=cut
sub SetDefaultConfig {
	my($class) = @_;
	my $filename = ConfigFilename();
    my $c;
    if (-e $filename) {
    	$c = Config::Simple->new( filename => $filename);
    } else {
	    $c = Config::Simple->new( syntax => 'ini');
    }
    if ($class eq "P3Client") {
		$c->set_block('P3Client', {
			wsurl => $Bio::P3::Workspace::ScriptHelpers::defaultWSURL,
			appurl => $Bio::P3::Workspace::ScriptHelpers::defaultAPPURL		
		});
	}
    $c->write($filename);
}

=head3 SetConfig
Definition:
	void Bio::P3::Workspace::ScriptHelpers::SetConfig;
Description:
	Sets specified parameters to the specified values

=cut
sub SetConfig {
    my($params) = @_;
    my $c = GetConfigs();
	$c->autosave( 0 ); # disable autosaving so that update is "atomic"
	for my $key (keys(%{$params})) {
	    unless ($key =~ /^[a-zA-Z]\w*$/) {
			die "Parameter key '$key' is not a legitimate key value";
	    }
	    unless ((ref $params->{$key} eq '') ||
		    (ref $params->{$key} eq 'ARRAY')) {
			die "Parameter value for $key is not a legal value: ".$params->{$key};
	    }
    	my $fullkey = "P3Client." . $key;
    	if (! defined($params->{$key})) {
			if (defined($c->param($fullkey))) {
			    $c->delete($fullkey);
			}
	    } else {
			$c->param($fullkey, $params->{$key});
	    }
	}
	$c->save(ConfigFilename());
	chmod 0600, ConfigFilename();  
}

sub wsURL {
	my $newUrl = shift;
	my $currentURL;
	if (defined($newUrl)) {
		if ($newUrl eq "default") {
			$newUrl = $Bio::P3::Workspace::ScriptHelpers::defaultWSURL;
		}
		Bio::P3::Workspace::ScriptHelpers::SetConfig({wsurl => $newUrl});
		$currentURL = $newUrl;
	} else {
		if (defined($overrideWSURL)) {
			return $currentURL;
		}
		$currentURL =Bio::P3::Workspace::ScriptHelpers::GetConfigParam("P3Client.wsurl");
	}
	return $currentURL;
}

sub msurl {
	my $newUrl = shift;
	my $currentURL;
	if (defined($newUrl)) {
		if ($newUrl eq "default") {
			$newUrl = $Bio::P3::Workspace::ScriptHelpers::defaultMSURL;
		}
		Bio::P3::Workspace::ScriptHelpers::SetConfig({msurl => $newUrl});
		$currentURL = $newUrl;
	} else {
		if (defined($overrideWSURL)) {
			return $currentURL;
		}
		$currentURL =Bio::P3::Workspace::ScriptHelpers::GetConfigParam("P3Client.msurl");
	}
	return $currentURL;
}

sub appurl {
	my $newUrl = shift;
	my $currentURL;
	if (defined($newUrl)) {
		if ($newUrl eq "default") {
			$newUrl = $Bio::P3::Workspace::ScriptHelpers::defaultAPPURL;
		}
		Bio::P3::Workspace::ScriptHelpers::SetConfig({appurl => $newUrl});
		$currentURL = $newUrl;
	} else {
		if (defined($overrideWSURL)) {
			return $currentURL;
		}
		$currentURL =Bio::P3::Workspace::ScriptHelpers::GetConfigParam("P3Client.appurl");
	}
	return $currentURL;
}

sub process_paths {
	my $paths = shift;
	for (my $i=0; $i < @{$paths}; $i++) {
		if ($paths->[$i] !~ /^\// && $paths->[$i] !~ /^PATRICSOLR/) {
			$paths->[$i] = Bio::P3::Workspace::ScriptHelpers::directory().$paths->[$i];
		}
	}
	return $paths;
}

sub wscall {
	my $command = shift;
	my $params = shift;
	if (defined($adminmode)) {
		$params->{adminmode} = $adminmode;
	}
	my $output;
	eval {
		$output = Bio::P3::Workspace::ScriptHelpers::wsClient()->$command($params);
    };
    if ($@) {
		warn "Error running $command\n$@\n";
    }
	return $output;
}

sub directory {
	my $newdir = shift;
	my $current;
	if (defined($newdir)) {
		if ($newdir !~ m/\/$/) {
			$newdir .= "/";
		}
		Bio::P3::Workspace::ScriptHelpers::SetConfig({wsdir => $newdir});
		$current = $newdir;
	} else {
		$current =Bio::P3::Workspace::ScriptHelpers::GetConfigParam("P3Client.wsdir");
	}
	return $current;
}

sub login {
	my $params = shift;
	my $url = "http://tutorial.theseed.org/Sessions/Login";
	my $content = {
		user_id => $params->{user_id},
		password => $params->{password},
		status => 1,
		cookie => 1,
		fields => "name,user_id,token"
	};
	if ($params->{user_id} =~ m/^(.+)\@patricbrc\.org$/) {
		$url = "https://user.patricbrc.org/authenticate";
		$content = { username => $1, password => $params->{password} };
	}
	my $ua = LWP::UserAgent->new();
	my $res = $ua->post($url,$content);
	if (!$res->is_success) {
    	Bio::P3::Workspace::ScriptHelpers::SetConfig({
			token => undef,
			user_id => undef
		});
		return undef;
	}
	my $token;
	if ($params->{user_id} =~ m/^(.+)\@patricbrc\.org$/) {
		$token = $res->content;
	} else {
		my $data = decode_json $res->content;
		$token = $data->{token};
	}
	Bio::P3::Workspace::ScriptHelpers::SetConfig({
		token => $token,
		user_id => $params->{user_id},
		password => undef
	});
	return $token;
}

sub logout {
	Bio::P3::Workspace::ScriptHelpers::SetConfig({
		token => undef,
		user_id => undef
	});
}

sub msClient {
	my $url = shift;
	if (!defined($url)) {
		$url = msurl();
	}
	if ($url eq "impl") {
		require "Bio/ModelSEED/ProbModelSEED/ProbModelSEEDImpl.pm";
		$ENV{KB_DEPLOYMENT_CONFIG} = "/Users/chenry/code/ProbModelSEED/configs/test.cfg";
		$Bio::ModelSEED::ProbModelSEED::Service::CallContext = Bio::ModelSEED::ProbModelSEED::Service::CallContext->new(Bio::P3::Workspace::ScriptHelpers::token(),"unknown",Bio::P3::Workspace::ScriptHelpers::user());
		my $client = Bio::ModelSEED::ProbModelSEED::ProbModelSEEDImpl->new();
		return $client;
	}
	return Bio::ModelSEED::ProbModelSEED::ProbModelSEEDClient->new($url,token => Bio::P3::Workspace::ScriptHelpers::token());
}

sub wsClient {
	my $url = shift;
	if (!defined($url)) {
		$url = wsURL();
	}
	if ($url eq "impl") {
		eval {
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
			
			my $ctxone = Bio::P3::Workspace::ServiceContext->new(Bio::P3::Workspace::ScriptHelpers::token(),"unknown",Bio::P3::Workspace::ScriptHelpers::user());
			require "Bio/P3/Workspace/WorkspaceImpl.pm";
			return Bio::P3::Workspace::WorkspaceImpl->new();
		};
	}
	return Bio::P3::Workspace::WorkspaceClientExt->new($url,token => Bio::P3::Workspace::ScriptHelpers::token());
}

sub token {
	Bio::P3::Workspace::ScriptHelpers::GetConfigParam("P3Client.token");
} 

sub user {
	Bio::P3::Workspace::ScriptHelpers::GetConfigParam("P3Client.user_id");
}

{
	package Bio::ModelSEED::ProbModelSEED::Service::CallContext;
	
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
	sub log_debug {
		my($self,$msg) = @_;
		print STDERR $msg."\n";
	}
}

1;
