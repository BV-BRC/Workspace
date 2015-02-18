package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class args_set_permissions_deserializer extends JsonDeserializer<args_set_permissions>
{
    public args_set_permissions deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	args_set_permissions res = new args_set_permissions();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in args_set_permissions_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.input = p.readValueAs(set_permissions_params.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit args_set_permissions_deserializer with token " + t);

	return res;
    }
}
