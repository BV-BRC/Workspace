

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

    if (typeof(_url) != "string" || _url.length == 0) {
        _url = "https://p3.theseed.org/services/Workspace";
    }
    var _auth = auth ? auth : { 'token' : '', 'user_id' : ''};
    var _auth_cb = auth_cb;


    this.create = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.create",
        [input], 1, _callback, _errorCallback);
};

    this.create_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.create", [input], 1, _callback, _error_callback);
    };

    this.update_metadata = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.update_metadata",
        [input], 1, _callback, _errorCallback);
};

    this.update_metadata_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.update_metadata", [input], 1, _callback, _error_callback);
    };

    this.get = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.get",
        [input], 1, _callback, _errorCallback);
};

    this.get_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.get", [input], 1, _callback, _error_callback);
    };

    this.update_auto_meta = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.update_auto_meta",
        [input], 1, _callback, _errorCallback);
};

    this.update_auto_meta_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.update_auto_meta", [input], 1, _callback, _error_callback);
    };

    this.get_download_url = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.get_download_url",
        [input], 1, _callback, _errorCallback);
};

    this.get_download_url_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.get_download_url", [input], 1, _callback, _error_callback);
    };

    this.get_archive_url = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.get_archive_url",
        [input], 3, _callback, _errorCallback);
};

    this.get_archive_url_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.get_archive_url", [input], 3, _callback, _error_callback);
    };

    this.ls = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.ls",
        [input], 1, _callback, _errorCallback);
};

    this.ls_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.ls", [input], 1, _callback, _error_callback);
    };

    this.copy = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.copy",
        [input], 1, _callback, _errorCallback);
};

    this.copy_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.copy", [input], 1, _callback, _error_callback);
    };

    this.delete = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.delete",
        [input], 1, _callback, _errorCallback);
};

    this.delete_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.delete", [input], 1, _callback, _error_callback);
    };

    this.set_permissions = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.set_permissions",
        [input], 1, _callback, _errorCallback);
};

    this.set_permissions_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.set_permissions", [input], 1, _callback, _error_callback);
    };

    this.list_permissions = function (input, _callback, _errorCallback) {
    return json_call_ajax("Workspace.list_permissions",
        [input], 1, _callback, _errorCallback);
};

    this.list_permissions_async = function (input, _callback, _error_callback) {
        deprecationWarning();
        return json_call_ajax("Workspace.list_permissions", [input], 1, _callback, _error_callback);
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


