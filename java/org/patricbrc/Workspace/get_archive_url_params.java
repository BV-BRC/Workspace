package org.patricbrc.Workspace;

import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;



/**
"get_archive_url" command
Description:
This function returns a URL from which an archive of the given 
objects may be downloaded. The download URL will only be valid for a limited
amount of time.

Parameters:
list<FullObjectPath> objects - list of full paths to objects to be archived
bool recursive - if true, recurse into folders
string archive_name - name to be given to the archive file
string archive_type - type of archive, one of "zip", "tar.gz", "tar.bz2"
**/

public class get_archive_url_params
{
    public List<String> objects;
    public Integer recursive;
    public String archive_name;
    public String archive_type;
}


