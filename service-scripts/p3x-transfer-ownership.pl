#!/usr/bin/env perl

=head1 NAME

p3x-transfer-ownership - Transfer all workspaces from one owner to another

=head1 SYNOPSIS

    p3x-transfer-ownership [options] --from old_owner --to new_owner

    # Dry run (default) - shows what would be done
    p3x-transfer-ownership --from alice --to bob

    # Actually perform the transfer
    p3x-transfer-ownership --from alice --to bob --execute

=head1 DESCRIPTION

Transfers ownership of all workspaces from one user to another. This includes:

=over 4

=item * Updating the owner field in the workspaces collection

=item * Updating the owner field for all objects in those workspaces

=item * Moving the filesystem directories from old owner to new owner

=back

If a workspace name conflicts with an existing workspace owned by the target user,
the workspace will be renamed to C<{original-name}-from-{old-owner}>.

Note: Filesystem storage is in the C<P3WSDB> subdirectory of the configured db-path.

By default, runs in dry-run mode showing what changes would be made.
Use --execute to actually perform the transfer.

=head1 OPTIONS

=over 4

=item --from <username>

The current owner whose workspaces will be transferred. Required.

=item --to <username>

The new owner who will receive the workspaces. Required.

=item --config <file>

Path to configuration file. Defaults to deploy.cfg in current directory.
The config file should have a [Workspace] section with:

    [Workspace]
    mongodb-host = localhost
    mongodb-database = WorkspaceBuild
    mongodb-user = null
    mongodb-pwd = null
    db-path = /mnt/workspace

=item --execute

Actually perform the transfer. Without this flag, only shows what would be done.

=item --help

Show this help message.

=back

=head1 AUTHOR

BV-BRC Team

=cut

use strict;
use warnings;
use Data::Dumper;
use MongoDB::Connection;
use File::Copy qw(move);
use File::Path qw(make_path);
use Getopt::Long::Descriptive;
use Config::Simple;

my($opt, $usage) = describe_options(
    "%c %o",
    ["from=s",   "Current owner username", { required => 1 }],
    ["to=s",     "New owner username", { required => 1 }],
    ["config=s", "Path to configuration file", { default => "deploy.cfg" }],
    ["execute",  "Actually perform the transfer (default is dry-run)"],
    ["help|h",   "Show this help message"],
);

print($usage->text), exit 0 if $opt->help;

my $from_user = $opt->from;
my $to_user = $opt->to;
my $dry_run = !$opt->execute;

# Validate usernames
$from_user ne '' or die "Error: --from username cannot be empty\n";
$to_user ne '' or die "Error: --to username cannot be empty\n";
$from_user ne $to_user or die "Error: --from and --to cannot be the same user\n";

# Load configuration
my $config_file = $opt->config;
-f $config_file or die "Error: Configuration file not found: $config_file\n";

my $cfg = Config::Simple->new($config_file)
    or die "Error reading config file: " . Config::Simple->error() . "\n";

# Read settings from [Workspace] section
my $mongo_host = $cfg->param('Workspace.mongodb-host')
    or die "Error: mongodb-host not set in config\n";
my $mongo_db = $cfg->param('Workspace.mongodb-database')
    or die "Error: mongodb-database not set in config\n";
my $db_path = $cfg->param('Workspace.db-path')
    or die "Error: db-path not set in config\n";

# MongoDB credentials (may be 'null' string meaning no auth)
my $mongo_user = $cfg->param('Workspace.mongodb-user');
my $mongo_pwd = $cfg->param('Workspace.mongodb-pwd');

# Treat 'null' string as undefined
$mongo_user = undef if !defined($mongo_user) || $mongo_user eq 'null' || $mongo_user eq '';
$mongo_pwd = undef if !defined($mongo_pwd) || $mongo_pwd eq 'null' || $mongo_pwd eq '';

print "=" x 60, "\n";
print "Workspace Ownership Transfer\n";
print "=" x 60, "\n";
print "From user:     $from_user\n";
print "To user:       $to_user\n";
print "MongoDB host:  $mongo_host\n";
print "MongoDB db:    $mongo_db\n";
print "DB path:       $db_path\n";
print "Mode:          ", ($dry_run ? "DRY RUN (use --execute to apply)" : "EXECUTE"), "\n";
print "=" x 60, "\n\n";

# Connect to MongoDB
my %mongo_args = (
    host => $mongo_host,
    db_name => $mongo_db,
);
$mongo_args{username} = $mongo_user if defined $mongo_user;
$mongo_args{password} = $mongo_pwd if defined $mongo_pwd;

my $mongo = MongoDB::Connection->new(%mongo_args)
    or die "Error: Failed to connect to MongoDB at $mongo_host\n";

my $db = $mongo->get_database($mongo_db);
my $ws_coll = $db->get_collection('workspaces');
my $obj_coll = $db->get_collection('objects');

