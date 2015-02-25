package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = Workspace_tuple_3_serializer.class)
@JsonDeserialize(using = Workspace_tuple_3_deserializer.class)
public class Workspace_tuple_3
{
    public String source;
    public String destination;
}


