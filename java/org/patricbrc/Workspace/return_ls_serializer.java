package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class return_ls_serializer extends JsonSerializer<return_ls>
{
    public void serialize(return_ls value, JsonGenerator jgen, SerializerProvider provider)
	throws IOException, JsonProcessingException
    {
	jgen.writeStartArray();
	jgen.writeObject(value.output);
	jgen.writeEndArray();
    }
}
