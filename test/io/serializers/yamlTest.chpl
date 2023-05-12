use Yaml, IO;

var f = open("test.yaml", ioMode.cwr);

record r {
    var x: int;
    var y: real;
}

f.writer().withSerializer(new yamlSerializer()).write(new r(1, 2.0));
