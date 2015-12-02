
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

my($opt, $usage) = Bio::P3::Workspace::ScriptHelpers::options("%c %o <name> <type> <filename>",[
	["permission|p", "Permissions for folders created"],
	["useshock|u", "Upload file to shock and store link in workspace"],
	["overwrite|o", "Overwirte existing destination object"],
]);

my $type = $ARGV[1];
my $filename = $ARGV[2];
my $data = undef;
if (!$opt->useshock) {
	open (my $fh, "<", $filename);
	$data = "";
	while (my $line = <$fh>) {
	    $data .= $line;
	}
	close($fh);
}
my $paths = Bio::P3::Workspace::ScriptHelpers::process_paths([$ARGV[0]]);
my $res = Bio::P3::Workspace::ScriptHelpers::wscall("create",{
	objects => [[$paths->[0],$type,{},$data]],
	permission => $opt->permission,
	overwrite => $opt->overwrite,
	createUploadNodes => $opt->useshock
});

if ($opt->useshock) {
	local $HTTP::Request::Common::DYNAMIC_FILE_UPLOAD = 1;
	my $ua = LWP::UserAgent->new();
	my $item = $res->[0];
	my $shock_url = $item->[11];
	my $req = HTTP::Request::Common::POST($shock_url, 
					  Authorization => "OAuth " . Bio::P3::Workspace::ScriptHelpers::token(),
					  Content_Type => 'multipart/form-data',
					  Content => [upload => [$filename]]);
    $req->method('PUT');
    my $sres = $ua->request($req);
    print Data::Dumper->Dump([$sres]);
}

print "File created:\n";
Bio::P3::Workspace::ScriptHelpers::print_wsmeta_table($res,$opt->useshock);




