package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = return_get_serializer.class)
@JsonDeserialize(using = return_get_deserializer.class)
public class return_get
{
    public List<Workspace_tuple_2> output;
}


