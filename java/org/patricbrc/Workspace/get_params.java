package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
"get" command
Description: 
This function retrieves objects, directories, and shock references

Parameters:
list<FullObjectPath> objects - list of full paths to objects to be retreived
bool metadata_only - return metadata only
bool adminmode - run this command as an admin, meaning you can get anything anywhere
**/

public class get_params
{
    public List<String> objects;
    public Integer metadata_only;
    public Integer adminmode;
}


