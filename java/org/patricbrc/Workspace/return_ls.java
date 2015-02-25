package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = return_ls_serializer.class)
@JsonDeserialize(using = return_ls_deserializer.class)
public class return_ls
{
    public Map<String, List<ObjectMeta>> output;
}


