package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
"list" command
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
**/

public class list_params
{
    public List<String> paths;
    public Integer excludeDirectories;
    public Integer excludeObjects;
    public Integer recursive;
    public Integer fullHierachicalOutput;
    public Map<String, String> query;
    public Integer adminmode;
}


