package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class return_list_permissions_deserializer extends JsonDeserializer<return_list_permissions>
{
    public return_list_permissions deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	return_list_permissions res = new return_list_permissions();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in return_list_permissions_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.output = p.readValueAs(new TypeReference<Map<String, List<Workspace_tuple_3>>>(){});
	JsonToken t = p.nextToken();
//	System.out.println("exit return_list_permissions_deserializer with token " + t);

	return res;
    }
}
