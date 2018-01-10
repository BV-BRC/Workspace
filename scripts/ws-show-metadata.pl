
use strict;
use Bio::P3::Workspace::ScriptHelpers;
use LWP::UserAgent;
use Text::Table;
use Data::Dumper;

=head1 NAME

ws-show-metadata

=head1 SYNOPSIS

ws-show-metadata path [path...]

=head1 DESCRIPTION

Show the workspace metadata for the given paths.

=head1 COMMAND-LINE OPTIONS

ws-cat.pl [-h] [long options...] path [path...]
	--url       Service URL
	-h --help   Show this usage message
=cut

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o path [path...]",[
]);
my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths([@ARGV]);
my $res = Bio::P3::Workspace::ScriptHelpers::wscall("get",{ objects => $paths, metadata_only => 1 });

my $tb = Text::Table->new("Name", "Type", "Path", "Timestamp", "Object ID", "Owner", "Size", "User\nPerm", "Global\nPerm", "Shock\nURL");
for my $ent (@$res)
{
    my($meta) = @$ent;
    my($name, $type, $path, $ts, $id, $owner, $size, $user_meta, $auto_meta,
       $user_perm, $global_perm, $shock_url) = @$meta;
    $tb->load([$name, $type, $path, $ts, $id, $owner, $size, $user_perm, $global_perm, $shock_url]);
}
print $tb;
