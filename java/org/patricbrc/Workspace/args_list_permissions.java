package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = args_list_permissions_serializer.class)
@JsonDeserialize(using = args_list_permissions_deserializer.class)
public class args_list_permissions
{
    public list_permissions_params input;
}


