package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class return_get_archive_url_serializer extends JsonSerializer<return_get_archive_url>
{
    public void serialize(return_get_archive_url value, JsonGenerator jgen, SerializerProvider provider)
	throws IOException, JsonProcessingException
    {
	jgen.writeStartArray();
	jgen.writeObject(value.url);
	jgen.writeEndArray();
    }
}
