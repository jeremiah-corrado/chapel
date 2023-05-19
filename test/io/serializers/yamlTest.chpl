use Yaml, IO, List, FileSystem;

record rec0 {
  var x: int;
  var y: bool;
}

record rec1 {
  var x: int;
  var y: real;
}

record rec2 {
  var thing: rec1;
  var val: int;
}

record rec3 {
  var a: list(int);
  var b: rec2;
}

const r0 = new rec0(111, true);
const r1 = new rec1(1, 2.0);
const r2 = new rec2(new rec1(5, 6.0), 7);
const r3 = new rec3(new list(1..5), new rec2(new rec1(8, 9.0), 10));

proc writeYaml(serializerOptions...) {
  var f = open("test.yaml", ioMode.cwr);

  var w = f.writer().withSerializer(new yamlSerializer((...serializerOptions)));
  w.write(r0);
  w.write(r1);
  w.write(r2);
  w.write(r3);
  w.close();

  writeln(openReader("test.yaml").readAll());

  var r = f.reader().withDeserializer(new yamlDeserializer());
  assert(r0 == r.read(rec0));
  assert(r1 == r.read(rec1));
  assert(r2 == r.read(rec2));
  assert(r3 == r.read(rec3));
}

// block
writeYaml(SequenceStyle.Block, MappingStyle.Block);

// flow
writeYaml(SequenceStyle.Flow, MappingStyle.Flow);

remove("test.yaml");
