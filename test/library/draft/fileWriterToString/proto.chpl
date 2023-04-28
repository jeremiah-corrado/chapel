use IO;

var s = "";

var sf = new stringFile(s),
    stringWriter = sf.writer();

try {
    stringWriter.write("hello world!");
} catch e {
    writeln(e);
}

stringWriter.close();
var s2 = sf.close();

writeln(s2);
