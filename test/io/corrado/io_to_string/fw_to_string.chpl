use IO;

var s = "";
// var f = new file(s);
var fw = new fileWriter(s);

fw.write("Hello World");

s.buffLen = 11;
s.cachedNumCodepoints = 11;

fw.close();
writeln(s);