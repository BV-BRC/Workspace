package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class Workspace_tuple_1_deserializer extends JsonDeserializer<Workspace_tuple_1>
{
    public Workspace_tuple_1 deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	Workspace_tuple_1 res = new Workspace_tuple_1();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in Workspace_tuple_1_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.e_1 = p.readValueAs(String.class);
	res.e_2 = p.readValueAs(String.class);
	res.e_3 = p.readValueAs(new TypeReference<Map<String, String>>(){});
	res.e_4 = p.readValueAs(String.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit Workspace_tuple_1_deserializer with token " + t);

	return res;
    }
}
