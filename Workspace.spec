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
typedef structure {
	string id;
} ObjectData;

/* Path to a workspace or workspace subdirectory */
typedef string WorkspacePath;

/* Unique UUID for workspace */
typedef string WorkspaceID;

/* Name for workspace specified by user */
typedef string WorkspaceName;

/* A URI that can be used to restfully retrieve a data object from the workspace */
typedef string WorkspaceReference;

/* This is a key value hash of user-specified metadata */
typedef mapping<string,string> UserMetadata;

/* This is a key value hash of automated metadata populated based on object type */
typedef mapping<string,string> AutoMetadata;

/* WorkspaceMeta: tuple containing information about a workspace 

	WorkspaceID - a globally unique UUID assigned every workspace that will never change
	WorkspaceName - name of the workspace.
	Username workspace_owner - name of the user who owns (e.g. created) this workspace.
	timestamp moddate - date when the workspace was last modified.
	int num_objects - the approximate number of objects (including directories) in the workspace.
	WorkspacePerm user_permission - permissions for the authenticated user of this workspace.
	WorkspacePerm global_permission - whether this workspace is globally readable.
	int num_directories - number of directories in workspace.
	UserMetadata - arbitrary metadata for workspace

*/
typedef tuple<WorkspaceID,WorkspaceName,Username workspace_owner,Timestamp moddate,int num_objects,WorkspacePerm user_permission,WorkspacePerm global_permission,int num_directories,UserMetadata> WorkspaceMeta;

/* ObjectMeta: tuple containing information about an object in the workspace 

	ObjectID - a globally unique UUID assigned to very object that will never change
	ObjectName - name selected for object in workspace
	ObjectType - type of the object in the workspace
	Timestamp creation_time - time when the object was created
	WorkspaceReference - restful reference permitting retrieval of object in workspace
	Username object_owner - name of object owner
	WorkspaceID - UUID of workspace containing object
	WorkspaceName - name of workspace containing object
	WorkspacePath - full path to object in workspace
	ObjectSize - size of the object in bytes
	UserMetadata - arbitrary user metadata associated with object
	AutoMetadata - automatically populated metadata generated from object data in automated way
	
*/
typedef tuple<ObjectID,ObjectName,ObjectType,Timestamp creation_time,WorkspaceReference,Username object_owner,WorkspaceID,WorkspaceName,WorkspacePath,ObjectSize,UserMetadata,AutoMetadata> ObjectMeta;

/* This is the struct returned by get_objects, which includes object data and metadata */
typedef structure {
		ObjectData data;
		ObjectMeta info;
} ObjectDataInfo;

/********** DATA LOAD FUNCTIONS ********************/

/* This function creates a new workspace volume - returns metadata of created workspace */
typedef structure {
		WorkspaceName workspace;
		WorkspacePerm permission;
		UserMetadata metadata;
} create_workspace_params;
funcdef create_workspace(create_workspace_params input) returns (WorkspaceMeta output) authentication required;

/* This function receives a list of objects, names, and types and stores the objects in the workspace */
typedef structure {
		list<tuple<WorkspacePath,ObjectName,ObjectData,ObjectType,UserMetadata>> objects;
		bool overwrite;
} save_objects_params;
funcdef save_objects(save_objects_params input) returns (list<ObjectMeta> output) authentication required;

/* This function creates a node in shock that the user can upload to and links this node to a workspace */
typedef structure {
		list<tuple<WorkspacePath,ObjectName,ObjectType,UserMetadata>> objects;
		bool overwrite;
} create_upload_node_params;
funcdef create_upload_node(create_upload_node_params input) returns (list<string> output) authentication required;

/********** DATA RETRIEVAL FUNCTIONS ********************/

/* This function retrieves a list of objects from the workspace */
typedef structure {
		list<tuple<WorkspacePath,ObjectName>> objects;
		bool metadata_only;
} get_objects_params;
funcdef get_objects(get_objects_params input) returns (list<ObjectDataInfo> output) authentication required;

/* This function retrieves metadata for a set of workspaces */
typedef structure {
		list<WorkspaceID> workspaces;
} get_workspace_meta_params;
funcdef get_workspace_meta(get_workspace_meta_params input) returns (list<WorkspaceMeta> output) authentication required;

/* This function retrieves a list of objects from the workspace */
typedef structure {
		list<ObjectID> objects;
		bool metadata_only;
} get_objects_by_reference_params;
funcdef get_objects_by_reference(get_objects_by_reference_params input) returns (list<ObjectDataInfo> output) authentication required;