# Find all workspaces owned by from_user
my @workspaces = $ws_coll->find({ owner => $from_user })->all;
my $ws_count = scalar(@workspaces);

if ($ws_count == 0) {
    print "No workspaces found owned by '$from_user'\n";
    exit 0;
}

print "Found $ws_count workspace(s) owned by '$from_user'\n\n";

# Check if target user directory exists, create if needed
my $to_user_dir = "$db_path/P3WSDB/$to_user";
if (!$dry_run && !-d $to_user_dir) {
    print "Creating directory: $to_user_dir\n";
    make_path($to_user_dir) or die "Error: Failed to create directory $to_user_dir: $!\n";
}

# Track statistics
my $transferred = 0;
my $skipped = 0;
my $total_objects = 0;

for my $ws (@workspaces) {
    my $ws_name = $ws->{name};
    my $ws_uuid = $ws->{uuid};
    my $new_ws_name = $ws_name;  # May be renamed if collision

    print "-" x 40, "\n";
    print "Workspace: $from_user/$ws_name\n";
    print "UUID:      $ws_uuid\n";

    # Check for name collision in target user
    my $existing = $ws_coll->find_one({ owner => $to_user, name => $ws_name });
    if ($existing) {
        $new_ws_name = "${ws_name}-from-${from_user}";
        print "NOTE: '$to_user' already has a workspace named '$ws_name'\n";
        print "      Renaming to: $new_ws_name\n";

        # Check if the renamed version also exists
        my $renamed_exists = $ws_coll->find_one({ owner => $to_user, name => $new_ws_name });
        if ($renamed_exists) {
            print "WARNING: '$to_user' also has workspace named '$new_ws_name'\n";
            print "SKIPPING this workspace to avoid collision\n";
            $skipped++;
            next;
        }
    }

    # Count objects in this workspace
    my $obj_count = $obj_coll->count({ workspace_uuid => $ws_uuid });
    print "Objects:   $obj_count\n";
    $total_objects += $obj_count;

    # Filesystem paths (files are in P3WSDB subdirectory)
    my $old_path = "$db_path/P3WSDB/$from_user/$ws_name";
    my $new_path = "$db_path/P3WSDB/$to_user/$new_ws_name";

    # Move filesystem directory
    if (-d $old_path) {
        print "Moving:    $old_path\n";
        print "       ->  $new_path\n";

        if (!$dry_run) {
            if (-e $new_path) {
                print "ERROR: Target path already exists: $new_path\n";
                print "SKIPPING this workspace\n";
                $skipped++;
                next;
            }

            move($old_path, $new_path)
                or do {
                    print "ERROR: Failed to move directory: $!\n";
                    print "SKIPPING this workspace\n";
                    $skipped++;
                    next;
                };
            print "Directory moved successfully\n";
        }
    } else {
        print "Note: No filesystem directory at $old_path\n";
    }

    # Update workspace document (owner and possibly name)
    print "Updating workspace owner in MongoDB...\n";
    if ($new_ws_name ne $ws_name) {
        print "Renaming workspace: $ws_name -> $new_ws_name\n";
    }
    if (!$dry_run) {
        my $update_fields = { owner => $to_user };
        $update_fields->{name} = $new_ws_name if $new_ws_name ne $ws_name;

        my $result = $ws_coll->update(
            { uuid => $ws_uuid },
            { '$set' => $update_fields },
            { safe => 1 }
        );
        if (!$result->{ok}) {
            print "ERROR: Failed to update workspace: " . Dumper($result) . "\n";
            $skipped++;
            next;
        }
    }

    # Update all objects in this workspace
    print "Updating $obj_count object(s) in workspace...\n";
    if (!$dry_run) {
        my $result = $obj_coll->update(
            { workspace_uuid => $ws_uuid },
            { '$set' => { owner => $to_user } },
            { safe => 1, multiple => 1 }
        );
        if (!$result->{ok}) {
            print "ERROR: Failed to update objects: " . Dumper($result) . "\n";
        }
    }

    print "Done\n";
    $transferred++;
}

print "\n";
print "=" x 60, "\n";
print "Summary\n";
print "=" x 60, "\n";
print "Workspaces transferred: $transferred\n";
print "Workspaces skipped:     $skipped\n";
print "Total objects updated:  $total_objects\n";
print "\n";

if ($dry_run) {
    print "This was a DRY RUN. No changes were made.\n";
    print "Run with --execute to apply these changes.\n";
} else {
    print "Transfer complete.\n";
}

# Check for orphaned objects (objects owned by from_user in other workspaces)
my @ws_uuids = map { $_->{uuid} } @workspaces;
my $orphan_count = $obj_coll->count({
    owner => $from_user,
    workspace_uuid => { '$nin' => \@ws_uuids }
});

if ($orphan_count > 0) {
    print "\n";
    print "NOTE: Found $orphan_count object(s) owned by '$from_user' in other users' workspaces.\n";
    print "These objects were NOT transferred (they belong to shared workspaces).\n";
}
