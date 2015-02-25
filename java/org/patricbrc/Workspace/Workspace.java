package org.patricbrc.Workspace;

import java.io.Serializable;

import java.net.*;
import java.io.*;
import java.util.*;
import org.codehaus.jackson.map.*;
import org.codehaus.jackson.map.annotate.*;
import org.codehaus.jackson.type.*;
import org.codehaus.jackson.*;

import us.kbase.rpc.Caller;

public class Workspace
{
    public Caller caller;

    public Workspace(String url) throws MalformedURLException
    {
	caller = new Caller(url);
    }

    public Workspace(String url, String token) throws MalformedURLException
    {
	caller = new Caller(url, token);
    }



    public List<ObjectMeta> create(create_params input) throws Exception
    {
	try {
	    args_create args = new args_create();
	    args.input = input;

	    return_create res = caller.jsonrpc_call("Workspace.create", args, return_create.class);
	    return res.output;
	} catch (IOException e) {
	    System.out.println("Failed with exception: " + e);
	}
	return null;
    }


    public List<Workspace_tuple_2> get(get_params input) throws Exception
    {
	try {
	    args_get args = new args_get();
	    args.input = input;

	    return_get res = caller.jsonrpc_call("Workspace.get", args, return_get.class);
	    return res.output;
	} catch (IOException e) {
	    System.out.println("Failed with exception: " + e);
	}
	return null;
    }


    public List<String> get_download_url(get_download_url_params input) throws Exception
    {
	try {
	    args_get_download_url args = new args_get_download_url();
	    args.input = input;

	    return_get_download_url res = caller.jsonrpc_call("Workspace.get_download_url", args, return_get_download_url.class);
	    return res.urls;
	} catch (IOException e) {
	    System.out.println("Failed with exception: " + e);
	}
	return null;
    }


    public String get_archive_url(get_archive_url_params input) throws Exception
    {
	try {
	    args_get_archive_url args = new args_get_archive_url();
	    args.input = input;

	    return_get_archive_url res = caller.jsonrpc_call("Workspace.get_archive_url", args, return_get_archive_url.class);
	    return res.url;
	} catch (IOException e) {
	    System.out.println("Failed with exception: " + e);
	}
	return null;
    }


    public Map<String, List<ObjectMeta>> ls(list_params input) throws Exception
    {
	try {
	    args_ls args = new args_ls();
	    args.input = input;

	    return_ls res = caller.jsonrpc_call("Workspace.ls", args, return_ls.class);
	    return res.output;
	} catch (IOException e) {
	    System.out.println("Failed with exception: " + e);
	}
	return null;
    }


    public List<ObjectMeta> copy(copy_params input) throws Exception
    {
	try {
	    args_copy args = new args_copy();
	    args.input = input;

	    return_copy res = caller.jsonrpc_call("Workspace.copy", args, return_copy.class);
	    return res.output;
	} catch (IOException e) {
	    System.out.println("Failed with exception: " + e);
	}
	return null;
    }


    public List<ObjectMeta> delete(delete_params input) throws Exception
    {
	try {
	    args_delete args = new args_delete();
	    args.input = input;

	    return_delete res = caller.jsonrpc_call("Workspace.delete", args, return_delete.class);
	    return res.output;
	} catch (IOException e) {
	    System.out.println("Failed with exception: " + e);
	}
	return null;
    }


    public ObjectMeta set_permissions(set_permissions_params input) throws Exception
    {
	try {
	    args_set_permissions args = new args_set_permissions();
	    args.input = input;

	    return_set_permissions res = caller.jsonrpc_call("Workspace.set_permissions", args, return_set_permissions.class);
	    return res.output;
	} catch (IOException e) {
	    System.out.println("Failed with exception: " + e);
	}
	return null;
    }


    public Map<String, List<Workspace_tuple_3>> list_permissions(list_permissions_params input) throws Exception
    {
	try {
	    args_list_permissions args = new args_list_permissions();
	    args.input = input;

	    return_list_permissions res = caller.jsonrpc_call("Workspace.list_permissions", args, return_list_permissions.class);
	    return res.output;
	} catch (IOException e) {
	    System.out.println("Failed with exception: " + e);
	}
	return null;
    }

}


