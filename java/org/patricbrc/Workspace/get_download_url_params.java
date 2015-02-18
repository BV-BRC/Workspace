package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
"get_download_url" command
Description:
This function returns a URL from which an object may be downloaded
without any other authentication required. The download URL will only be
valid for a limited amount of time. 

Parameters:
list<FullObjectPath> objects - list of full paths to objects for which URLs are to be constructed
**/

public class get_download_url_params
{
    public List<String> objects;
}


