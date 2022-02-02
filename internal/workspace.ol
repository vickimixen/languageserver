from console import Console
from exec import Exec
from string_utils import StringUtils

from ..lsp import WorkspaceInterface

service Workspace {
	execution: concurrent
	
	embed Exec as exec
	embed Console as console
	embed StringUtils as stringUtils	

	inputPort WorkspaceInput {
		location: "local"
		interfaces: WorkspaceInterface
	}
	
	init {
		println@console( "workspace running" )()
	}

	main {
		[ didChangeWatchedFiles( notification ) ] {
			println@console( "Received didChangedWatchedFiles" )()
		}

		[ didChangeWorkspaceFolders( notification ) ] {
			newFolders -> notification.event.added
			removedFolders -> notification.event.removed
			for(i = 0, i<#newFolders, i++) {
				global.workspace.folders[#global.workspace.folders+(i+1)] = newFolders[i]
			}
			for(i = 0, i<#removedFolders, i++) {
				for(j = 0, i<#global.workspace.folders, j++) {
					if(global.workspace.folders[j] == removedFolders[i]) {
						undef( global.workspace.folders[j] )
					}
				}
			}
			println@console("workspacefolders in workspace file: "+global.workspace.folders[0].uri)()
		}

		[ didChangeConfiguration( notification ) ] {
			valueToPrettyString@stringUtils( notification )(res)
			println@console("didChangeConfiguration received " + res)()
		}

		[ executeCommand( commandParams )( commandResult ) {
			cmd -> commandParams.commandParams
			args -> commandParams.arguments
			command = cmd
			command.args = args
			exec@exec( command )( commandResult )
		} ]
	}
}