package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class return_set_permissions_deserializer extends JsonDeserializer<return_set_permissions>
{
    public return_set_permissions deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	return_set_permissions res = new return_set_permissions();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in return_set_permissions_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.output = p.readValueAs(ObjectMeta.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit return_set_permissions_deserializer with token " + t);

	return res;
    }
}
