use Yaml, IO;

var f = open("test.yaml", ioMode.cwr);

record rec1 {
    var x: int;
    var y: real;
}

record rec2 {
    var thing: rec1;
    var val: int;
}

var w = f.writer().withSerializer(new yamlSerializer(mapStyle =  MappingStyle.Block));
w.write(111);
w.write(true);
w.write(new rec1(1, 2.0));
w.write(new rec1(3, 4.0));
w.write(new rec2(new rec1(5, 6.0), 7));

w.close();
var r = f.reader().withDeserializer(new yamlDeserializer());

writeln(r.read(int));
writeln(r.read(bool));
writeln(r.read(rec1));
writeln(r.read(rec1));
writeln(r.read(rec2));

// var fw = f.writer();
// fw.withSerializer(new yamlSerializer()).write(new r(1, 2.0));
// fw.withSerializer(new yamlSerializer()).write(new r(3, 4.0));
