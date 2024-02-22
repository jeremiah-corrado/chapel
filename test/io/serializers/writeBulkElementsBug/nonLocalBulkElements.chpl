use IO;

var f = openTempFile();

on Locales[1] {
    var fw = f.writer(locking=false, serializer = new binarySerializer());
    var a: [1..1000] int;

    fw.write(a);
}
