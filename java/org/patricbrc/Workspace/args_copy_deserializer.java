package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class args_copy_deserializer extends JsonDeserializer<args_copy>
{
    public args_copy deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	args_copy res = new args_copy();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in args_copy_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.input = p.readValueAs(copy_params.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit args_copy_deserializer with token " + t);

	return res;
    }
}
