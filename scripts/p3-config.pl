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
my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o",[
	[ 'wsurl|w=s', 'URL for Workspace' ],
	[ 'msurl|m=s', 'URL for ProbModelSEED' ],
	[ 'appurl=s', 'URL for app service' ],
	[ 'print|p', 'Print the configuration' ],
]);
if (defined($opt->{wsurl})) {
	print "Resetting Workspace url:\n".$opt->{wsurl}."\n";
	Bio::P3::Workspace::ScriptHelpers::wsURL($opt->{wsurl});
}
if (defined($opt->{msurl})) {
	print "Resetting ProbModelSEED url:\n".$opt->{msurl}."\n";
	Bio::P3::Workspace::ScriptHelpers::msurl($opt->{msurl});
}
if (defined($opt->{appurl})) {
	print "Resetting app url:\n".$opt->{appurl}."\n";
	Bio::P3::Workspace::ScriptHelpers::appurl($opt->{appurl});
}
if (defined($opt->{print})) {
	print "wsurl:".Bio::P3::Workspace::ScriptHelpers::wsURL()."\n";
	print "appurl:".Bio::P3::Workspace::ScriptHelpers::appurl()."\n";
#	print "msurl:".Bio::P3::Workspace::ScriptHelpers::msurl()."\n";
}
exit 0;
