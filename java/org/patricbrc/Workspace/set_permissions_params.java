package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
"set_permissions" command
Description: 
This function alters permissions for the specified object

Parameters:
FullObjectPath path - path to directory for which permissions are to be set; only top-level directories can have permissions altered
list<tuple<Username,WorkspacePerm>> permissions - set of user-specific permissions for specified directory (optional; default = null)
WorkspacePerm new_global_permission - new default permissions on specified directory (optional; default = null)
bool adminmode - run this command as an admin, meaning you can set permissions on anything anywhere
**/

public class set_permissions_params
{
    public String path;
    public List<Workspace_tuple_3> permissions;
    public String new_global_permission;
    public Integer adminmode;
}


