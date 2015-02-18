package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class Workspace_tuple_1_serializer extends JsonSerializer<Workspace_tuple_1>
{
    public void serialize(Workspace_tuple_1 value, JsonGenerator jgen, SerializerProvider provider)
	throws IOException, JsonProcessingException
    {
	jgen.writeStartArray();
	jgen.writeObject(value.e_1);
	jgen.writeObject(value.e_2);
	jgen.writeObject(value.e_3);
	jgen.writeObject(value.e_4);
	jgen.writeEndArray();
    }
}
