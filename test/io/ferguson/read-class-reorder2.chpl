use IO;

class Base {
}

class Parent : Base {
  var a: int;
  var b: int;
}

class Child : Parent {
  var x: int;
  var y: int;
}

var ownA = new owned Child(a = 1, b = 2, x = 3, y = 4);
var a: borrowed Child = ownA.borrow();

writeln("a is ", a);

var f = open("test.txt", ioMode.cwr);
var writer = f.writer(locking=false);
var s = "{b=5,a=4,y=7,x=6}";
writer.writeln(s);
writeln("writing ", s);
writer.close();

var reader = f.reader(locking=false);
reader.read(a);
writeln("a after reading is ", a);
