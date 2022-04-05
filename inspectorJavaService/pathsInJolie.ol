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

interface PathsInJolieInterface {
	RequestResponse:
	inspectPackagePath(InspectPackagePathRequest)(InspectPackagePathResult),
    inspectSymbol(InspectSymbolRequest)(InspectSymbolResult)
}
service PathsInJolie {
    inputPort PathsInJolie {
        location:"local"
        interfaces: PathsInJolieInterface
    }

    foreign java {
        class: "inspector.PathsInJolie"
    }
}