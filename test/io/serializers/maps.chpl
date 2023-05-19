
use IO;
use Map;
use FormatHelper;

record R {
  var x : int;
  var y : real;
}

proc R.init(x: int, y: real) {
  this.x = x;
  this.y = y;
}

proc R.init(reader: fileReader, ref deserializer) throws {
  var gotError = false;
  deserializer.startRecord(reader, "R", 2);
  try {
    this.x = deserializer.deserializeField(reader, "x", int);
    this.y = deserializer.deserializeField(reader, "y", real);
  } catch {
    gotError = true;
  }
  deserializer.endRecord(reader);
  this.complete();
  if gotError then throw new Error();
}

proc test(m: map) {
  printDebugFmt(m);

  var f = openTempFile();
  {
    f.writer().withSerializer(getFormatVal(true)).writeln(m);
    writeln("-------------------");
    writeln(f.reader().readAll());
    writeln("-------------------");
  }
  {
    var x = f.reader().withDeserializer(getFormatVal(false)).read(m.type);
    if m != x then
      writeln("FAILURE: ", m.type:string);
    else
      writeln("SUCCESS: ", m.type:string);
  }
}

proc main() {
  {
    var m : map(string, string);
    m.add("hello", "goodbye");
    m.add("day", "night");
    m.add("east", "west");
    m.add("north", "south");

    test(m);
  }

  // Check what serializer does with non-string key
  {
    var m : map(int, string);
    m.add(206, "Seattle");
    m.add(212, "NYC");
    m.add(713, "Houston");
    
    test(m);
  }

  {
    var m : map(string, R);
    m.add("Apple", new R(5, 42.0));
    m.add("Banana", new R(1, -10.0));
    m.add("Orange", new R(13, 106.7));

    test(m);

    var r : map(R, string);
    for k in m.keys() do
      r.add(m[k], k);

    test(r);
  }
}
