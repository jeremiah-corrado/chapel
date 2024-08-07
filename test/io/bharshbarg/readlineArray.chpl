use IO;

config const n = 100;
config const line = 60;
config const debug = false;

var f = openMemFile();
var r = f.reader(locking=false);
var w = f.writer(locking=false);

var numChars = 0;
for i in 1..n {
  for j in 1..line do w.write(j%10);
  w.writeln();
  numChars += line + 1;
}

var data : [1..numChars] uint(8);

var total : int = 1;
for i in 1..n {
  var numRead = r.readLine(data[total..]);
  total += numRead;
}

var numWrong = 0;
var idx = 1;
for i in 1..n {
  for j in 1..line {
    if data[idx] != ((j%10):string).toByte() then numWrong += 1;
    idx += 1;
  }
  if data[idx] != 0x0A then numWrong += 1; // newline character
  idx += 1;
}

if numWrong != 0 then writeln(numWrong, " out of ", numChars, " characters were wrong");

if total - 1 != numChars then writeln("FAILURE: read ", total - 1, ", but expected ", numChars);
