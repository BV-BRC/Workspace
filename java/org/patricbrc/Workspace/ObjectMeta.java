package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
ObjectMeta: tuple containing information about an object in the workspace 

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
**/

@JsonSerialize(using = ObjectMeta_serializer.class)
@JsonDeserialize(using = ObjectMeta_deserializer.class)
public class ObjectMeta
{
    public String e_1;
    public String e_2;
    public String e_3;
    public String creation_time;
    public String e_5;
    public String object_owner;
    public Integer e_7;
    public Map<String, String> e_8;
    public Map<String, String> e_9;
    public String user_permission;
    public String global_permission;
    public String shockurl;
}


