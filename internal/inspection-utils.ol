from console import Console
from string_utils import StringUtils
from runtime import Runtime
from file import File
from inspector import Inspector

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
					stderr = inspection.(inspection.default)
					stderr.regex =  "\\s*(.+):\\s*(\\d+):\\s*(error|warning)\\s*:\\s*(.+)"
					find@StringUtils( stderr )( matchRes )
					if ( !(matchRes.group[1] instanceof string) ) {
						matchRes.group[1] = ""
					}
					indexOf@StringUtils( matchRes.group[1] {
						word = "file:"
					} )( indexOfRes )
					if ( indexOfRes > -1 ) {
						subStrReq = matchRes.group[1]
						subStrReq.begin = indexOfRes + 5
						substring@StringUtils( subStrReq )( documentUri ) //filename
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
						uri << documentData.uri
						diagnostics << {
							severity = 1
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
							source = "jolie"
							message = matchRes.group[4]
						}
					}
					publishDiagnostics@LanguageClient( diagnosticParams )
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
				
				inspectPorts@Inspector( inspectionReq )( inspectionRes )
				diagnosticParams << {
					uri << documentData.uri
				}
				publishDiagnostics@LanguageClient( diagnosticParams )
			}
        }]
    }


}