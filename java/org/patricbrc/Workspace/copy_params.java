package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
"copy" command
Description: 
This function copies or moves objects from one location to another

Parameters:
list<tuple<FullObjectPath source,FullObjectPath destination>> objects - list of source and destination paths for copy operation
bool overwrite - indicates that copy/move should permit overwrite of destination objects; directories will never by overwritten by objects (optional; default = "0")
bool recursive - indicates that when copying a directory, all subobjects within the directory will also be copied (optional; default = "0")
bool move  - indicates that instead of a copy, objects should be moved; moved objects retain their UUIDs (optional; default = "0")
bool adminmode - run this command as an admin, meaning you can copy anything anywhere
**/

public class copy_params
{
    public List<Workspace_tuple_3> objects;
    public Integer overwrite;
    public Integer recursive;
    public Integer move;
    public Integer adminmode;
}


