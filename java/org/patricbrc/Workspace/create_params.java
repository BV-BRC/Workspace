package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
"create" command
Description: 
This function creates objects, directories, and upload nodes 

Parameters:
list<tuple<FullObjectPath,ObjectType,UserMetadata,ObjectData>> objects - data on objects being create; use type "Directory" to create a directory; data does not need to be specified if creating a directory or upload node
WorkspacePerm permission - this will be the default permission specified for any top level directories being created (optional; default = "n")
bool createUploadNodes - set this boolean to "1" if we are creating upload nodes instead of objects or directories (optional; default = "0")
bool overwrite - set this boolean to "1" if we should overwrite existing objects; directories cannot be overwritten (optional; default = "0")
bool adminmode - run this command as an admin, meaning you can create anything anywhere and use the "setowner" param
string setowner - use this parameter as an administrator to set the own of the created objects
**/

public class create_params
{
    public List<Workspace_tuple_1> objects;
    public String permission;
    public Integer createUploadNodes;
    public Integer downloadLinks;
    public Integer overwrite;
    public Integer adminmode;
    public String setowner;
}


