#!/usr/bin/env perl
########################################################################
# Simple script based on the kbase-login.pl template for looking up token
# and user name of the logged in user using the Bio::KBase::Auth* libraries.
# Michael Sneddon, mwsneddon@lbl.gov
########################################################################                                                                                                                                     
use strict;
use warnings;
use Bio::P3::Workspace::ScriptHelpers; 

#Defining usage and options
my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("$0 %o\nDetermine who you are logged in as.",[
	[ 'token|t', 'Print out user token instead of your user name.' ],
]);

if (defined(Bio::P3::Workspace::ScriptHelpers::token())) {
	if (defined($opt->{token})) {
		print Bio::P3::Workspace::ScriptHelpers::token()."\n";
	} else {
		print "You are logged in as:\n".Bio::P3::Workspace::ScriptHelpers::user()."\n";
	}
} else {
	print "You are not logged in.\n";
}

exit 0;
