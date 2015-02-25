package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class args_ls_deserializer extends JsonDeserializer<args_ls>
{
    public args_ls deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	args_ls res = new args_ls();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in args_ls_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.input = p.readValueAs(list_params.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit args_ls_deserializer with token " + t);

	return res;
    }
}
