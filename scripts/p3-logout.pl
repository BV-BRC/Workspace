#!/usr/bin/env perl
########################################################################
# Adapted from original kbws-logout.pl script from kbase workspace module
# Clears the auth_token and user_id fields from the ~/.kbase_config file
# (or whatever file Bio::KBase::Auth determines is the config file path)
# Steve Chan sychan@lbl.gov
#
# original headers follow:
# Authors: Christopher Henry, Scott Devoid, Paul Frybarger
# Contact email: chenry@mcs.anl.gov
# Development location: Mathematics and Computer Science Division, Argonne National Lab
########################################################################
use strict;
use warnings;
use Bio::P3::Workspace::ScriptHelpers; 

#Defining usage and options
my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("$0 %o\nClears any kbase authentication tokens from the INI file so that you are logged out. Takes no options, and does not complain if you don't have a token set.",[]);
Bio::P3::Workspace::ScriptHelpers::logout();
print "Logged in as:\npublic\n";

