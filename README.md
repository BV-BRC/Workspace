Repo for development of the P3 Workspace Service

SERVICE DEPENDENCIES:
typecomp
shock

SETUP

1) A mongodb instance must be up and running.
2) The connected Shock server must be up and running.
3) make
4) if you want to run tests: make test
5) make deploy
6) fill in deploy.cfg and set KB_DEPLOYMENT_CONFIG appropriately
7) /kb/deployment/services/Workspace/start_service

If the server doesn't start up correctly, check /var/log/syslog 
for debugging information.

MONGO OBJECTS

The workspace collection holds objects of this form:

[
{
  "_id": ObjectId("5519b6dcfc6521532b3df037"),
  "owner": "olson",
  "global_permission": "n",
  "permissions": {

  },
  "creation_date": "2015-03-30T20:49:32",
  "name": "olson",
  "metadata": {

  },
  "uuid": "4431C49E-D71E-11E4-B895-17ED682E0674"
}
]

The objects collection holds objects of this form:

[
{
  "_id": ObjectId("5519bb83fc6521532b3df038"),
  "owner": "olson",
  "shock": NumberLong(0),
  "name": "buchnera.fa",
  "autometadata": {

  },
  "path": "",
  "uuid": "0A1A550C-D721-11E4-8FDD-17ED682E0674",
  "folder": NumberLong(0),
  "size": NumberLong(626258),
  "wsobj": {
    "owner": "olson",
    "global_permission": "n",
    "creation_date": "2015-03-30T20:49:32",
    "permissions": {

    },
    "_id": ObjectId("5519b6dcfc6521532b3df037"),
    "name": "olson",
    "metadata": {

    },
    "uuid": "4431C49E-D71E-11E4-B895-17ED682E0674"
  },
  "creation_date": "2015-03-30T21:09:23",
  "metadata": {
    "original_file": "/homes/olson/buchnera.fa"
  },
  "type": "unspecified",
  "workspace_uuid": "4431C49E-D71E-11E4-B895-17ED682E0674"
}
]


UNAUTHENTICATED DOWNLOADS

The workspace service supports the creation of time-limited download
URLs that do not require authentication to retrieve.

We have two forms of this; single-file download and archive
download. 

Single-file download is managed with a mongodb collection
download_keys that maps from a download key (a long apparently random
string) to a workspace object identifier. The workspace object must
not be a folder (folders are managed using archive downloads).

The identifier is a random string. We use a base-64 representation of
a UUID (shorter than the standard UUID hex representation).

The URL generated will have the filename of the source file after the
random number:

       [base of service url]/download/<random>/<filename>

This will provide a hint as to what the file is, and will also help
browsers generate the correct path when saving. We will also issue
the approprate Content-Disposition header to trigger a save to disk
with the correct filename.

The document stored in mongo is of the following form:

structure {
	download_key string;
	workspace_path string;
	expiration_time int;
	file_path string;
	shock_node string;
	user_token string;
};

We use the collection named downloads to store these documents.

We use a secondary Dancer application hosted in a twiggy asynchonous server
to serve the actual download documents. We use the AnyEvent
infrastructure to allow multiple downlaods to be processed at once. It
will also host a download data item garbage collection timer to purge
the downloads collection of expired entries.
