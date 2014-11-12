

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


    this.create_workspace = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.create_workspace",
        [input], 1, _callback, _errorCallback);
};

    this.create_workspace_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.create_workspace", [input], 1, _callback, _error_callback);
    };

    this.save_objects = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.save_objects",
        [input], 1, _callback, _errorCallback);
};

    this.save_objects_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.save_objects", [input], 1, _callback, _error_callback);
    };

    this.create_upload_node = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.create_upload_node",
        [input], 1, _callback, _errorCallback);
};

    this.create_upload_node_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.create_upload_node", [input], 1, _callback, _error_callback);
    };

    this.get_objects = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.get_objects",
        [input], 1, _callback, _errorCallback);
};

    this.get_objects_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.get_objects", [input], 1, _callback, _error_callback);
    };

    this.get_objects_by_reference = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.get_objects_by_reference",
        [input], 1, _callback, _errorCallback);
};

    this.get_objects_by_reference_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.get_objects_by_reference", [input], 1, _callback, _error_callback);
    };

    this.list_workspace_contents = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.list_workspace_contents",
        [input], 1, _callback, _errorCallback);
};

    this.list_workspace_contents_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.list_workspace_contents", [input], 1, _callback, _error_callback);
    };

    this.list_workspace_hierarchical_contents = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.list_workspace_hierarchical_contents",
        [input], 1, _callback, _errorCallback);
};

    this.list_workspace_hierarchical_contents_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.list_workspace_hierarchical_contents", [input], 1, _callback, _error_callback);
    };

    this.list_workspaces = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.list_workspaces",
        [input], 1, _callback, _errorCallback);
};

    this.list_workspaces_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.list_workspaces", [input], 1, _callback, _error_callback);
    };

    this.search_for_workspaces = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.search_for_workspaces",
        [input], 1, _callback, _errorCallback);
};

    this.search_for_workspaces_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.search_for_workspaces", [input], 1, _callback, _error_callback);
    };

    this.search_for_workspace_objects = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.search_for_workspace_objects",
        [input], 1, _callback, _errorCallback);
};

    this.search_for_workspace_objects_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.search_for_workspace_objects", [input], 1, _callback, _error_callback);
    };

    this.create_workspace_directory = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.create_workspace_directory",
        [input], 1, _callback, _errorCallback);
};

    this.create_workspace_directory_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.create_workspace_directory", [input], 1, _callback, _error_callback);
    };

    this.copy_objects = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.copy_objects",
        [input], 1, _callback, _errorCallback);
};

    this.copy_objects_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.copy_objects", [input], 1, _callback, _error_callback);
    };

    this.move_objects = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.move_objects",
        [input], 1, _callback, _errorCallback);
};

    this.move_objects_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.move_objects", [input], 1, _callback, _error_callback);
    };

    this.delete_workspace = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.delete_workspace",
        [input], 1, _callback, _errorCallback);
};

    this.delete_workspace_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.delete_workspace", [input], 1, _callback, _error_callback);
    };

    this.delete_objects = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.delete_objects",
        [input], 1, _callback, _errorCallback);
};

    this.delete_objects_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.delete_objects", [input], 1, _callback, _error_callback);
    };

    this.delete_workspace_directory = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.delete_workspace_directory",
        [input], 1, _callback, _errorCallback);
};

    this.delete_workspace_directory_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.delete_workspace_directory", [input], 1, _callback, _error_callback);
    };

    this.reset_global_permission = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.reset_global_permission",
        [input], 1, _callback, _errorCallback);
};

    this.reset_global_permission_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.reset_global_permission", [input], 1, _callback, _error_callback);
    };

    this.set_workspace_permissions = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.set_workspace_permissions",
        [input], 1, _callback, _errorCallback);
};

    this.set_workspace_permissions_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.set_workspace_permissions", [input], 1, _callback, _error_callback);
    };

    this.list_workspace_permissions = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.list_workspace_permissions",
        [input], 1, _callback, _errorCallback);
};

    this.list_workspace_permissions_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.list_workspace_permissions", [input], 1, _callback, _error_callback);
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


