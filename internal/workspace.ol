/* MIT License
 *
 * Copyright (c) 2021 The Jolie Programming Language
 * Copyright (c) 2022 Vicki Mixen <vicki@mixen.dk>
 * Copyright (C) 2022 Fabrizio Montesi <famontesi@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.from console import Console
 */
from console import Console
from exec import Exec
from string_utils import StringUtils
from file import File
from runtime import Runtime
from ..inspectorJavaService.inspector import Inspector
from ..lsp import WorkspaceInterface, GlobalVariables

service Workspace {
	execution: concurrent

	embed Exec as Exec
	embed Console as Console
	embed StringUtils as StringUtils
	embed File as File
	embed Inspector as Inspector
	embed Runtime as Runtime

	inputPort WorkspaceInput {
		location: "local"
		interfaces: WorkspaceInterface
	}

	outputPort GlobalVar{
		location: "local://GlobalVar"
		interfaces: GlobalVariables
	}

	init {
		println@Console( "workspace running" )()
	}

	main {
		[ didChangeWatchedFiles( notification ) ] {
			println@Console( "Received didChangedWatchedFiles" )()
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
			println@Console("workspacefolders in workspace file: "+global.workspace.folders[0].uri)()
		}

		[ didChangeConfiguration( notification ) ] {
			valueToPrettyString@StringUtils( notification )(res)
			println@Console("didChangeConfiguration received " + res)()
		}

		[ executeCommand( commandParams )( commandResult ) {
			println@Console("executeCommand received")()
			cmd -> commandParams.commandParams
			args -> commandParams.arguments
			command = cmd
			command.args = args
			exec@Exec( command )( commandResult )
		}]

		/* triggered by Ctrl+t
		 * returns results from searching for symbol in symboltable
		 * @Request: WorkspaceSymbolParams from lsp.ol
		 * @Response: WorkSpaceSymbolResponse from lsp.ol
		 */
		[symbol(request)(response){
			response = void
			install ( FileNotFound => nullProcess )

			// Get workspace rootUri
			getRootUri@GlobalVar()(uriResponse)
			// remove file:/// from path
			split@StringUtils(uriResponse {regex = "///"})(splitResp)
			docUri = splitResp.result[1]

			// create request for inspectWorkspaceModules
			getenv@Runtime( "JOLIE_HOME" )( jHome )
			getFileSeparator@File()( fs )
			requestWorkspaceModules << {
				rootUri = docUri
				includePaths[0] = jHome + fs + "include"
				includePaths[1] = docUri
				symbol = request.query
			}

			inspectWorkspaceModules@Inspector(requestWorkspaceModules)(workspaceModulesResponse)
			// Create the correct response for all places the symbol was found
			responseIndex = 0
			for(i = 0, i < #workspaceModulesResponse.module, i++){
				for(j = 0, j < #workspaceModulesResponse.module[i].symbol, j++){
					response._[responseIndex] << { // according to lsp docs it has to be a list
						name = workspaceModulesResponse.module[i].symbol[j] 
						kind = 5
						location << {
							uri = workspaceModulesResponse.module[i]
							range << {
								start << {
									line = workspaceModulesResponse.module[i].symbol[j].context.startLine
									character = workspaceModulesResponse.module[i].symbol[j].context.startColumn
								}
								end << {
									line = workspaceModulesResponse.module[i].symbol[j].context.endLine
									character = workspaceModulesResponse.module[i].symbol[j].context.endColumn
								}
							}
						}
					}
					responseIndex += 1
				}
			}
		}]
	}
}
