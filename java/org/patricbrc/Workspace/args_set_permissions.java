package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = args_set_permissions_serializer.class)
@JsonDeserialize(using = args_set_permissions_deserializer.class)
public class args_set_permissions
{
    public set_permissions_params input;
}


