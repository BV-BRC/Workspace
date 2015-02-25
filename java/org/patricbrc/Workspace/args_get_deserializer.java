package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class args_get_deserializer extends JsonDeserializer<args_get>
{
    public args_get deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	args_get res = new args_get();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in args_get_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.input = p.readValueAs(get_params.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit args_get_deserializer with token " + t);

	return res;
    }
}
