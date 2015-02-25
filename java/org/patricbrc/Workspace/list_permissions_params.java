package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
"list_permissions" command
Description: 
This function lists permissions for the specified objects

Parameters:
list<FullObjectPath> objects - path to objects for which permissions are to be listed
bool adminmode - run this command as an admin, meaning you can list permissions on anything anywhere
**/

public class list_permissions_params
{
    public List<String> objects;
    public Integer adminmode;
}


