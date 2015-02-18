package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = Workspace_tuple_2_serializer.class)
@JsonDeserialize(using = Workspace_tuple_2_deserializer.class)
public class Workspace_tuple_2
{
    public ObjectMeta e_1;
    public String e_2;
}


