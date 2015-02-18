package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
"delete" command
Description: 
This function deletes the specified list of objects or directories

Parameters:
list<FullObjectPath> objects  - list of objects or directories to be deleted
bool deleteDirectories - indicates that directories should be deleted (optional; default = "0")
bool forces - must set this flag to delete a directory that contains subobjects (optional; default = "0")
bool adminmode - run this command as an admin, meaning you can delete anything anywhere
**/

public class delete_params
{
    public List<String> objects;
    public Integer deleteDirectories;
    public Integer force;
    public Integer adminmode;
}


