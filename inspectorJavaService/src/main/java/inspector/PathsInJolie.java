package joliex.inspector;

import java.util.List;
import java.util.ArrayList;
import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.io.IOException;
import java.nio.file.Path;

import jolie.runtime.JavaService;
import jolie.runtime.Value;
import jolie.runtime.ValueVector;

public class PathsInJolie extends JavaService{

    private String packagePathToPath(String packagePath){
        String[] splitByDot = packagePath.split("\\.");
        int prePath = 0;
        for (String spl : splitByDot) {
            if(spl.isEmpty()){
                prePath += 1;
            } else {
                break;
            }
        }
        if(prePath == 0){
            packagePath = System.getProperty("file.separator") + packagePath.replace(".", System.getProperty("file.separator"));
        }else if(prePath == 1){
            packagePath = packagePath.replace(".", System.getProperty("file.separator"));
        }else{
            packagePath = packagePath.substring(prePath);
            packagePath = packagePath.replace(".", System.getProperty("file.separator"));
            String extraSeparators = System.getProperty("file.separator");
            for (int i = 1; i < prePath; i++) {
                extraSeparators += ".."+System.getProperty("file.separator");                
            }
            packagePath = extraSeparators+packagePath;
        }
        return packagePath;

    }

    private ArrayList<File> possibleFilesAtPath(String sourcePath, String joliePackagePath){
        String parentPath;
        if(sourcePath.endsWith(".ol")){
            File source = new File(sourcePath);
            parentPath = source.getParent();
        } else {
            parentPath = sourcePath;
        }
        ArrayList<File> possibleFiles = new ArrayList<>();

        File correctPath = new File(parentPath + joliePackagePath);
        if(correctPath.isDirectory()){
            for (File file : correctPath.listFiles()) {
                if(file.isFile()){
                    if(file.getPath().endsWith(".ol")){
                        possibleFiles.add(file);
                    }
                }else if(file.isDirectory()){
                    possibleFiles.add(file);
                }   
            }
        } else {
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

    public Value inspectPackagePath(Value request) {
        String sourcePath = request.getFirstChild( "sourcePath" ).strValue().substring(5);
        String joliePackagePath = request.getFirstChild("joliePackagePath").strValue();
        Value result = Value.create();
        ValueVector possibliePackagesVector = result.getChildren("possiblePackages");
        ArrayList<File> possibleFiles;
        if(joliePackagePath.startsWith(".")){
            joliePackagePath = packagePathToPath(joliePackagePath);
            possibleFiles = possibleFilesAtPath(sourcePath, joliePackagePath);
        } else{
            joliePackagePath = packagePathToPath(joliePackagePath);
            possibleFiles = possibleFilesAtPath(System.getenv("JOLIE_HOME")+System.getProperty("file.separator")+"packages", joliePackagePath);
        }
        for (File file : possibleFiles) {
            String[] pathSplit = file.getPath().split("\\"+System.getProperty("file.separator"));
            String name = pathSplit[pathSplit.length-1];
            if(name.contains(".")){
                name = name.split("\\.")[0];
            }
            possibliePackagesVector.add(Value.create(name));
            
        }
        return result;
    }

    public Value inspectSymbol(Value request) {
        String sourcePath = request.getFirstChild( "sourcePath" ).strValue().substring(5);
        String packagePath = request.getFirstChild("packagePath").strValue();
        String symbol = request.getFirstChild("symbol").strValue();
        Value result = Value.create();
        ValueVector possibleSymbolsVector = result.getChildren("possibleSymbols");

        File filePath;
        if(packagePath.startsWith(".")){
            packagePath = packagePathToPath(packagePath);
            if(sourcePath.endsWith(".ol")){
                File source = new File(sourcePath);
                sourcePath = source.getParent();
            }
            filePath = new File(sourcePath + packagePath+".ol");
        } else{
            packagePath = packagePathToPath(packagePath);
            filePath = new File(System.getenv("JOLIE_HOME")+System.getProperty("file.separator")+"packages"+packagePath+".ol");
        }
        if(filePath.isFile()){
            try{
                FileReader fr = new FileReader(filePath);
                BufferedReader br = new BufferedReader(fr);
                String line;
                while((line=br.readLine())!=null){
                    if(line.matches("^(service|interface)\\s.+\\s\\{.*$")){
                        String[] tempSplit = line.split(" ");
                        String serviceName = tempSplit[1];
                        if(serviceName.startsWith(symbol)){
                            possibleSymbolsVector.add(Value.create(serviceName));
                        }
                    }
                }

            }catch(IOException e){
            }
        }

        return result;
    }
}
