module Workspace {
authentication required;
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
funcdef create_workspace(WorkspaceName workspace,WorkspacePerm permission,UserMetadata metadata) returns (WorkspaceMeta);

/* This function receives a list of objects, names, and types and stores the objects in the workspace */
funcdef save_objects(list<tuple<WorkspacePath,ObjectName,ObjectData,ObjectType,UserMetadata>> objects,bool overwrite) returns (list<ObjectMeta>);

/* This function creates a node in shock that the user can upload to and links this node to a workspace */
funcdef create_upload_node(list<tuple<WorkspacePath,ObjectName,ObjectType>> objects,bool overwrite) returns (list<string> output);

/********** DATA RETRIEVAL FUNCTIONS ********************/

/* This function retrieves a list of objects from the workspace */
funcdef get_objects(list<tuple<WorkspacePath,ObjectName>> objects) returns (list<ObjectDataInfo> output);

/* This function retrieves a list of objects from the workspace */
funcdef get_objects_by_reference(list<ObjectID> objects) returns (list<ObjectDataInfo> output);

/* This function lists the contents of the specified workspace (e.g. ls) */
funcdef list_workspace_contents(WorkspacePath directory,bool includeSubDirectories,bool excludeObjects,bool Recursive) returns (list<ObjectMeta> output);

/* This function lists the contents of the specified workspace (e.g. ls) */
funcdef list_workspace_hierarchical_contents(WorkspacePath directory,bool includeSubDirectories,bool excludeObjects,bool Recursive) returns (mapping<WorkspacePath,list<ObjectMeta>> output);

/* This function lists all workspace volumes accessible by user */
funcdef list_workspaces(bool owned_only,bool no_public) returns (list<WorkspaceMeta> output);

/* Provides a list of all objects in all workspaces whose name or workspace or path match the input query */
funcdef search_for_workspaces(mapping<string,string> query) returns (list<WorkspaceMeta> output);

/* Provides a list of all objects in all workspaces whose name or workspace or path match the input query */
funcdef search_for_workspace_objects(mapping<string,string> query) returns (list<ObjectMeta> output);

/********** REORGANIZATION FUNCTIONS *******************/

/* This function creates a new workspace volume - returns metadata of created workspace */
funcdef create_workspace_directory(WorkspacePath directory,UserMetadata metadata) returns (ObjectMeta output);

/* This function copies an object to a new workspace */
funcdef copy_objects(list<tuple<WorkspacePath source,ObjectName origname,WorkspacePath destination,ObjectName newname>> objects,bool overwrite,bool recursive) returns (list<ObjectMeta> output);

/* This function copies an object to a new workspace */
funcdef move_objects(list<tuple<WorkspacePath source,ObjectName origname,WorkspacePath destination,ObjectName newname>> objects,bool overwrite,bool recursive) returns (list<ObjectMeta> output);

/********** DELETION FUNCTIONS *******************/

/* This function deletes an entire workspace (e.g. rm -rf) - returns metadata of deleted workspace */
funcdef delete_workspace(WorkspaceName workspace) returns (WorkspaceMeta output);

/* This function deletes an object from a workspace */
funcdef delete_objects(list<tuple<WorkspacePath,ObjectName>> objects,bool delete_directories,bool force) returns (list<ObjectMeta> output);

/* This function creates a new workspace volume - returns metadata of created workspace */
funcdef delete_workspace_directory(WorkspacePath directory,bool force) returns (ObjectMeta output);

/********** FUNCTIONS RELATED TO SHARING ********************/

/* This function resets the global permission of a workspace to the input value */
funcdef reset_global_permission(WorkspaceName workspace,WorkspacePerm global_permission) returns (WorkspaceMeta output);

/* This function gives permissions to a workspace to new users (e.g. chmod) */
funcdef set_workspace_permissions(WorkspaceName workspace,list<tuple<Username,WorkspacePerm>> permissions) returns (WorkspaceMeta output);

/* Provides a list of all users who have access to the workspace */
funcdef list_workspace_permissions(list<WorkspaceName> workspaces) returns (mapping<string,list<tuple<Username,WorkspacePerm>>> output);

};