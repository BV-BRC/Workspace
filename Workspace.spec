module Workspace {
/* User permission in worksace (e.g. w - write, r - read, a - admin, n - none) */
typedef string WorkspacePerm;

/* Login name for user */
typedef string Username;

/* Login name for user */
typedef int bool;

/* Indication of a system time */
typedef string Timestamp;

/* Name assigned to an object saved to a workspace */
typedef string ObjectName;

/* Unique UUID assigned to every object in a workspace on save - IDs never reused */
typedef string ObjectID;

/* Specified type of an object (e.g. Genome) */
typedef string ObjectType;

/* Size of the object */
typedef int ObjectSize;

/* Generic type containing object data */
typedef string ObjectData;

/* Path to any object in workspace database */
typedef string FullObjectPath;

/* This is a key value hash of user-specified metadata */
typedef mapping<string,string> UserMetadata;

/* This is a key value hash of automated metadata populated based on object type */
typedef mapping<string,string> AutoMetadata;

/* ObjectMeta: tuple containing information about an object in the workspace 

	ObjectName - name selected for object in workspace
	ObjectType - type of the object in the workspace
	FullObjectPath - full path to object in workspace, including object name
	Timestamp creation_time - time when the object was created
	ObjectID - a globally unique UUID assigned to every object that will never change even if the object is moved
	Username object_owner - name of object owner
	ObjectSize - size of the object in bytes or if object is directory, the number of objects in directory
	UserMetadata - arbitrary user metadata associated with object
	AutoMetadata - automatically populated metadata generated from object data in automated way
	WorkspacePerm user_permission - permissions for the authenticated user of this workspace.
	WorkspacePerm global_permission - whether this workspace is globally readable.
	string shockurl - shockurl included if object is a reference to a shock node
	
*/
typedef tuple<ObjectName,ObjectType,FullObjectPath,Timestamp creation_time,ObjectID,Username object_owner,ObjectSize,UserMetadata,AutoMetadata,WorkspacePerm user_permission,WorkspacePerm global_permission,string shockurl> ObjectMeta;

/********** DATA LOAD FUNCTIONS ********************/

/* "create" command
	Description: 
	This function creates objects, directories, and upload nodes 
	
	Parameters:
	list<tuple<FullObjectPath,ObjectType,UserMetadata,ObjectData>> objects - data on objects being create; use type "Directory" to create a directory; data does not need to be specified if creating a directory or upload node
	WorkspacePerm permission - this will be the default permission specified for any top level directories being created (optional; default = "n")
	bool createUploadNodes - set this boolean to "1" if we are creating upload nodes instead of objects or directories (optional; default = "0")
	bool overwrite - set this boolean to "1" if we should overwrite existing objects; directories cannot be overwritten (optional; default = "0")
	bool adminmode - run this command as an admin, meaning you can create anything anywhere and use the "setowner" param
	string setowner - use this parameter as an administrator to set the own of the created objects
*/
typedef structure {
		list<tuple<FullObjectPath,ObjectType,UserMetadata,ObjectData,Timestamp creation_time>> objects;
		WorkspacePerm permission;
		bool createUploadNodes;
		bool downloadLinks;
		bool overwrite;
		bool adminmode;
		string setowner;
} create_params;
funcdef create(create_params input) returns (list<ObjectMeta> output) authentication required;

/* "update_metadata" command
	Description: 
	This function permits the alteration of metadata associated with an object
	
	Parameters:
	list<tuple<FullObjectPath,UserMetadata>> objects - list of object paths and new metadatas
	bool autometadata - this flag can only be used by the workspace itself
	bool adminmode - run this command as an admin, meaning you can set permissions on anything anywhere
*/
typedef structure {
	list<tuple<FullObjectPath,UserMetadata,ObjectType,Timestamp creation_time>> objects;
	bool autometadata;
	bool adminmode;
} update_metadata_params;
funcdef update_metadata(update_metadata_params input) returns (list<ObjectMeta> output) authentication required;

/********** DATA RETRIEVAL FUNCTIONS ********************/

/* "get" command
	Description: 
	This function retrieves objects, directories, and shock references
	
	Parameters:
	list<FullObjectPath> objects - list of full paths to objects to be retreived
	bool metadata_only - return metadata only
	bool adminmode - run this command as an admin, meaning you can get anything anywhere
*/
typedef structure {
		list<FullObjectPath> objects;
		bool metadata_only;
		bool adminmode;
} get_params;
funcdef get(get_params input) returns (list<tuple<ObjectMeta,ObjectData>> output) authentication optional;

/* "update_shock_meta" command
	Description:
	Call this function to trigger an immediate update of workspace metadata for an object,
	which should typically take place once the upload of a file into shock has completed

	Parameters:
	list<FullObjectPath> objects - list of full paths to objects for which shock nodes should be updated
*/
typedef structure {
	list<FullObjectPath> objects;
	bool adminmode;
} update_auto_meta_params;
funcdef update_auto_meta(update_auto_meta_params input) returns (list<ObjectMeta> output) authentication required;

/* "get_download_url" command
	Description:
	This function returns a URL from which an object may be downloaded
	without any other authentication required. The download URL will only be
	valid for a limited amount of time. 

	Parameters:
	list<FullObjectPath> objects - list of full paths to objects for which URLs are to be constructed
*/
typedef structure {
	list<FullObjectPath> objects;
} get_download_url_params;
funcdef get_download_url(get_download_url_params input) returns (list<string> urls) authentication optional;

/* "get_archive_url" command
	Description:
	This function returns a URL from which an archive of the given 
	objects may be downloaded. The download URL will only be valid for a limited
	amount of time.

	Parameters:
	list<FullObjectPath> objects - list of full paths to objects to be archived
	bool recursive - if true, recurse into folders
	string archive_name - name to be given to the archive file
	string archive_type - type of archive, one of "zip", "tar.gz", "tar.bz2"
*/
typedef structure {
	list<FullObjectPath> objects;
	bool recursive;
	string archive_name;
	string archive_type;
} get_archive_url_params;
funcdef get_archive_url(get_archive_url_params input) returns (string url)  authentication optional;

/* "list" command
	Description: 
	This function retrieves a list of all objects and directories below the specified paths with optional ability to filter by search
	
	Parameters:
	list<FullObjectPath> paths - list of full paths for which subobjects should be listed
	bool excludeDirectories - don't return directories with output (optional; default = "0")
	bool excludeObjects - don't return objects with output (optional; default = "0")
	bool recursive - recursively list contents of all subdirectories; will not work above top level directory (optional; default "0")
	bool fullHierachicalOutput - return a hash of all directories with contents of each; only useful with "recursive" (optional; default = "0")
	mapping<string,string> query - filter output object lists by specified key/value query (optional; default = {})
	bool adminmode - run this command as an admin, meaning you can see anything anywhere
*/
typedef structure {
		list<FullObjectPath> paths;
		bool excludeDirectories;
		bool excludeObjects;
		bool recursive;
		bool fullHierachicalOutput;
		mapping<string,list<string>> query;
		bool adminmode;
} list_params;
funcdef ls(list_params input) returns (mapping<FullObjectPath,list<ObjectMeta>> output)  authentication optional;

/********** REORGANIZATION FUNCTIONS *******************/

/* "copy" command
	Description: 
	This function copies or moves objects from one location to another
	
	Parameters:
	list<tuple<FullObjectPath source,FullObjectPath destination>> objects - list of source and destination paths for copy operation
	bool overwrite - indicates that copy/move should permit overwrite of destination objects; directories will never by overwritten by objects (optional; default = "0")
	bool recursive - indicates that when copying a directory, all subobjects within the directory will also be copied (optional; default = "0")
	bool move  - indicates that instead of a copy, objects should be moved; moved objects retain their UUIDs (optional; default = "0")
	bool adminmode - run this command as an admin, meaning you can copy anything anywhere
*/
typedef structure {
	list<tuple<FullObjectPath source,FullObjectPath destination>> objects;
	bool overwrite;
	bool recursive;
	bool move;
	bool adminmode;
} copy_params;
funcdef copy(copy_params input) returns (list<ObjectMeta> output) authentication required;

/********** DELETION FUNCTIONS *******************/

/* "delete" command
	Description: 
	This function deletes the specified list of objects or directories
	
	Parameters:
	list<FullObjectPath> objects  - list of objects or directories to be deleted
	bool deleteDirectories - indicates that directories should be deleted (optional; default = "0")
	bool forces - must set this flag to delete a directory that contains subobjects (optional; default = "0")
	bool adminmode - run this command as an admin, meaning you can delete anything anywhere
*/
typedef structure {
	list<FullObjectPath> objects;
	bool deleteDirectories;
	bool force;
	bool adminmode;
} delete_params;
funcdef delete(delete_params input) returns (list<ObjectMeta> output) authentication required;

/********** FUNCTIONS RELATED TO SHARING ********************/

/* "set_permissions" command
	Description: 
	This function alters permissions for the specified object
	
	Parameters:
	FullObjectPath path - path to directory for which permissions are to be set; only top-level directories can have permissions altered
	list<tuple<Username,WorkspacePerm>> permissions - set of user-specific permissions for specified directory (optional; default = null)
	WorkspacePerm new_global_permission - new default permissions on specified directory (optional; default = null)
	bool adminmode - run this command as an admin, meaning you can set permissions on anything anywhere
*/
typedef structure {
	FullObjectPath path;
	list<tuple<Username,WorkspacePerm> > permissions;
	WorkspacePerm new_global_permission;
	bool adminmode;
} set_permissions_params;
funcdef set_permissions(set_permissions_params input) returns (list<tuple<Username,WorkspacePerm> > output) authentication required;

/* "list_permissions" command
	Description: 
	This function lists permissions for the specified objects
	
	Parameters:
	list<FullObjectPath> objects - path to objects for which permissions are to be listed
	bool adminmode - run this command as an admin, meaning you can list permissions on anything anywhere
*/
typedef structure {
	list<FullObjectPath> objects;
	bool adminmode;
} list_permissions_params;
funcdef list_permissions(list_permissions_params input) returns (mapping<string,list<tuple<Username,WorkspacePerm> > > output) authentication optional;

};
