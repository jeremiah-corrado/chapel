proc test(val) {
  var x = val: string;
  writeln(x.cachedNumCodepoints);
}

test(1);
test(1.1);
test(1..1);
test((1,1));
