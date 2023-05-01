use IO;

var s = "abc";

var sf = new stringFile(s),
    sw = sf.writer();

try {
    sw.writeln(21);
    sw.writeln("hello world!");
} catch e {
    writeln(e);
}

sw.close();
var s2 = sf.close();

writeln("s2: ", s2);
