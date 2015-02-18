package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class ObjectMeta_serializer extends JsonSerializer<ObjectMeta>
{
    public void serialize(ObjectMeta value, JsonGenerator jgen, SerializerProvider provider)
	throws IOException, JsonProcessingException
    {
	jgen.writeStartArray();
	jgen.writeObject(value.e_1);
	jgen.writeObject(value.e_2);
	jgen.writeObject(value.e_3);
	jgen.writeObject(value.creation_time);
	jgen.writeObject(value.e_5);
	jgen.writeObject(value.object_owner);
	jgen.writeObject(value.e_7);
	jgen.writeObject(value.e_8);
	jgen.writeObject(value.e_9);
	jgen.writeObject(value.user_permission);
	jgen.writeObject(value.global_permission);
	jgen.writeObject(value.shockurl);
	jgen.writeEndArray();
    }
}
