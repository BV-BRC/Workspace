package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class return_create_deserializer extends JsonDeserializer<return_create>
{
    public return_create deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	return_create res = new return_create();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in return_create_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.output = p.readValueAs(new TypeReference<List<ObjectMeta>>(){});
	JsonToken t = p.nextToken();
//	System.out.println("exit return_create_deserializer with token " + t);

	return res;
    }
}
