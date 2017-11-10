#!/usr/bin/env perl
########################################################################
# Modified version of the original kbase-login.pl script in the kbase workspace
# service git module. Adapted to work with updated Bio::KBase::Auth* libraries
# and added into the main auth repo.  Steve Chan sychan@lbl.gov
# 
# Authors: Christopher Henry, Scott Devoid, Paul Frybarger
# Contact email: chenry@mcs.anl.gov
# Development location: Mathematics and Computer Science Division, Argonne National Lab
########################################################################                                                                                                                                     
use strict;
use warnings;
use Term::ReadKey;
use Bio::P3::Workspace::ScriptHelpers; 

#Defining usage and options
my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options(
	"$0 <Username> %o\nAcquire a PATRIC authentication token for the username specified. " .
    "Prompts for password if not specified on the command line. " . 
    "Upon successful login the token will be placed in the INI format file " .
    Bio::P3::Workspace::ScriptHelpers::ConfigFilename() .
    " and used by default for PATRIC clients that require authentication.",[
	[ 'password|p:s', 'User password' ]
]);

my $pswd;
if (defined($opt->{password})) {
	$pswd = $opt->{password};
} else {
	$pswd = get_pass();
}
my $token = Bio::P3::Workspace::ScriptHelpers::login({
	user_id => $ARGV[0], password => $pswd
});
if (!defined($token)) {
	print "Login failed. Now logged in as:\npublic\n";
} else {
	print "Login successful. Now logged in as:\n".$ARGV[0]."\n";
}

sub get_pass {
    my $key  = 0;
    my $pass = ""; 
    print "Password: ";
    ReadMode(4);
    while ( ord($key = ReadKey(0)) != 10 ) {
        # While Enter has not been pressed
        if (ord($key) == 127 || ord($key) == 8) {
            chop $pass;
            print "\b \b";
        } elsif (ord($key) < 32) {
            # Do nothing with control chars
        } else {
            $pass .= $key;
            print "*";
        }
    }
    ReadMode(0);
    print "\n";
    return $pass;
}
