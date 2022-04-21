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
from string_utils import StringUtils
from runtime import Runtime
from file import File
from exec import Exec
from ..inspectorJavaService.inspector import Inspector
from ..lsp import TextDocumentInterface, UtilsInterface, CompletionHelperInterface, InspectionUtilsInterface, GlobalVariables

constants {
	INTEGER_MAX_VALUE = 2147483647,
	NOTIFICATION = "notification",
	NATIVE_TYPE_VOID = "void",
	REQUEST_TYPE = "Request Type",
	RESPONSE_TYPE = "Response Type",
	HOVER_MARKUP_KIND_MARKWDOWN = "markdown",
	HOVER_MARKUP_KIND_PLAIN = "plaintext"
}

constants {
	SymbolKind_File = 1,
	SymbolKind_Module = 2,
	SymbolKind_Namespace = 3,
	SymbolKind_Package = 4,
	SymbolKind_Class = 5,
	SymbolKind_Method = 6,
	SymbolKind_Property = 7,
	SymbolKind_Field = 8,
	SymbolKind_Constructor = 9,
	SymbolKind_Enum = 10,
	SymbolKind_Interface = 11,
	SymbolKind_Function = 12,
	SymbolKind_Variable = 13,
	SymbolKind_Constant = 14,
	SymbolKind_String = 15,
	SymbolKind_Number = 16,
	SymbolKind_Boolean = 17,
	SymbolKind_Array = 18,
}

/*
 * Service that handles all the textDocument/ messages sent from the client
 */
