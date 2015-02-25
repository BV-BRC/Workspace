package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class args_list_permissions_deserializer extends JsonDeserializer<args_list_permissions>
{
    public args_list_permissions deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	args_list_permissions res = new args_list_permissions();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in args_list_permissions_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.input = p.readValueAs(list_permissions_params.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit args_list_permissions_deserializer with token " + t);

	return res;
    }
}
