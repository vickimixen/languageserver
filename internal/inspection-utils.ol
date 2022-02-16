from console import Console
from string_utils import StringUtils
from runtime import Runtime
from file import File
from ..inspectorJavaService.inspector import Inspector
from ..inspectorJavaService.inspector import CodeCheckExceptionType

from ..lsp import ServerToClient, InspectionUtilsInterface

constants {
	INTEGER_MAX_VALUE = 2147483647
}

service InspectionUtils {
    execution: sequential

    embed Inspector as Inspector
	embed Console as Console
	embed StringUtils as StringUtils
	embed Runtime as Runtime
	embed File as File

    inputPort InspectionUtils {
        location: "local://InspectionUtils"
        interfaces: InspectionUtilsInterface
    }

	outputPort LanguageClient {
		location: "local://Client"
		interfaces: ServerToClient
	}

    init {
        println@Console("InspectionUtils Service started at "+ global.inputPorts.Utils.location + ".")()//" connected to " + LanguageClient.location )()
    }
    main{
		[inspectDocument(documentData)(inspectionRes) {
			println@Console("Inside inspectDocument")()
			scope(inspection){
				install( default =>
					stderr << inspection.(inspection.default)
					isCodeCheckException = stderr instanceof CodeCheckExceptionType
					if(isCodeCheckException){
						for(codeMessage in stderr.exceptions){
							if(is_defined(codeMessage.context)){
								startLine << codeMessage.context.startLine
								endLine << codeMessage.context.endLine
								startColumn << codeMessage.context.startColumn
								endColumn << codeMessage.context.endColumn
							} else {
								startLine = 1
								endLine = 1
								startColumn = 0
								endColumn = 0
							}
							if(is_defined(codeMessage.description)){
								message = codeMessage.description
							} else {
								message = ""
							}
							if(is_defined(codeMessage.help)){
								message += codeMessage.help
							}
							//severity
							//TODO alwayes return error, never happend to get a warning
							//but this a problem of the jolie parser
							s = 1

							diagnosticParams << {
								uri << documentData.uri
								diagnostics << {
									severity = s
									range << {
										start << {
										line = startLine -1
										character = startColumn
										}
										end << {
										line = endLine -1
										character = endColumn
										}
									}
									source = "jolie"
									message = message
								}
							}
							publishDiagnostics@LanguageClient( diagnosticParams )
						}
					} else {
						stderr.regex =  "\\s*(.+):\\s*(\\d+):\\s*(error|warning)\\s*:\\s*(.+)"
						find@StringUtils( stderr )( matchRes )
						// //getting the uri of the document to be checked
						//have to do this because the inspector, when returning an error,
						//returns an uri that looks the following:
						// /home/eferos93/.atom/packages/Jolie-ide-atom/server/file:/home/eferos93/.atom/packages/Jolie-ide-atom/server/utils.ol
						//same was with jolie --check
						if ( !(matchRes.group[1] instanceof string) ) {
							matchRes.group[1] = ""
						}
						indexOf@StringUtils( matchRes.group[1] {
							word = "file:"
						} )( indexOfRes )
						if ( indexOfRes > -1 ) {
							subStrReq = matchRes.group[1]
							subStrReq.begin = indexOfRes + 5

							substring@StringUtils( subStrReq )( documentUri ) //line
						} else {
							replaceRequest = matchRes.group[1]
							replaceRequest.regex = "\\\\";
							replaceRequest.replacement = "/"
							replaceAll@StringUtils( replaceRequest )( documentUri )
							// documentUri = "///" + fileName
						}
						
						//line
						l = int( matchRes.group[2] )
						//severity
						sev -> matchRes.group[3]
						//TODO alwayes return error, never happend to get a warning
						//but this a problem of the jolie parser
						if ( sev == "error" ) {
							s = 1
						} else {
							s = 1
						}

						diagnosticParams << {
							uri = "file:" + documentUri
							diagnostics << {
							range << {
								start << {
								line = l-1
								character = 1
								}
								end << {
								line = l-1
								character = INTEGER_MAX_VALUE
								}
							}
							severity = s
							source = "jolie"
							message = matchRes.group[4]
							}
						}
						publishDiagnostics@LanguageClient( diagnosticParams )
					}
				);
				// TODO : fix these:
				// - remove the directories of this LSP
				// - add the directory of the open file.
				getenv@Runtime( "JOLIE_HOME" )( jHome )
				getFileSeparator@File()( fs )
				getParentPath@File( documentData.uri )( documentPath )
				regexRequest << documentData.uri
				regexRequest.regex =  "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?"
				find@StringUtils( regexRequest )( regexResponse )
				inspectionReq << {
					filename = regexResponse.group[5]
					source = documentData.text
					includePaths[0] = jHome + fs + "include"
					includePaths[1] = documentPath
				}
				replacementRequest = regexResponse.group[5]
				replacementRequest.regex = "%20"
				replacementRequest.replacement = " "
				replaceAll@StringUtils(replacementRequest)(inspectionReq.filename)
				
				replacementRequest = inspectionReq.includePaths[1]
				replaceAll@StringUtils(replacementRequest)(inspectionReq.includePaths[1])
				
				inspectFile@Inspector( inspectionReq )( inspectionRes )
				diagnosticParams << {
					uri << documentData.uri
					diagnostics = void
				}
				publishDiagnostics@LanguageClient( diagnosticParams )
			}
        }]
    }
}