package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class ObjectMeta_deserializer extends JsonDeserializer<ObjectMeta>
{
    public ObjectMeta deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	ObjectMeta res = new ObjectMeta();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in ObjectMeta_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.e_1 = p.readValueAs(String.class);
	res.e_2 = p.readValueAs(String.class);
	res.e_3 = p.readValueAs(String.class);
	res.creation_time = p.readValueAs(String.class);
	res.e_5 = p.readValueAs(String.class);
	res.object_owner = p.readValueAs(String.class);
	res.e_7 = p.readValueAs(Integer.class);
	res.e_8 = p.readValueAs(new TypeReference<Map<String, String>>(){});
	res.e_9 = p.readValueAs(new TypeReference<Map<String, String>>(){});
	res.user_permission = p.readValueAs(String.class);
	res.global_permission = p.readValueAs(String.class);
	res.shockurl = p.readValueAs(String.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit ObjectMeta_deserializer with token " + t);

	return res;
    }
}
