from ..lsp import DocumentUri, WorkSpaceSymbolResponse 

type InspectPackagePathRequest: any {
	joliePackagePath:string
    sourcePath:string
}

type InspectPackagePathResult: any {
	possiblePackages*:string
}

type InspectSymbolRequest: any {
    packagePath:string
    symbol:string
    sourcePath:string
}

type InspectSymbolResult: any {
	possibleSymbols*:string
}

type findSymbolsInAllFilesRequest {
    symbol: string
    rootUri: DocumentUri
}

type findSymbolsInAllFilesResponse: WorkSpaceSymbolResponse

interface PathsInJolieInterface {
	RequestResponse:
	inspectPackagePath(InspectPackagePathRequest)(InspectPackagePathResult),
    inspectSymbol(InspectSymbolRequest)(InspectSymbolResult),
    findSymbolInAllFiles(findSymbolsInAllFilesRequest)(findSymbolsInAllFilesResponse)
}
service PathsInJolie {
    inputPort PathsInJolie {
        location:"local"
        interfaces: PathsInJolieInterface
    }

    foreign java {
        class: "joliex.inspector.PathsInJolie"
    }
}