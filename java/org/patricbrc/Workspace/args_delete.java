package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = args_delete_serializer.class)
@JsonDeserialize(using = args_delete_deserializer.class)
public class args_delete
{
    public delete_params input;
}


