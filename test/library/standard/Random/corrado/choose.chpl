use Random;

var rs = new randomStream(int, seed=314159);
const ranges = (1..10, 1..10 by 2, 1..10 by 2 align 2);

for r in ranges {
  // range interface
  const rChoices = rs.choose(r, 4),
        rChoice = rs.choose(r);
  writeln(rChoices, "\n", rChoice);

  // domain interface
  const d = {r},
        dChoices = rs.choose(d, 4),
        dChoice = rs.choose(d);
  writeln(dChoices, "\n", dChoice);

  // array interface
  var a: [d] rec;
  for (item, i) in zip(a, 0..) do item.x = i;
  const aChoices = rs.choose(a, 4),
        aChoice = rs.choose(a);
  writeln(aChoices, "\n", aChoice);
}

record rec {
  var x: int;
}
