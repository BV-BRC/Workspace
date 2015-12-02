
use strict;
use Bio::P3::Workspace::ScriptHelpers;
=head1 NAME

ws-create

=head1 SYNOPSIS

ws-create ws-name

=head1 DESCRIPTION

Create a workspace

=head1 COMMAND-LINE OPTIONS

ws-create workspace [long options...]
	--url      URL to use for workspace service
	--help     print usage message and exit
	
=cut

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o <workspace>",[
	["perm|p=s", "permission to reset globally or for specific users"],
	["users|u=s", "; delimited list of users to set permissions for"],
]);
my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths([$ARGV[0]]);
if (defined($opt->{perm})) {
	my $perms = $opt->{perm};
	my $input = {
		path => $paths->[0]
	};
	if (defined($opt->{users})) {
		my $array = [split(/;/,$opt->{users})];
		for (my $i=0; $i < @{$array}; $i++) {
			push(@{$input->{permissions}},[$array->[$i],$perms]);
		}
	} else {
		$input->{new_global_permission} = $perms;
	}
	my $res = Bio::P3::Workspace::ScriptHelpers::wscall("set_permissions",$input);
	print Data::Dumper->Dump([$res]);
} else {
	my $res = Bio::P3::Workspace::ScriptHelpers::wscall("list_permissions",{objects => $paths});
	print Data::Dumper->Dump([$res->{$paths->[0]}]);
}