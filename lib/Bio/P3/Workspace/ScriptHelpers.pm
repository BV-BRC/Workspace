package Bio::P3::Workspace::ScriptHelpers;
use strict;
use warnings;
use Bio::P3::Workspace::WorkspaceClient;

our $defaultWSURL   = "http://p3.theseed.org/services/Workspace";

=head3 ConfigFilename
Definition:
	void Bio::P3::Workspace::ScriptHelpers::ConfigFilename;
Description:
	Returns the filename where the config file is currently stashed

=cut
sub ConfigFilename {
    my $filename = glob "~/.kbase_config";
    if (defined($ENV{ KB_CLIENT_CONFIG })) {
    	$filename = $ENV{ KB_CLIENT_CONFIG };
    } elsif (defined($ENV{ HOME })) {
    	$filename = $ENV{ HOME }."/.kbase_config";
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
    	SetDefaultConfig("P3Workspace");
    }
	$c = Config::Simple->new( filename => $filename);
    if (!defined($c->param("P3Workspace.url")) || length($c->param("P3Workspace.url")) == 0 || $c->param("P3Workspace.url") =~ m/ARRAY/) {
    	SetDefaultConfig("P3Workspace");
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
    if ($class eq "P3Workspace") {
		$c->set_block('P3Workspace', {
			url => $Bio::P3::Workspace::ScriptHelpers::defaultWSURL		
		});
	} else {
		$c->set_block('P3Workspace', {
			url => $Bio::P3::Workspace::ScriptHelpers::defaultWSURL		
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
    	my $fullkey = "P3Workspace." . $key;
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
		Bio::P3::Workspace::ScriptHelpers::SetConfig({url => $newUrl});
		$currentURL = $newUrl;
	} else {
		$currentURL =Bio::P3::Workspace::ScriptHelpers::GetConfigParam("P3Workspace.url");
	}
	return $currentURL;
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
	return Bio::P3::Workspace::WorkspaceClient->new($url);
}

sub token {
	Bio::P3::Workspace::ScriptHelpers::GetConfigParam("authentication.token");
} 

sub user {
	Bio::P3::Workspace::ScriptHelpers::GetConfigParam("authentication.user_id");
}
1;