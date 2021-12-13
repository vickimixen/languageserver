from console import Console
from string_utils import StringUtils
from file import File
from inspector import Inspector
from runtime import Runtime

from ..lsp import InspectionUtilsInterface, ServerToClient

service InspectionUtils {
  execution: sequential

  embed Console as Console
  embed StringUtils as StringUtils
  embed File as File
  embed Inspector as Inspector
  embed Runtime as Runtime

  inputPort InspectionUtils {
    Location: "local://InspectionUtils"
    Interfaces: InspectionUtilsInterface
  }

  outputPort DiagnosticPublishingClient {
		location: "local://Client"
		interfaces: ServerToClient
	}
  

  init {
    println@Console( "InspectionUtils Service started" )()
  }

  main {
    [ inspect( documentData )( inspectionResult ) {
      println@Console( "Inspecting..." )(  )
      scope( inspection ) {
        install( default =>
          stderr = inspection.(inspection.default)
          stderr.regex =  "\\s*(.+):\\s*(\\d+):\\s*(error|warning)\\s*:\\s*(.+)"
          find@StringUtils( stderr )( matchRes )
          //getting the uri of the document to be checked
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
            substring@StringUtils( matchRes.group[1] {
              begin = indexOfRes + 5
            } )( documentUri ) //filename
          } else {
            replaceAll@StringUtils( matchRes.group[1] {
              regex = "\\\\"
              replacement = "/"
            } )( documentUri )
            // documentUri = "///" + fileName
          }
          println@Console( "documentData.uri: "+documentData.uri )(  )
          println@Console( "documentUri in inspection-utils: "+documentUri )(  )

          //line
          l = int( matchRes.group[2] )
          //severity
          sev -> matchRes.group[3]
          //TODO always return error, never happend to get a warning
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
          /* println@Console("diagnosticParams: "+diagnosticParams)()
          println@Console("diagnosticParams uri: "+diagnosticParams.uri)()
          println@Console("diagnosticParams diagnostics: "+diagnosticParams.diagnostics)()
          println@Console("diagnosticParams diagnostics.range: "+diagnosticParams.diagnostics.range)()
          println@Console("diagnosticParams diagnostics.range: "+diagnosticParams.diagnostics.range.start.line)()
          println@Console("diagnosticParams diagnostics.range: "+diagnosticParams.diagnostics.range.end.line)()
          println@Console("diagnosticParams diagnostics.severity: "+diagnosticParams.diagnostics.severity)()
          println@Console("diagnosticParams diagnostics.source: "+diagnosticParams.diagnostics.source)()
          println@Console("diagnosticParams diagnostics.message: "+diagnosticParams.diagnostics.message)()
           */
          publishDiagnostics@DiagnosticPublishingClient( diagnosticParams )
          inspectionResult.diagnostics << diagnosticParams
        )

        // TODO : fix these:
        // - remove the directories of this LSP
        // - add the directory of the open file.
        getenv@Runtime( "JOLIE_HOME" )( jHome )
        getFileSeparator@File()( fs )
        getParentPath@File( documentData.uri )( documentPath )
        regexRequest = documentData.uri
	      regexRequest.regex =  "^(([^:/?#]+):)?(//([^/?#]*))?([^?#]*)(\\?([^#]*))?(#(.*))?"
        find@StringUtils( regexRequest )( regexResponse )

        //Spaces in file URIs are encoded with %20 in some systems
        replaceAll@StringUtils( regexResponse.group[5] {
          regex = "%20" 
          replacement = " "
        } )( inspectionReq.filename )

        inspectionReq << {
          source = documentData.text
          includePaths[0] = jHome + fs + "include"
        }

        //Spaces in file URIs are encoded with %20 in some systems
        replaceAll@StringUtils( documentPath {
          regex = "%20"
          replacement = " "
        } )( inspectionReq.includePaths[1] )

        inspectPorts@Inspector( inspectionReq )( inspectionResult.result )
      }
    }]

    [ sendEmptyDiagnostics( uri ) ] {
        println@Console( "Sending empty diagnostics" )(  )
        diagnosticParams << {
          uri = uri
          diagnostics = void
        }
        publishDiagnostics@DiagnosticPublishingClient( diagnosticParams )
      }
  }
}