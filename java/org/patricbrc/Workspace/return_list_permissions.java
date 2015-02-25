package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = return_list_permissions_serializer.class)
@JsonDeserialize(using = return_list_permissions_deserializer.class)
public class return_list_permissions
{
    public Map<String, List<Workspace_tuple_3>> output;
}


