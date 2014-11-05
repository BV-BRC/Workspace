#BEGIN_HEADER
#END_HEADER


class Workspace:
    '''
    Module Name:
    Workspace

    Module Description:
    
    '''

    ######## WARNING FOR GEVENT USERS #######
    # Since asynchronous IO can lead to methods - even the same method -
    # interrupting each other, you must be *very* careful when using global
    # state. A method could easily clobber the state set by another while
    # the latter method is running.
    #########################################
    #BEGIN_CLASS_HEADER
    #END_CLASS_HEADER

    # config contains contents of config file in a hash or None if it couldn't
    # be found
    def __init__(self, config):
        #BEGIN_CONSTRUCTOR
        #END_CONSTRUCTOR
        pass

    def create_workspace(self, ctx, workspace, permission, metadata):
        # ctx is the context object
        # return variables are: returnVal
        #BEGIN create_workspace
        #END create_workspace

        # At some point might do deeper type checking...
        if not isinstance(returnVal, list):
            raise ValueError('Method create_workspace return value ' +
                             'returnVal is not type list as required.')
        # return the results
        return [returnVal]

    def save_objects(self, ctx, objects, overwrite):
        # ctx is the context object
        # return variables are: returnVal
        #BEGIN save_objects
        #END save_objects

        # At some point might do deeper type checking...
        if not isinstance(returnVal, list):
            raise ValueError('Method save_objects return value ' +
                             'returnVal is not type list as required.')
        # return the results
        return [returnVal]

    def create_upload_node(self, ctx, objects, overwrite):
        # ctx is the context object
        # return variables are: output
        #BEGIN create_upload_node
        #END create_upload_node

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method create_upload_node return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def get_objects(self, ctx, objects):
        # ctx is the context object
        # return variables are: output
        #BEGIN get_objects
        #END get_objects

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method get_objects return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def get_objects_by_reference(self, ctx, objects):
        # ctx is the context object
        # return variables are: output
        #BEGIN get_objects_by_reference
        #END get_objects_by_reference

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method get_objects_by_reference return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def list_workspace_contents(self, ctx, directory, includeSubDirectories, excludeObjects, Recursive):
        # ctx is the context object
        # return variables are: output
        #BEGIN list_workspace_contents
        #END list_workspace_contents

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method list_workspace_contents return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def list_workspace_hierarchical_contents(self, ctx, directory, includeSubDirectories, excludeObjects, Recursive):
        # ctx is the context object
        # return variables are: output
        #BEGIN list_workspace_hierarchical_contents
        #END list_workspace_hierarchical_contents

        # At some point might do deeper type checking...
        if not isinstance(output, dict):
            raise ValueError('Method list_workspace_hierarchical_contents return value ' +
                             'output is not type dict as required.')
        # return the results
        return [output]

    def list_workspaces(self, ctx, owned_only, no_public):
        # ctx is the context object
        # return variables are: output
        #BEGIN list_workspaces
        #END list_workspaces

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method list_workspaces return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def search_for_workspaces(self, ctx, query):
        # ctx is the context object
        # return variables are: output
        #BEGIN search_for_workspaces
        #END search_for_workspaces

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method search_for_workspaces return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def search_for_workspace_objects(self, ctx, query):
        # ctx is the context object
        # return variables are: output
        #BEGIN search_for_workspace_objects
        #END search_for_workspace_objects

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method search_for_workspace_objects return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def create_workspace_directory(self, ctx, directory, metadata):
        # ctx is the context object
        # return variables are: output
        #BEGIN create_workspace_directory
        #END create_workspace_directory

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method create_workspace_directory return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def copy_objects(self, ctx, objects, overwrite, recursive):
        # ctx is the context object
        # return variables are: output
        #BEGIN copy_objects
        #END copy_objects

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method copy_objects return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def move_objects(self, ctx, objects, overwrite, recursive):
        # ctx is the context object
        # return variables are: output
        #BEGIN move_objects
        #END move_objects

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method move_objects return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def delete_workspace(self, ctx, workspace):
        # ctx is the context object
        # return variables are: output
        #BEGIN delete_workspace
        #END delete_workspace

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method delete_workspace return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def delete_objects(self, ctx, objects, delete_directories, force):
        # ctx is the context object
        # return variables are: output
        #BEGIN delete_objects
        #END delete_objects

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method delete_objects return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def delete_workspace_directory(self, ctx, directory, force):
        # ctx is the context object
        # return variables are: output
        #BEGIN delete_workspace_directory
        #END delete_workspace_directory

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method delete_workspace_directory return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def reset_global_permission(self, ctx, workspace, global_permission):
        # ctx is the context object
        # return variables are: output
        #BEGIN reset_global_permission
        #END reset_global_permission

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method reset_global_permission return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def set_workspace_permissions(self, ctx, workspace, permissions):
        # ctx is the context object
        # return variables are: output
        #BEGIN set_workspace_permissions
        #END set_workspace_permissions

        # At some point might do deeper type checking...
        if not isinstance(output, list):
            raise ValueError('Method set_workspace_permissions return value ' +
                             'output is not type list as required.')
        # return the results
        return [output]

    def list_workspace_permissions(self, ctx, workspaces):
        # ctx is the context object
        # return variables are: output
        #BEGIN list_workspace_permissions
        #END list_workspace_permissions

        # At some point might do deeper type checking...
        if not isinstance(output, dict):
            raise ValueError('Method list_workspace_permissions return value ' +
                             'output is not type dict as required.')
        # return the results
        return [output]
