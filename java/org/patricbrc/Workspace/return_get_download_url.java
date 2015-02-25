package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



@JsonSerialize(using = return_get_download_url_serializer.class)
@JsonDeserialize(using = return_get_download_url_deserializer.class)
public class return_get_download_url
{
    public List<String> urls;
}


