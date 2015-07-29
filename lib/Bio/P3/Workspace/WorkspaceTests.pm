{
	package Bio::P3::Workspace::WorkspaceTests;
	
	use strict;
	use Bio::P3::Workspace::ScriptHelpers; 
	use Test::More;
	use Data::Dumper;
	use Config::Simple;
	
	sub new {
	    my($class,$bin) = @_;
	    my $c = Config::Simple->new();
		$c->read($bin."test.cfg");
	    my $self = {
			testcount => 0,
			dumpoutput => $c->param("WorkspaceTest.dumpoutput"),
			showerrors => $c->param("WorkspaceTest.showerrors"),
			user => $c->param("WorkspaceTest.user"),
			password => $c->param("WorkspaceTest.password"),
			usertwo => $c->param("WorkspaceTest.adminuser"),
			passwordtwo => $c->param("WorkspaceTest.adminpassword"),
			token => undef,
			tokentwo => undef,
			url => $c->param("WorkspaceTest.url"),
			testoutput => {}
	    };
	    $self->{token} = Bio::P3::Workspace::ScriptHelpers::login({
			user_id => $self->{user}, password => $self->{password},tokenonly => 1
		});
		$self->{tokentwo} = Bio::P3::Workspace::ScriptHelpers::login({
			user_id => $self->{usertwo}, password => $self->{passwordtwo},tokenonly => 1
		});
	    $ENV{KB_INTERACTIVE} = 1;
	    if (defined($c->param("WorkspaceTest.serverconfig"))) {
	    	$ENV{KB_DEPLOYMENT_CONFIG} = $bin.$c->param("WorkspaceTest.serverconfig");
	    }
	    if (!defined($self->{url}) || $self->{url} eq "impl") {
	    	print "Loading server with this config: ".$ENV{KB_DEPLOYMENT_CONFIG}."\n";
	    	require "Bio/P3/Workspace/WorkspaceImpl.pm";
	    	$self->{obj} = Bio::P3::Workspace::WorkspaceImpl->new();
	    } else {
	    	require "Bio/P3/Workspace/WorkspaceClient.pm";
	    	$self->{clientobj} = Bio::P3::Workspace::WorkspaceClient->new($self->{url},token => $self->{token});
	    	$self->{clientobjtwo} = Bio::P3::Workspace::WorkspaceClient->new($self->{url},token => $self->{tokentwo});
	    }
	    return bless $self, $class;
	}
	
	sub set_user {
		my($self,$user) = @_;
		if (!defined($self->{url}) || $self->{url} eq "impl") {
			if ($user == 2) {
				$Bio::P3::Workspace::WorkspaceImpl::CallContext = Bio::P3::Workspace::WorkspaceImpl::CallContext->new($self->{tokentwo},"test",$self->{usertwo});
			} else {
				$Bio::P3::Workspace::WorkspaceImpl::CallContext = Bio::P3::Workspace::WorkspaceImpl::CallContext->new($self->{token},"test",$self->{user});
			}
		} else {
			if ($user == 2) {
				$self->{obj} = $self->{clientobjtwo};
			} else {
				$self->{obj} = $self->{clientobj};
			}
		}
	}
	
	sub test_harness {
		my($self,$function,$parameters,$name,$tests,$fail_to_pass,$dependency,$user) = @_;
		$self->set_user($user);
		$self->{testoutput}->{$name} = {
			output => undef,
			"index" => $self->{testcount},
			tests => $tests,
			command => $function,
			parameters => $parameters,
			dependency => $dependency,
			fail_to_pass => $fail_to_pass,
			pass => 1,
			function => 1,
			status => "Failed initial function test!"
		};
		$self->{testcount}++;
		if (defined($dependency) && $self->{testoutput}->{$dependency}->{function} != 1) {
			$self->{testoutput}->{$name}->{pass} = -1;
			$self->{testoutput}->{$name}->{function} = -1;
			$self->{testoutput}->{$name}->{status} = "Test skipped due to failed dependency!";
			return;
		}
		my $output;
		eval {
			if (defined($parameters)) {
				$output = $self->{obj}->$function($parameters);
			} else {
				$output = $self->{obj}->$function();
			}
		};
		my $errors;
		if ($@) {
			$errors = $@;
		}
		$self->{completetestcount}++;
		if (defined($output)) {
			$self->{testoutput}->{$name}->{output} = $output;
			$self->{testoutput}->{$name}->{function} = 1;
			if (defined($fail_to_pass) && $fail_to_pass == 1) {
				$self->{testoutput}->{$name}->{pass} = 0;
				$self->{testoutput}->{$name}->{status} = $name." worked, but should have failed!"; 
				ok $self->{testoutput}->{$name}->{pass} == 1, $self->{testoutput}->{$name}->{status};
			} else {
				ok 1, $name." worked as expected!";
				for (my $i=0; $i < @{$tests}; $i++) {
					$self->{completetestcount}++;
					$tests->[$i]->[2] = eval $tests->[$i]->[0];
					if ($tests->[$i]->[2] == 0) {
						$self->{testoutput}->{$name}->{pass} = 0;
						$self->{testoutput}->{$name}->{status} = $name." worked, but sub-tests failed!"; 
					}
					ok $tests->[$i]->[2] == 1, $tests->[$i]->[1];
				}
			}
		} else {
			$self->{testoutput}->{$name}->{function} = 0;
			if (defined($fail_to_pass) && $fail_to_pass == 1) {
				$self->{testoutput}->{$name}->{pass} = 1;
				$self->{testoutput}->{$name}->{status} = $name." failed as expected!";
			} else {
				$self->{testoutput}->{$name}->{pass} = 0;
				$self->{testoutput}->{$name}->{status} = $name." failed to function at all!";
			}
			ok $self->{testoutput}->{$name}->{pass} == 1, $self->{testoutput}->{$name}->{status};
			if ($self->{showerrors} && $self->{testoutput}->{$name}->{pass} == 0 && defined($errors)) {
				print "Errors:\n".$errors."\n";
			}
		}
		if ($self->{dumpoutput}) {
			print "$function output:\n".Data::Dumper->Dump([$output])."\n\n";
		}
		return $output;
	}
	
	sub run_tests {
		my($self) = @_;
		
		#Clearing out previous test results
		my $output = $self->test_harness("ls",{
			paths => ["/".$self->{usertwo}],
		},"Initial listing of all workspaces owned by ".$self->{usertwo},[],0,undef,2);
		if (defined($output->{"/".$self->{usertwo}})) {
			my $hash = {};
			for (my $i=0; $i < @{$output->{"/".$self->{usertwo}}}; $i++) {
				my $item = $output->{"/".$self->{usertwo}}->[$i];
				if ($item->[2].$item->[0] eq "/".$self->{usertwo}."/TestWorkspace") {
					my $output = $self->test_harness("delete",{
						objects => ["/".$self->{usertwo}."/TestWorkspace"],
						force => 1,
						deleteDirectories => 1,
						adminmode => 1
					},"Deleting TestWorkspace ".$self->{usertwo},[],0,undef,2);
				}
			}
		}
		
		$output = $self->test_harness("ls",{
			paths => ["/".$self->{user}],
		},"Initial listing of all workspaces owned by ".$self->{user},[],0,undef,1);
		if (defined($output->{"/".$self->{user}})) {
			my $hash = {};
			for (my $i=0; $i < @{$output->{"/".$self->{user}}}; $i++) {
				my $item = $output->{"/".$self->{user}}->[$i];
				if ($item->[2].$item->[0] eq "/".$self->{user}."/TestWorkspace") {
					my $output = $self->test_harness("delete",{
						objects => ["/".$self->{user}."/TestWorkspace"],
						force => 1,
						deleteDirectories => 1,
						adminmode => 1
					},"Deleting TestWorkspace of ".$self->{user},[],0,undef,1);
				} elsif ($item->[2].$item->[0] eq "/".$self->{user}."/TestAdminWorkspace") {
					my $output = $self->test_harness("delete",{
						objects => ["/".$self->{user}."/TestAdminWorkspace"],
						force => 1,
						deleteDirectories => 1,
						adminmode => 1
					},"Deleting TestAdminWorkspace of ".$self->{user},[],0,undef,2);
				}
			}
		}
		
		#Creating a private workspace as "$testuserone"
		$output = $self->test_harness("create",{
			objects => [["/".$self->{user}."/TestWorkspace","folder",{description => "My first workspace!"},undef]],
			permission => "n"
		},"Creating top level TestWorkspace directory for ".$self->{user},[],0,undef,1);
		#user = reviewer
		#usertwo = chenry
		
		#Creating a public workspace as "$testusertwo"
		$output = $self->test_harness("create",{
			objects => [["/".$self->{usertwo}."/TestWorkspace","folder",{description => "My first workspace!"},undef]],
			permission => "r"
		},"Creating top level TestWorkspace directory for ".$self->{usertwo},[],0,undef,2);
		
		#Testing testusertwo acting as an adminitrator
		$output = $self->test_harness("create",{
			objects => [["/".$self->{user}."/TestAdminWorkspace","folder",{description => "My first admin workspace!"},undef,0]],
			permission => "r",
			adminmode => 1,
			setowner => $self->{user}
		},"Creating top level TestAdminWorkspace for ".$self->{user}." with ".$self->{usertwo}." as admin",[],0,undef,2);
		
		#Attempting to make a workspace for another user
		$output = $self->test_harness("create",{
			objects => [["/".$self->{user}."/TestWorkspaceTwo","folder",{description => "My second workspace!"},undef]],
			permission => "r"
		},"Creating top level directory TestWorkspaceTwo for ".$self->{user}." as ".$self->{usertwo}." should fail",[],1,undef,2);
		
		#Listing workspaces as user one
		$output = $self->test_harness("ls",{
			paths => ["/".$self->{user}]
		},"Using ls function as ".$self->{user},[
			["\$output->{\"/".$self->{user}."\"}->[0]->[5] eq \"".$self->{user}."\"","First workspace returned is owned by ".$self->{user}]
		],0,undef,1);
		
		#Listing workspaces as user two
		$output = $self->test_harness("ls",{
			paths => ["/".$self->{usertwo}]
		},"Using ls function as ".$self->{usertwo},[
			["\$output->{\"/".$self->{usertwo}."\"}->[0]->[5] eq \"".$self->{usertwo}."\"","First workspace returned is owned by ".$self->{usertwo}]
		],0,undef,2);
		
		#Getting workspace metadata
		$output = $self->test_harness("get",{
			metadata_only => 1,
			objects => ["/".$self->{usertwo}."/TestWorkspace"]
		},"Using get function to retrieve TestWorkspace metadata only",[
			["defined(\$output->[0]->[0])","Metadata for object contained in output"]
		],0,undef,2);
		
		#Saving an object
		$output = $self->test_harness("create",{
			objects => [["/".$self->{user}."/TestWorkspace/testdir/testdir2/testdir3/testobj","genome",{"Description" => "My first object!"},{
				id => "83333.1",
				scientific_name => "Escherichia coli",
				domain => "Bacteria",
				dna_size => 4000000,
				num_contigs => 1,
				gc_content => 0.5,
				taxonomy => "Bacteria",
				features => [{}]
			}]]
		},"Creating a genome object",[
			["defined(\$output->[3])","Getting metadata for created objects back"],
			["\$output->[3]->[1] eq \"genome\"","Object has type genome"]
		],0,undef,1);
		
		#Recreating an existing folder
		$output = $self->test_harness("create",{
			objects => [["/".$self->{user}."/TestWorkspace/testdir","folder",{"Description" => "My recreated folder!"},undef]]
		},"Recreating new object folder",[["!defined(\$output->[0])","Recreation of existing folder returns empty array"]],0,undef,1);
		
		#Saving contigs
		$output = $self->test_harness("create",{
			objects => [["/".$self->{user}."/TestWorkspace/testdir/testdir2/testdir3/contigs","contigs",{"Description" => "My first contigs!"},">gi|284931009|gb|CP001873.1| Mycoplasma gallisepticum str. F, complete genome
				TTTTTATTATTAACCATGAGAATTGTTGATAAATCTGTGGATAACTCTAAAAAAATTCCGGATTTATAAA
				AGTACATTAAAATATTTATATTTTAATGTAAATATTATATCACTTTTTCACAAAAACGTGTATTATATAT
				AAGGAGTTTTGTAAATTATTTAACTATATTACTATGTAATATAGTTATTATATCAAAACAAACTAAAACA
				GTAGAGCAACCTTTAAAAATTAACTAAAAACTAAATACAAATTTGTTTATAGACGAAAGTTTTTCTATTA
				ATATCCCCACATTAACTCTATCAAAACCCCTATACTAAAAAAAACACACTCTGAATACATAACTTGTATG
				TAAAGTTTGAGTGAAGTTAAATCGCTTTAATATTGTAACAATATTGTTTGTAAAAATATTTATTTAATAT
				GAAAAAAATATTGTGATTTTTATCGGAAATATTGTGATTTTCTAATTCAGGCCAATTAAAAATATCAAAA
				CTAATTACTTAAATAAAAATATCAATAAATAAATTAAAAAACTTATTAACATTTCTACTAAGAGAGTTCG
				TATTTGGAAATAATATTAAAGTAATACACAATATTAAAAAAATATTATTAGTATTTAAACGATTAAGTAC
				TTTTTCATTCTTTTGTCTATCTGTAAAAGACACTAGGTAAGGATTACTTTATTAACAAGATAAAGAGAAA
				AGAATTTATTTTTAATAATACGATTTTAATATTTTTAAAATATTATTCAATTTACGTTGTTTTATTACCA
				AAAATAGAATATTAAAACAATATTTATAAGTTAATTAAAATTAATACTTTTTAAAACAAAACAACAATAT
				TATTTCAATATGGTCACAGTAGTCACAATAAAGTTGATAATATTTAAATAATATTAATTAAATATTTATT
				CAAGAATTTATTATTCTTGAATAACAGCAAAAAACTTTTATAGAACTGAAGAGCATTCTTAAAAAAGAAA
				AAACCTAATGCTAACGGCATCAGAACTAACTAATACGAAAATAATATTTGATTACAAGAGAAGCAAATAA
				TATTGTTAAGGGATCAATATTGTAATAATATTAAAATCATATCATAGAAGGTTAATGCTTACCAGTAATA
				CTACTAACAGATAGTTTAATGTAGATGTATTAATATTGTAATAATATTAAAGTCATATTGTAAAAAGTTT
				ATCTTTAGCAAAAAATACTACTAAACGGAGAATTTAATATAGATATATCATTAATATTTAAATAATATTA
				CTTCATAAGGAAGCAATAATAACAAATATTCTTAACTTATAAATAAGCAATATATTAATAATATGGTAAC
				AATATTGTTTTAATACTACATTCGTAATAAAGCTAGTTTAAGAGAATATTAAAATAATATTGGTTTGAAA
				CTGTTAAAAATTATCTTTCTTAACAATATTGCCAAATCCGATTTTGCTTTACTTCAACGGGAATAAGTTT
				TTAACTAAACTTTGCACTCTAATTACTAAAATATAAAAACAAACTTAGGACTAAAAAGATTTGAAATGAT
				TAGCGTAAGGCTGAGGTTTTAGTTTAAATATACAAAGTAAAGTATTTTTTATTTAAAACAAGTTTTAAAA
				ATACCAAAATGATATTTTATTAATATTGTTATCTATATCAAGATTTATAATATGTTTTCTTGAGCACTTT
				TTTTCAAGATTGCCTAATAATAATATATTTTTAATATTTAATTACTAGGAAAATAATATTGCGAAAATTA"
			]]	
		},"Saving genome contigs",[
			["defined(\$output->[0])","Getting metadata for created object back"],
			["\$output->[0]->[1] eq \"contigs\"","Object has type contigs"]
		],0,undef,1);
		
		#Creating shock nodes
		$output = $self->test_harness("create",{
			objects => [["/".$self->{user}."/TestWorkspace/testdir/testdir2/testdir3/shockobj","genome",{"Description" => "My first shock object!"}]],
			createUploadNodes => 1
		},"Creating an upload node",[
			["defined(\$output->[0])","Getting metadata for created object back"],
			["\$output->[0]->[1] eq \"genome\"","Object has type genome"],
			["defined(\$output->[0]->[11])","Shock URL is returned"]
			
		],0,undef,1);
		
		#Uploading file to newly created shock node
		print "Filename:".$self->{bin}."testdata.txt\n";
		my $req = HTTP::Request::Common::POST($output->[0]->[11],Authorization => "OAuth ".$self->{token},Content_Type => 'multipart/form-data',Content => [upload => [$self->{bin}."testdata.txt"]]);
		$req->method('PUT');
		my $ua = LWP::UserAgent->new();
		my $res = $ua->request($req);
		if ($self->{dumpoutput} == 1) {
			print "File uploaded:\n".Data::Dumper->Dump([$res])."\n\n";
		}
		
		#Updating metadata
		$output = $self->test_harness("update_metadata",{
			objects => [["/".$self->{user}."/TestWorkspace/testdir/testdir2/testdir3/shockobj",undef,undef,0]],
			autometadata => 0,
			adminmode => 1
		},"Running update metadata function",[
			["defined(\$output->[0])","Metadata update should return metadata for updated object"]
		],0,undef,2);
		
		#Retrieving shock object through workspace API
		$output = $self->test_harness("get",{
			objects => ["/".$self->{user}."/TestWorkspace/testdir/testdir2/testdir3/shockobj"]
		},"Running get function to retreive shock object",[
			["defined(\$output->[0])","Get function should return the object retrieved"]
		],0,undef,1);
		
		#Listing objects
		$output = $self->test_harness("ls",{
			paths => ["/".$self->{user}."/TestWorkspace/testdir/testdir2"],
			excludeDirectories => 0,
			excludeObjects => 0,
			recursive => 1
		},"Running ls function recursively on directory",[
			["defined(\$output->{\"/".$self->{user}."/TestWorkspace/testdir/testdir2\"})","Returns contents of subdirectory"]
		],0,undef,1);
		
		$output = $self->test_harness("ls",{
			paths => ["/".$self->{user}."/TestWorkspace"],
			excludeDirectories => 0,
			excludeObjects => 0,
			recursive => 0
		},"Running basic ls on workspace",[
			["defined(\$output->{\"/".$self->{user}."/TestWorkspace\"}->[0]) && !defined(\$output->{\"/".$self->{user}."/TestWorkspace\"}->[1])","Returns contents with only one item"]
		],0,undef,1);
		
		$output = $self->test_harness("ls",{
			paths => ["/".$self->{user}."/TestWorkspace"],
			excludeDirectories => 1,
			excludeObjects => 0,
			recursive => 1
		},"Running ls on workspace recursively with directories excluded",[
			["defined(\$output->{\"/".$self->{user}."/TestWorkspace\"}->[2]) && !defined(\$output->{\"/".$self->{user}."/TestWorkspace\"}->[3])","Returns contents with only three items"]
		],0,undef,1);
		
		$output = $self->test_harness("ls",{
			paths => ["/".$self->{user}."/TestWorkspace"],
			excludeDirectories => 0,
			excludeObjects => 1,
			recursive => 1
		},"Running ls on workspace recursively with objects excluded",[
			["defined(\$output->{\"/".$self->{user}."/TestWorkspace\"}->[2]) && !defined(\$output->{\"/".$self->{user}."/TestWorkspace\"}->[3])","Returns contents with only three items"]
		],0,undef,1);
		
		#Listing objects hierarchically
		$output = $self->test_harness("ls",{
			paths => ["/".$self->{user}."/TestWorkspace"],
			excludeDirectories => 0,
			excludeObjects => 0,
			recursive => 1,
			fullHierachicalOutput => 1
		},"Running ls on workspace with hierarchical output",[
			["defined(\$output->{\"/".$self->{user}."/TestWorkspace\"}) && defined(\$output->{\"/".$self->{user}."/TestWorkspace/testdir\"})","Output folders exist as keys in output structure"]
		],0,undef,1);
		
		#Copying workspace object
		$output = $self->test_harness("copy",{
			objects => [["/".$self->{user}."/TestWorkspace/testdir","/".$self->{usertwo}."/TestWorkspace/copydir"]],
			recursive => 1
		},"Copying to read only workspace fails",[],1,undef,1);
				
		#Changing workspace permissions
		$output = $self->test_harness("set_permissions",{
			path => "/".$self->{usertwo}."/TestWorkspace",
			permissions => [[$self->{user},"w"]]
		},"Resetting permissions on workspace",[],0,undef,2);

		#Listing workspace permission
		$output = $self->test_harness("list_permissions",{
			objects => ["/".$self->{usertwo}."/TestWorkspace"]
		},"Listing workspace permissions",[
			["defined(\$output->{\"/".$self->{usertwo}."/TestWorkspace\"}->[0])","Workspace permissions returned"]
		],0,undef,2);
				
		#Copying workspace object
		$output = $self->test_harness("copy",{
			objects => [["/".$self->{user}."/TestWorkspace/testdir","/".$self->{usertwo}."/TestWorkspace/copydir"]],
			recursive => 1
		},"Copying object from one user workspace to another",[],0,undef,1);
		
		#Listing contents of workspace with copied objects
		$output = $self->test_harness("ls",{
			paths => ["/".$self->{usertwo}."/TestWorkspace"],
			excludeDirectories => 0,
			excludeObjects => 0,
			recursive => 1
		},"Listing contents of copied workspace",[
			["defined(\$output->{\"/".$self->{usertwo}."/TestWorkspace\"}->[0])","ls on copied workspace succeeded to return output"]
		],0,undef,1);
		
		#Changing global workspace permissions
		$output = $self->test_harness("set_permissions",{
			path => "/".$self->{user}."/TestWorkspace",
			new_global_permission => "w"
		},"Successfully changed global permissions!",[],0,undef,1);
		
		#Moving objects
		$output = $self->test_harness("copy",{
			objects => [["/".$self->{usertwo}."/TestWorkspace/copydir","/".$self->{user}."/TestWorkspace/movedir"]],
			recursive => 1,
			move => 1
		},"Successfully ran copy to move objects!",[],0,undef,2);
		
		#Deleting an object
		$output = $self->test_harness("delete",{
			objects => ["/".$self->{user}."/TestWorkspace/movedir/testdir2/testdir3/testobj","/".$self->{user}."/TestWorkspace/movedir/testdir2/testdir3/shockobj"]
		},"Successfully deleted object!",[],0,undef,1);
		
		$output = $self->test_harness("delete",{
			objects => ["/".$self->{user}."/TestWorkspace/movedir/testdir2/testdir3"],
			force => 1,
			deleteDirectories => 1
		},"Successfully deleted folder!",[],0,undef,1);
		
		#Deleting a directory
		$output = $self->test_harness("delete",{
			objects => ["/".$self->{user}."/TestWorkspace/movedir"],
			force => 1,
			deleteDirectories => 1
		},"Successfully deleted top-level directory!",[],0,undef,1);
		
		#Creating a directory
		$output = $self->test_harness("create",{
			objects => [["/".$self->{user}."/TestWorkspace/emptydir","folder",{},undef]]
		},"Successfully created a workspace directory!",[],0,undef,1);
		
		#Getting an object
		$output = $self->test_harness("get",{
			objects => ["/".$self->{user}."/TestWorkspace/testdir/testdir2/testdir3/testobj"]
		},"Successfully retrieved an object!",[
			["defined(\$output->[0]->[1])","Object retrieved with all data"]
		],0,undef,1);
		
		#Getting an object by reference
		$output = $self->test_harness("get",{
			objects => [$output->[0]->[0]->[4]]
		},"Successfully retrieved an object by UUID!",[
			["defined(\$output->[0]->[1])","Object retrieved with all data"]
		],0,undef,1);
		
		#Deleting workspaces
		$output = $self->test_harness("delete",{
			objects => ["/".$self->{user}."/TestWorkspace"],
			force => 1,
			deleteDirectories => 1
		},"Deleting entire top level directory for ".$self->{user}."!",[],0,undef,1);
		
		$output = $self->test_harness("delete",{
			objects => ["/".$self->{usertwo}."/TestWorkspace"],
			force => 1,
			deleteDirectories => 1
		},"Deleting entire top level directory for ".$self->{usertwo}."!",[],0,undef,2);
				
		done_testing($self->{completetestcount});
	}
}	

{
	package Bio::P3::Workspace::WorkspaceImpl::CallContext;
	
	use strict;
	
	sub new {
	    my($class,$token,$method,$user) = @_;
	    my $self = {
	        token => $token,
	        method => $method,
	        user_id => $user
	    };
	    return bless $self, $class;
	}
	sub user_id {
		my($self) = @_;
		return $self->{user_id};
	}
	sub token {
		my($self) = @_;
		return $self->{token};
	}
	sub method {
		my($self) = @_;
		return $self->{method};
	}
	sub log_debug {
		my($self,$msg) = @_;
		print STDERR $msg."\n";
	}
}

1;