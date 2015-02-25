package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = Workspace_tuple_1_serializer.class)
@JsonDeserialize(using = Workspace_tuple_1_deserializer.class)
public class Workspace_tuple_1
{
    public String e_1;
    public String e_2;
    public Map<String, String> e_3;
    public String e_4;
}


