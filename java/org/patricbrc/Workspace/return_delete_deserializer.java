package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class return_delete_deserializer extends JsonDeserializer<return_delete>
{
    public return_delete deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	return_delete res = new return_delete();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in return_delete_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.output = p.readValueAs(new TypeReference<List<ObjectMeta>>(){});
	JsonToken t = p.nextToken();
//	System.out.println("exit return_delete_deserializer with token " + t);

	return res;
    }
}
