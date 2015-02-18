package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class return_ls_deserializer extends JsonDeserializer<return_ls>
{
    public return_ls deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	return_ls res = new return_ls();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in return_ls_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.output = p.readValueAs(new TypeReference<Map<String, List<ObjectMeta>>>(){});
	JsonToken t = p.nextToken();
//	System.out.println("exit return_ls_deserializer with token " + t);

	return res;
    }
}