/* This function lists the contents of the specified workspace (e.g. ls) */
typedef structure {
		WorkspacePath directory;
		bool includeSubDirectories;
		bool excludeObjects;
		bool Recursive;
} list_workspace_contents_params;
funcdef list_workspace_contents(list_workspace_contents_params input) returns (list<ObjectMeta> output) authentication required;

/* This function lists the contents of the specified workspace (e.g. ls) */
typedef structure {
		WorkspacePath directory;
		bool includeSubDirectories;
		bool excludeObjects;
		bool Recursive;
} list_workspace_hierarchical_contents_params;
funcdef list_workspace_hierarchical_contents(list_workspace_hierarchical_contents_params input) returns (mapping<WorkspacePath,list<ObjectMeta>> output) authentication required;

/* This function lists all workspace volumes accessible by user */
typedef structure {
		bool owned_only;
		bool no_public;
} list_workspaces_params;
funcdef list_workspaces(list_workspaces_params input) returns (list<WorkspaceMeta> output) authentication required;

/* Provides a list of all objects in all workspaces whose name or workspace or path match the input query */
typedef structure {
		mapping<string,string> workspace_query;
} search_for_workspaces_params;
funcdef search_for_workspaces(search_for_workspaces_params input) returns (list<WorkspaceMeta> output) authentication required;

/* Provides a list of all objects in all workspaces whose name or workspace or path match the input query */
typedef structure {
		mapping<string,string> workspace_query;
		mapping<string,string> object_query;
} search_for_workspace_objects_params;
funcdef search_for_workspace_objects(search_for_workspace_objects_params input) returns (list<ObjectMeta> output) authentication required;

/********** REORGANIZATION FUNCTIONS *******************/

/* This function creates a new workspace volume - returns metadata of created workspace */
typedef structure {
		WorkspacePath directory;
		UserMetadata metadata;
} create_workspace_directory_params;
funcdef create_workspace_directory(create_workspace_directory_params input) returns (ObjectMeta output) authentication required;

/* This function copies an object to a new workspace */
typedef structure {
		list<tuple<WorkspacePath source,ObjectName origname,WorkspacePath destination,ObjectName newname>> objects;
		bool overwrite;
		bool recursive;
} copy_objects_params;
funcdef copy_objects(copy_objects_params input) returns (list<ObjectMeta> output) authentication required;

/* This function copies an object to a new workspace */
typedef structure {
		list<tuple<WorkspacePath source,ObjectName origname,WorkspacePath destination,ObjectName newname>> objects;
		bool overwrite;
		bool recursive;
} move_objects_params;
funcdef move_objects(move_objects_params input) returns (list<ObjectMeta> output) authentication required;

/********** DELETION FUNCTIONS *******************/

/* This function deletes an entire workspace (e.g. rm -rf) - returns metadata of deleted workspace */
typedef structure {
		WorkspaceName workspace;
} delete_workspace_params;
funcdef delete_workspace(delete_workspace_params input) returns (WorkspaceMeta output) authentication required;

/* This function deletes an object from a workspace */
typedef structure {
		list<tuple<WorkspacePath,ObjectName>> objects;
		bool delete_directories;
		bool force;
} delete_objects_params;
funcdef delete_objects(delete_objects_params input) returns (list<ObjectMeta> output) authentication required;

/* This function creates a new workspace volume - returns metadata of created workspace */
typedef structure {
		WorkspacePath directory;
		bool force;
} delete_workspace_directory_params;
funcdef delete_workspace_directory(delete_workspace_directory_params input) returns (ObjectMeta output) authentication required;

/********** FUNCTIONS RELATED TO SHARING ********************/

/* This function resets the global permission of a workspace to the input value */
typedef structure {
		WorkspaceName workspace;
		WorkspacePerm global_permission;
} reset_global_permission_params;
funcdef reset_global_permission(reset_global_permission_params input) returns (WorkspaceMeta output) authentication required;

/* This function gives permissions to a workspace to new users (e.g. chmod) */
typedef structure {
		WorkspaceName workspace;
		list<tuple<Username,WorkspacePerm>> permissions;
} set_workspace_permissions_params;
funcdef set_workspace_permissions(set_workspace_permissions_params input) returns (WorkspaceMeta output) authentication required;

/* Provides a list of all users who have access to the workspace */
typedef structure {
		list<WorkspaceName> workspaces;
} list_workspace_permissions_params;
funcdef list_workspace_permissions(list_workspace_permissions_params input) returns (mapping<string,list<tuple<Username,WorkspacePerm>>> output) authentication required;

};