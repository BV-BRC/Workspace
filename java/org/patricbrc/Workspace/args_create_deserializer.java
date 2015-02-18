package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class args_create_deserializer extends JsonDeserializer<args_create>
{
    public args_create deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	args_create res = new args_create();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in args_create_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.input = p.readValueAs(create_params.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit args_create_deserializer with token " + t);

	return res;
    }
}
