compile_typespec \
	-impl Bio::P3::Workspace::WorkspaceImpl \
	-service Bio::P3::Workspace::Service \
	-psgi Workspace.psgi \
	-client Bio::P3::Workspace::WorkspaceClient \
	-js javascript/Workspace/WorkspaceClient \
	-py biop3/Workspace/WorkspaceClient \
	Workspace.spec lib