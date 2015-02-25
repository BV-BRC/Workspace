package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;


public class args_get_download_url_deserializer extends JsonDeserializer<args_get_download_url>
{
    public args_get_download_url deserialize(JsonParser p, DeserializationContext ctx)
	throws IOException, JsonProcessingException
    {
	args_get_download_url res = new args_get_download_url();
	if (!p.isExpectedStartArrayToken())
	{
		System.out.println("Bad parse in args_get_download_url_deserializer: " + p.getCurrentToken());
		return null;
	}
	p.nextToken();
	res.input = p.readValueAs(get_download_url_params.class);
	JsonToken t = p.nextToken();
//	System.out.println("exit args_get_download_url_deserializer with token " + t);

	return res;
    }
}
