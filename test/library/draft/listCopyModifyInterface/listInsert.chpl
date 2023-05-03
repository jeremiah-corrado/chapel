use List;

var l = new list(0..<10);

var (added, lNew) = l.insertCpy(5, 100);
writeln("Added: ", added, " List: ", lNew);

(added, lNew) = l.insertCpy(11, 100);
writeln("Added: ", added, " List: ", lNew);
