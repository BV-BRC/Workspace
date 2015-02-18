package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class return_get_archive_url_deserializer extends JsonDeserializer<return_get_archive_url>
{
    public return_get_archive_url deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	return_get_archive_url res = new return_get_archive_url();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in return_get_archive_url_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.url = p.readValueAs(String.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit return_get_archive_url_deserializer with token " + t);

	return res;
    }
}