service TextDocument {
	execution: concurrent

	embed Exec as Exec
	embed Console as Console
	embed StringUtils as StringUtils
	embed Runtime as Runtime
	embed Inspector as Inspector
	embed File as File

	inputPort TextDocumentInput {
		location: "local"
		interfaces: TextDocumentInterface
	}

	outputPort Utils {
		location: "local://Utils"
		interfaces: UtilsInterface
	}

	outputPort CompletionHelper {
		location: "local://CompletionHelper"
		interfaces: CompletionHelperInterface
	}

	outputPort InspectionUtils {
		location: "local://InspectionUtils"
		interfaces: InspectionUtilsInterface
	}

	outputPort GlobalVar{
		location: "local://GlobalVar"
		interfaces: GlobalVariables
	}

	init {
		println@Console( "txtDoc running" )()
	}

	main {
		[ didOpen( notification ) ]  {
			println@Console( "didOpen received for " + notification.textDocument.uri )()
			insertNewDocument@Utils( notification )
			doc.path = notification.textDocument.uri
			//syntaxCheck@SyntaxChecker( doc )
		}

		/*
		* Message sent from the L.C. when saving a document
		* Type: DidSaveTextDocumentParams, see types.iol
		*/
		[ didChange( notification ) ] {
			println@Console( "didChange received " )()

			docModifications << {
				text = notification.contentChanges[0].text
				version = notification.textDocument.version
				uri = notification.textDocument.uri
			}

			updateDocument@Utils( docModifications )
		}

		[ willSave( notification ) ] {
			//never received a willSave message though
			println@Console( "willSave received" )()
		}

		/*
		* Messsage sent from the L.C. when saving a document
		* Type: DidSaveTextDocumentParams, see types.iol
		*/
		[ didSave( notification ) ] {
			println@Console( "didSave message received" )()
			//didSave message contains only the version and the uri of the doc
			//not the text! Therefore I get the document saved in the memory to get the text
			//the text found will match the actual text just saved in the file as
			//before this we surely received a didChange with the updated text
			getDocument@Utils( notification.textDocument.uri )( textDocument )
			docModifications << {
				text = textDocument.source
				version = notification.textDocument.version
				uri = notification.textDocument.uri
			}
			updateDocument@Utils( docModifications )
			//doc.path = notification.textDocument.uri
			//syntaxCheck@SyntaxChecker( doc )
		}

		/*
		* Message sent from the L.C. when closing a doc
		* Type: DidCloseTextDocumentParams, see types.iol
		*/
		[ didClose( notification ) ] {
			println@Console( "didClose received" )()
			deleteDocument@Utils( notification )

		}

		/*
		* RR sent sent from the client when requesting a completion
		* works for anything callable and imports
		* @Request: CompletionParams, see lsp.ol
		* @Response: CompletionResult, see lsp.ol
		*/
		[ completion( completionParams )( completionRes ) {
			println@Console( "Completion Req Received" )()
			completionRes.isIncomplete = false
			txtDocUri -> completionParams.textDocument.uri
			position -> completionParams.position

			if ( is_defined( completionParams.context ) ) {
				triggerChar -> completionParams.context.triggerCharacter
			}

			getDocument@Utils( txtDocUri )( document )

			// Bools for checking whether completion was found
			portFound = false
			keywordFound = false
			importModuleFound = false
			importSymbolFound = false

			program -> document.jolieProgram

			// Check if the line from the completion request is part of an import statement or not
			codeLine = document.lines[position.line]
			trim@StringUtils( codeLine )( codeLineTrimmed )
			// try to match the line with "from something import random"
			match@StringUtils(codeLineTrimmed {regex="^from\\s([\\.\\w]+)\\simport\\s(\\w+)$"})(matchResponseImportSymbol)
			// try to match the line with "from something"
			match@StringUtils(codeLineTrimmed {regex = "^from\\s([\\.\\w]+)$"})(matchResponseImportModule)
			if(matchResponseImportSymbol == 1){ // line matches "from something import random"
				// call helperservice
				completionImportSymbol@CompletionHelper(
					{txtDocUri = txtDocUri, regexMatch << matchResponseImportSymbol.group})(helperResponse)
				if(is_defined(helperResponse.result)){
					importSymbolFound = true
					// create the completion response
					for ( name in helperResponse.result){
						completionItem << {
							label = name
							insertTextFormat = 2
							insertText = name
						}
						completionRes.items[#completionRes.items] << completionItem
					}
				}
			} else if(matchResponseImportModule == 1){ // line matchen "from something"
				// call helper service
				completionImportModule@CompletionHelper(
					{ regexMatch << matchResponseImportModule.group, txtDocUri = txtDocUri } )(helperResponse)
				if(is_defined(helperResponse.result)){
					importModuleFound = true
					// create completion response
					for ( name in helperResponse.result){
						completionItem << {
							label = name
							insertTextFormat = 2
							insertText = name
						}
						completionRes.items[#completionRes.items] << completionItem
					}
				}
			}else { // if none of the regex match, it is either an operation or a keyword
				// call helper service to see if the completion is for an operation
				completionOperation@CompletionHelper({jolieProgram << program, codeLine = codeLineTrimmed})(helperResponse)
				if(is_defined(helperResponse.result)){
					portFound = true
					for(item in helperResponse.result){
						completionRes.items[#completionRes.items] << item
					}
				}
				// call helper service to see if the completion is for a keyword
				completionKeywords@CompletionHelper({codeLine = codeLineTrimmed})(keywordResponse)
				if(is_defined(keywordResponse.result)){
					keywordFound = true
					for(item in keywordResponse.result){
						completionRes.items[#completionRes.items] << item
					}
				}
			}
			// if no completions were found, return a void response, such that the extension simply does not show any suggestions
			if ( !foundPort && !keywordFound && !importModuleFound && !importSymbolFound) {
				completionRes.items = void
			}
			println@Console( "Sending completion Item to the client" )()
		}]

		/*
		* RR sent sent from the client when requesting a hover
		* @Request: TextDocumentPositionParams, see lsp.ol
		* @Response: HoverResult, see lsp.ol
		*/
		[ hover( hoverReq )( hoverResp ) {
			found = false
			println@Console( "hover req received.." )()
			textDocUri -> hoverReq.textDocument.uri
			getDocument@Utils( textDocUri )( document )

			line = document.lines[hoverReq.position.line]
			program -> document.jolieProgram
			trim@StringUtils( line )( trimmedLine )
			//regex that identifies a message sending to a port
			trimmedLine.regex = "([A-z]+)@([A-z]+)\\(.*"
			//.group[1] is operaion name, .group[2] port name
			find@StringUtils( trimmedLine )( findRes )
			if ( findRes == 0 ) {
				trimmedLine.regex = "\\[? ?( ?[A-z]+ ?)\\( ?[A-z]* ?\\)\\(? ?[A-z]* ?\\)? ?\\]? ?\\{?"
				//in this case, we have only group[1] as op name
				find@StringUtils( trimmedLine )( findRes )
			}

			//if we found somenthing, we have to send a hover item, otherwise void
			if ( findRes == 1 ) {
				// portName might NOT be defined
				portName -> findRes.group[2]
				operationName -> findRes.group[1]
				undef( trimmedLine.regex )
				hoverInfo = operationName

				if ( is_defined( portName ) ) {
					hoverInfo += "@" + portName
					ports -> program.outputPorts
				} else {
					ports -> program.inputPorts
				}

				for ( port in ports ) {
					if ( is_defined( portName ) ) {
						ifGuard = port.name == portName && is_defined( port.interfaces )
					} else {
						//we do not know the port name, so we search for each port we have
						//in the program
						ifGuard = is_defined( port.interfaces )
					}

					if ( ifGuard ) {
						for ( iFace in port.interfaces ) {
							for ( op in iFace.operations ) {
								if ( op.name == operationName ) {
									found = true
									if ( !is_defined( portName ) ) {
										hoverInfo += port.name
									}

									reqType = op.requestType
									// reqTypeCode = op.requestType.code
									// reqTypeCode = resTypeCode = "" // TODO : pretty type description

									if ( is_defined( op.responseType ) ) {
										resType = op.responseType
										// resTypeCode = op.responseType.code
									} else {
										resType = ""
										// resTypeCode = ""
									}
								}
							}
						}
					}
				}

				hoverInfo += "( " + reqType + " )"
				//build the info
				if ( resType != "" ) {
					//the operation is a RR
					hoverInfo += "( " + resType + " )"
				}

				// hoverInfo += "\n```\n*" + REQUEST_TYPE + "*: \n" + reqTypeCode
				// if ( resTypeCode != "" ) {
				//   hoverInfo += "\n\n*" + RESPONSE_TYPE + "*: \n" + resTypeCode
				// }

				//setting the content of the response
				if ( found ) {
					hoverResp.contents << {
						language = "jolie"
						value = hoverInfo
					}

					//computing and setting the range
					length@StringUtils( line )( endCharPos )
					line.word = trimmedLine
					indexOf@StringUtils( line )( startChar )

					hoverResp.range << {
						start << {
							line = hoverReq.position.line
							character = startChar
						}
						end << {
							line = hoverReq.position.line
							character = endCharPos
						}
					}
				}
			}
		}]

		[ signatureHelp( txtDocPositionParams )( signatureHelp ) {
			// TODO, not finished, buggy, needs refactor
			println@Console( "signatureHelp Message Received" )(  )
			signatureHelp = void
			textDocUri -> txtDocPositionParams.textDocument.uri
			position -> txtDocPositionParams.position
			getDocument@Utils( textDocUri )( document )
			line = document.lines[position.line]
			program -> document.jolieProgram
			trim@StringUtils( line )( trimmedLine )
			trimmedLine.regex = "([A-z]+)@([A-z]+)"
			find@StringUtils( trimmedLine )( matchRes )

			if ( matchRes == 0 ) {
				trimmedLine.regex = "\\[?([A-z]+)"
				find@StringUtils( trimmedLine )( matchRes )
				if ( matchRes == 1 ) {
					opName -> matchRes.group[1]
					portName -> matchRes.group[2]

					if ( is_defined( portName ) ) {
						label = opName
					} else {
						label = opName + "@" + portName
					}
				}
			} else {
				opName -> matchRes.group[1]
				portName -> matchRes.group[2]
				label = opName + "@" + portName
			}
			// if we had a match
			foundSomething = false
			if ( matchRes == 1 ) {
				for ( port in program ) {

					if ( is_defined( portName ) ) {
						ifGuard = ( port.name == portName ) && is_defined( port.interface )
						foundSomething = true
					} else {
						ifGuard = is_defined( port.interface )
					}

					if ( ifGuard ) {
						for ( iFace in port.interface ) {
							if ( op.name == opName ) {
								foundSomething = true
								opRequestType = op.requestType.name

								if ( is_defined( op.responseType ) ) {
									opResponseType = op.responseType.name
								}
							}
						}
					}
				}

				parametersLabel = opRequestType + " " + opResponseType
				if ( foundSomething ) {
					signatureHelp << {
						signatures << {
							label = label
							parameters << {
								label = parametersLabel
							}
						}
					}
				}
			}
		}]

		[ documentSymbol( request )( response ) {
			println@Console("documentSymbol received")()
		} // {
			// TODO: WIP
			// getDocument@Utils( request.textDocument.uri )( document )
			// i = 0
			// symbolInfo -> response._[i]
			// for( port in document.jolieProgram.outputPorts ) {
			//   symbolInfo.name = port.name
			//   symbol.detail = "outputPort"
			//   symbol.kind = SymbolKind_Class
			//   symbol.range 
			//   i++
			// }
		// }
		]

		/* Go to definition
		* (might not always go to the correct place, if the line and column number in the symbol table is not correct)
		* @Request: TextDocumentPositionParams in lsp.ol
		* @Response: DefinitionResponse in lsp.ol
		*/
		[ definition(request)(response){
			// receives the uri and the position
			println@Console("Definition request received")()
			response = void
			scope(inspection){
				// Do nothing in case of error, as a definition is simply not found
				// and the extension provides this message by looking at the void response
				install( default => 
					valueToPrettyString@StringUtils(inspection.default)(prettyDefault)
					println@Console("default error happened while looking for definition:\n"+prettyDefault)()
				)
				// Get the text of the file, which we get the definition request from
				split@StringUtils(request.textDocument.uri {regex = "///"})(splitResponse)
				readFile@File({filename = splitResponse.result[1]})(readFileResponse)
				documentData << {uri = request.textDocument.uri, text = readFileResponse}

				createMinimalInspectionRequest@InspectionUtils(documentData)(inspectionReq)
				//add the position to the minimal inspection request, as the inspectModule requires it
				inspectionReq.position << request.position
				inspectModule@Inspector(inspectionReq)(inspectResponse)

				// if a definition was found, build a response
				isResponseDefined = is_defined(inspectResponse.module)
				if(isResponseDefined){
					response << {
						uri = inspectResponse.module
						range << {
							start <<  {
								line = inspectResponse.module.context.startLine
								character = inspectResponse.module.context.startColumn
							}
							end << {
								line = inspectResponse.module.context.endLine
								character = inspectResponse.module.context.endColumn
							}
						}
					}
				}
			}
		}]

		/* Can be triggered by F2
		* if rename cannot be done correctly, the function does not do any renaming
		* @Request: RenameRequest from lsp.ol
		* @Response: RenameResponse from lsp.ol
		*/
		[rename(request)(response){
			println@Console("Inside rename")()
			response = void

			// get root path of the workspace
			getRootUri@GlobalVar()(request.rootUri)

			// Fix rooturi and documenturi to not contain file:///
			split@StringUtils(request.rootUri {regex = "///"})(splitResult)
			request.rootUri = splitResult.result[1]
			split@StringUtils(request.textDocument.uri {regex = "///"})(splitResponse)
			request.textDocument.uri = splitResponse.result[1]

			//Create includePaths
			getenv@Runtime( "JOLIE_HOME" )( jHome )
			getFileSeparator@File()( fs )
			request.includePaths[0] = jHome + fs + "include"
			request.includePaths[1] = request.textDocument.uri

			scope(renameInspection){
				// Catch errors from inspectionToRename in case the rename is not possible
				install( default =>
					stderr << renameInspection.default
					println@Console("error: "+renameInspection.default)()
				)
				// Get all places the symbol needs to be renamed, this is still not an optimal function,
				// as all places the symbol occurs cannot be found, and the line and columns of all symbols might not be correct
				inspectionToRename@Inspector(request)(inspectionResponse)

				// right now each symbol only exists one time in the symboltable and all places to rename cannot be found
				for(i = 0, i < #inspectionResponse.module, i++){
					for(j = 0, j < #inspectionResponse.module[i].symbol, j++){
						println@Console("inspectionResponse.module: "+inspectionResponse.module[i])()
						response.changes.(inspectionResponse.module[i])._[j] << {
							range << {
								start << {
									line = inspectionResponse.module[i].symbol[j].context.startLine
									character = inspectionResponse.module[i].symbol[j].context.startColumn
								}
								end << {
									line = inspectionResponse.module[i].symbol[j].context.endLine
									character = inspectionResponse.module[i].symbol[j].context.endColumn
								}
							}
							newText = request.newName
						}
					}
				}
			}
		}]
	}
}
