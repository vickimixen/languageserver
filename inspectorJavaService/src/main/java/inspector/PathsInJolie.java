package inspector;

import java.util.ArrayList;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;

import jolie.runtime.JavaService;
import jolie.runtime.Value;
import jolie.runtime.ValueVector;
import jolie.runtime.embedding.RequestResponse;

public class PathsInJolie extends JavaService{

    /**
     * Takes the module path e.g. ".someDirectory.someModule" and returns it as correct path e.g. "someDirectory/someModule/"
     * @param packagePath
     * @return path as a string
     */
    private String packagePathToPath(String packagePath){
        String[] splitByDot = packagePath.split("\\.");
        // count how many dots are in front of the first word in the packagePath
        int prePath = 0;
        for (String spl : splitByDot) {
            if(spl.isEmpty()){
                prePath += 1;
            } else {
                break;
            }
        }
        if(prePath == 0){
            // if no dots in front, simply replace all aother dots bit file separators
            packagePath = System.getProperty("file.separator") + packagePath.replace(".", System.getProperty("file.separator"));
        }else if(prePath == 1){
            // if one dot is in front, we are in the same directory as the source, and can also simply replace all dots by file separators
            packagePath = packagePath.replace(".", System.getProperty("file.separator"));
        }else{ // if there are more than one dot in front
            packagePath = packagePath.substring(prePath); // remove front dots from packagePath
            packagePath = packagePath.replace(".", System.getProperty("file.separator")); //replace the rest with file separators
            // create first part of path, as each front dot represents a super directory
            String extraSeparators = System.getProperty("file.separator");
            for (int i = 1; i < prePath; i++) {
                extraSeparators += ".."+System.getProperty("file.separator");                
            }
            // add the two parts of the path
            packagePath = extraSeparators+packagePath;
        }
        return packagePath;

    }

    /**
     * 
     * @param sourcePath
     * @param joliePackagePath
     * @return list of files and directories which could the completion of what the user wanted to write as the packagePath
     */
    private ArrayList<File> possibleFilesAtPath(String sourcePath, String joliePackagePath){
        // if the sourcePath given includes the filename, get the path of the directory
        String parentPath;
        if(sourcePath.endsWith(".ol")){
            File source = new File(sourcePath);
            parentPath = source.getParent();
        } else {
            parentPath = sourcePath;
        }
        ArrayList<File> possibleFiles = new ArrayList<>();

        File correctPath = new File(parentPath + joliePackagePath);
        if(correctPath.isDirectory()){ // if we are in a directory find all ".ol" files and all subdirectories
            for (File file : correctPath.listFiles()) {
                if(file.isFile()){
                    if(file.getPath().endsWith(".ol")){
                        possibleFiles.add(file);
                    }
                }else if(file.isDirectory()){
                    possibleFiles.add(file);
                }   
            }
        } else { // if the path is not a directory, go to parentdirectory,
            // look through all files to find filenames that matches the part of the correctPath that, which made it not a directory 
            File parentDirectory = correctPath.getParentFile();
            if(parentDirectory.isDirectory()){
                for (File file : parentDirectory.listFiles()) {
                    String[] tempsplit = correctPath.getPath().split("\\"+System.getProperty("file.separator"));
                    String lastPart = tempsplit[tempsplit.length-1];
                    if(file.getPath().contains(System.getProperty("file.separator")+lastPart)){
                        possibleFiles.add(file);
                    }
                    
                }
            }
        }
        return possibleFiles;
    }

    /**
     * Called from languageserver/internal/completionHelper.ol
     * @param request contains sourcepath (string), joliePackagePath (string)
     * @return value with a list(valueVector) of names to be used for completion of module
     */
    @RequestResponse
    public Value inspectPackagePath(Value request) {
        String sourcePath = request.getFirstChild( "sourcePath" ).strValue().substring(5); // removes "file:/"
        String joliePackagePath = request.getFirstChild("joliePackagePath").strValue();
        Value result = Value.create();
        ValueVector possibliePackagesVector = result.getChildren("possiblePackages");
        ArrayList<File> possibleFiles;
        if(joliePackagePath.startsWith(".")){ // packagepath to module is local to the sourcepath
            joliePackagePath = packagePathToPath(joliePackagePath); // turns packagePath into a correct path
            // finds all file and directory names at the packagePath which can be the completion for the packagePath we are looking for
            possibleFiles = possibleFilesAtPath(sourcePath, joliePackagePath);
        } else{ // packagepath to module is not local to sourcepath and should be located in the compiler (e.g console.ol)
            joliePackagePath = packagePathToPath(joliePackagePath);
            possibleFiles = possibleFilesAtPath(System.getenv("JOLIE_HOME")+System.getProperty("file.separator")+"packages", joliePackagePath);
        }
        for (File file : possibleFiles) {
            // split path according to file separator and save the last part, which is the file or directory name
            String[] pathSplit = file.getPath().split("\\"+System.getProperty("file.separator"));
            String name = pathSplit[pathSplit.length-1];
            if(name.contains(".")){ // if the name contains a "." it is an ".ol" file
                // split by "." and save first part as the name
                name = name.split("\\.")[0];
            }
            // all file and directory names are saved and returned
            possibliePackagesVector.add(Value.create(name));
            
        }
        return result;
    }

    /**
     * Called from langaugeserver/internal/completionHelper.ol
     * Goes through all symbols in the imported module and checks wether they match what the user has started to write
     * as the symbol they want to import. The symbol can either be a service
     * @param request
     * @return value containing a list(valueVector) of service, interface and type names
     */
    public Value inspectSymbol(Value request) {
        String sourcePath = request.getFirstChild( "sourcePath" ).strValue().substring(5);
        String packagePath = request.getFirstChild("packagePath").strValue();
        String symbol = request.getFirstChild("symbol").strValue();
        Value result = Value.create();
        ValueVector possibleSymbolsVector = result.getChildren("possibleSymbols");

        // Create the correct path to the module the symbol should be imported from
        File filePath;
        if(packagePath.startsWith(".")){ // local module
            packagePath = packagePathToPath(packagePath);
            if(sourcePath.endsWith(".ol")){
                File source = new File(sourcePath);
                sourcePath = source.getParent();
            }
            filePath = new File(sourcePath + packagePath+".ol");
        } else{ // module from compiler
            packagePath = packagePathToPath(packagePath);
            filePath = new File(System.getenv("JOLIE_HOME")+System.getProperty("file.separator")+"packages"+packagePath+".ol");
        }

        // read through the module source code and find services,interfaces and types matching the word we are trying to complete
        // TODO: should probably use the symboltable from the compiler instead
        if(filePath.isFile()){
            try{
                FileReader fr = new FileReader(filePath);
                BufferedReader br = new BufferedReader(fr);
                String line;
                while((line=br.readLine())!=null){
                    if(line.matches("^(service|interface)\\s.+\\s\\{.*$") || line.matches("^type\\s.+(\\s\\{|\\:\\s.\\{).*$")){
                        String[] tempSplit = line.split(" ");
                        String name = tempSplit[1];
                        if(name.startsWith(symbol)){
                            possibleSymbolsVector.add(Value.create(name));
                        }
                    }
                }
                br.close();

            }catch(IOException e){ // if an error occurs we simply do nothing, and the result will be empty
            }
        }
        return result;
    }
}
