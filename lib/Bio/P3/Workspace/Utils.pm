package Bio::P3::Workspace::Utils;

use Bio::KBase::AuthToken;
use Data::Dumper;
use strict;
use base 'Class::Accessor';
use Try::Tiny;

__PACKAGE__->mk_accessors(qw(ws token));

sub new
{
    my($class, $ws) = @_;

    my $token = Bio::KBase::AuthToken->new();
    my $self = {
	ws => $ws,
	token => $token,
    };
    return bless $self, $class;
}

sub username
{
    my($self) = @_;
    return $self->token->user_id;
}

sub workspace_exists
{
    my($self, $wspath) = @_;

    my $list = $self->ws->list_workspaces({});
    for my $ent (@$list)
    {
	my($wid, $wname, $user) = @$ent;
	if ($wspath eq "/$user/$wname")
	{
	    return 1;
	}
	
    }
    return 0;
}

1;
