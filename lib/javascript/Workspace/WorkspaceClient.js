

function Workspace(url, auth, auth_cb) {

    this.url = url;
    var _url = url;
    var deprecationWarningSent = false;

    function deprecationWarning() {
        if (!deprecationWarningSent) {
            deprecationWarningSent = true;
            if (!window.console) return;
            console.log(
                "DEPRECATION WARNING: '*_async' method names will be removed",
                "in a future version. Please use the identical methods without",
                "the'_async' suffix.");
        }
    }

    var _auth = auth ? auth : { 'token' : '', 'user_id' : ''};
    var _auth_cb = auth_cb;


    this.create_workspace = function (workspace, permission, metadata, _callback, _errorCallback) {
    return json_call_ajax("Workspace.create_workspace",
        [workspace, permission, metadata], 1, _callback, _errorCallback);
};

    this.create_workspace_async = function (workspace, permission, metadata, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.create_workspace", [workspace, permission, metadata], 1, _callback, _error_callback);
    };

    this.save_objects = function (objects, overwrite, _callback, _errorCallback) {
    return json_call_ajax("Workspace.save_objects",
        [objects, overwrite], 1, _callback, _errorCallback);
};

    this.save_objects_async = function (objects, overwrite, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.save_objects", [objects, overwrite], 1, _callback, _error_callback);
    };

    this.create_upload_node = function (objects, overwrite, _callback, _errorCallback) {
    return json_call_ajax("Workspace.create_upload_node",
        [objects, overwrite], 1, _callback, _errorCallback);
};

    this.create_upload_node_async = function (objects, overwrite, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.create_upload_node", [objects, overwrite], 1, _callback, _error_callback);
    };

    this.get_objects = function (objects, _callback, _errorCallback) {
    return json_call_ajax("Workspace.get_objects",
        [objects], 1, _callback, _errorCallback);
};

    this.get_objects_async = function (objects, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.get_objects", [objects], 1, _callback, _error_callback);
    };

    this.get_objects_by_reference = function (objects, _callback, _errorCallback) {
    return json_call_ajax("Workspace.get_objects_by_reference",
        [objects], 1, _callback, _errorCallback);
};

    this.get_objects_by_reference_async = function (objects, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.get_objects_by_reference", [objects], 1, _callback, _error_callback);
    };

    this.list_workspace_contents = function (directory, includeSubDirectories, excludeObjects, Recursive, _callback, _errorCallback) {
    return json_call_ajax("Workspace.list_workspace_contents",
        [directory, includeSubDirectories, excludeObjects, Recursive], 1, _callback, _errorCallback);
};

    this.list_workspace_contents_async = function (directory, includeSubDirectories, excludeObjects, Recursive, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.list_workspace_contents", [directory, includeSubDirectories, excludeObjects, Recursive], 1, _callback, _error_callback);
    };

    this.list_workspace_hierarchical_contents = function (directory, includeSubDirectories, excludeObjects, Recursive, _callback, _errorCallback) {
    return json_call_ajax("Workspace.list_workspace_hierarchical_contents",
        [directory, includeSubDirectories, excludeObjects, Recursive], 1, _callback, _errorCallback);
};

    this.list_workspace_hierarchical_contents_async = function (directory, includeSubDirectories, excludeObjects, Recursive, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.list_workspace_hierarchical_contents", [directory, includeSubDirectories, excludeObjects, Recursive], 1, _callback, _error_callback);
    };

    this.list_workspaces = function (owned_only, no_public, _callback, _errorCallback) {
    return json_call_ajax("Workspace.list_workspaces",
        [owned_only, no_public], 1, _callback, _errorCallback);
};

    this.list_workspaces_async = function (owned_only, no_public, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.list_workspaces", [owned_only, no_public], 1, _callback, _error_callback);
    };

    this.search_for_workspaces = function (query, _callback, _errorCallback) {
    return json_call_ajax("Workspace.search_for_workspaces",
        [query], 1, _callback, _errorCallback);
};

    this.search_for_workspaces_async = function (query, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.search_for_workspaces", [query], 1, _callback, _error_callback);
    };

    this.search_for_workspace_objects = function (query, _callback, _errorCallback) {
    return json_call_ajax("Workspace.search_for_workspace_objects",
        [query], 1, _callback, _errorCallback);
};

    this.search_for_workspace_objects_async = function (query, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.search_for_workspace_objects", [query], 1, _callback, _error_callback);
    };

    this.create_workspace_directory = function (directory, metadata, _callback, _errorCallback) {
    return json_call_ajax("Workspace.create_workspace_directory",
        [directory, metadata], 1, _callback, _errorCallback);
};

    this.create_workspace_directory_async = function (directory, metadata, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.create_workspace_directory", [directory, metadata], 1, _callback, _error_callback);
    };

    this.copy_objects = function (objects, overwrite, recursive, _callback, _errorCallback) {
    return json_call_ajax("Workspace.copy_objects",
        [objects, overwrite, recursive], 1, _callback, _errorCallback);
};

    this.copy_objects_async = function (objects, overwrite, recursive, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.copy_objects", [objects, overwrite, recursive], 1, _callback, _error_callback);
    };

    this.move_objects = function (objects, overwrite, recursive, _callback, _errorCallback) {
    return json_call_ajax("Workspace.move_objects",
        [objects, overwrite, recursive], 1, _callback, _errorCallback);
};

    this.move_objects_async = function (objects, overwrite, recursive, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.move_objects", [objects, overwrite, recursive], 1, _callback, _error_callback);
    };

    this.delete_workspace = function (workspace, _callback, _errorCallback) {
    return json_call_ajax("Workspace.delete_workspace",
        [workspace], 1, _callback, _errorCallback);
};

    this.delete_workspace_async = function (workspace, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.delete_workspace", [workspace], 1, _callback, _error_callback);
    };

    this.delete_objects = function (objects, delete_directories, force, _callback, _errorCallback) {
    return json_call_ajax("Workspace.delete_objects",
        [objects, delete_directories, force], 1, _callback, _errorCallback);
};

    this.delete_objects_async = function (objects, delete_directories, force, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.delete_objects", [objects, delete_directories, force], 1, _callback, _error_callback);
    };

    this.delete_workspace_directory = function (directory, force, _callback, _errorCallback) {
    return json_call_ajax("Workspace.delete_workspace_directory",
        [directory, force], 1, _callback, _errorCallback);
};

    this.delete_workspace_directory_async = function (directory, force, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.delete_workspace_directory", [directory, force], 1, _callback, _error_callback);
    };

    this.reset_global_permission = function (workspace, global_permission, _callback, _errorCallback) {
    return json_call_ajax("Workspace.reset_global_permission",
        [workspace, global_permission], 1, _callback, _errorCallback);
};

    this.reset_global_permission_async = function (workspace, global_permission, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.reset_global_permission", [workspace, global_permission], 1, _callback, _error_callback);
    };

    this.set_workspace_permissions = function (workspace, permissions, _callback, _errorCallback) {
    return json_call_ajax("Workspace.set_workspace_permissions",
        [workspace, permissions], 1, _callback, _errorCallback);
};

    this.set_workspace_permissions_async = function (workspace, permissions, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.set_workspace_permissions", [workspace, permissions], 1, _callback, _error_callback);
    };

    this.list_workspace_permissions = function (workspaces, _callback, _errorCallback) {
    return json_call_ajax("Workspace.list_workspace_permissions",
        [workspaces], 1, _callback, _errorCallback);
};

    this.list_workspace_permissions_async = function (workspaces, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.list_workspace_permissions", [workspaces], 1, _callback, _error_callback);
    };
 

    /*
     * JSON call using jQuery method.
     */
    function json_call_ajax(method, params, numRets, callback, errorCallback) {
        var deferred = $.Deferred();

        if (typeof callback === 'function') {
           deferred.done(callback);
        }

        if (typeof errorCallback === 'function') {
           deferred.fail(errorCallback);
        }

        var rpc = {
            params : params,
            method : method,
            version: "1.1",
            id: String(Math.random()).slice(2),
        };

        var beforeSend = null;
        var token = (_auth_cb && typeof _auth_cb === 'function') ? _auth_cb()
            : (_auth.token ? _auth.token : null);
        if (token != null) {
            beforeSend = function (xhr) {
                xhr.setRequestHeader("Authorization", token);
            }
        }

        var xhr = jQuery.ajax({
            url: _url,
            dataType: "text",
            type: 'POST',
            processData: false,
            data: JSON.stringify(rpc),
            beforeSend: beforeSend,
            success: function (data, status, xhr) {
                var result;
                try {
                    var resp = JSON.parse(data);
                    result = (numRets === 1 ? resp.result[0] : resp.result);
                } catch (err) {
                    deferred.reject({
                        status: 503,
                        error: err,
                        url: _url,
                        resp: data
                    });
                    return;
                }
                deferred.resolve(result);
            },
            error: function (xhr, textStatus, errorThrown) {
                var error;
                if (xhr.responseText) {
                    try {
                        var resp = JSON.parse(xhr.responseText);
                        error = resp.error;
                    } catch (err) { // Not JSON
                        error = "Unknown error - " + xhr.responseText;
                    }
                } else {
                    error = "Unknown Error";
                }
                deferred.reject({
                    status: 500,
                    error: error
                });
            }
        });

        var promise = deferred.promise();
        promise.xhr = xhr;
        return promise;
    }
}


