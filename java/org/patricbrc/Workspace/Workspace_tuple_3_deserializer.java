package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class Workspace_tuple_3_deserializer extends JsonDeserializer<Workspace_tuple_3>
{
    public Workspace_tuple_3 deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	Workspace_tuple_3 res = new Workspace_tuple_3();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in Workspace_tuple_3_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.source = p.readValueAs(String.class);
	res.destination = p.readValueAs(String.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit Workspace_tuple_3_deserializer with token " + t);

	return res;
    }
}
