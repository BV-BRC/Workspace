package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class args_delete_deserializer extends JsonDeserializer<args_delete>
{
    public args_delete deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	args_delete res = new args_delete();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in args_delete_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.input = p.readValueAs(delete_params.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit args_delete_deserializer with token " + t);

	return res;
    }
}
