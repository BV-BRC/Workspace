package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class Workspace_tuple_3_serializer extends JsonSerializer<Workspace_tuple_3>
{
    public void serialize(Workspace_tuple_3 value, JsonGenerator jgen, SerializerProvider provider)
	throws IOException, JsonProcessingException
    {
	jgen.writeStartArray();
	jgen.writeObject(value.source);
	jgen.writeObject(value.destination);
	jgen.writeEndArray();
    }
}
