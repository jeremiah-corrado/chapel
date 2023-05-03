use List;

var l = new list([1, 2, 3, 3, 3, 4, 5, 6]);

var (numRemoved, lNew) = l.removeCpy(3, 3);
writeln("Removed: ", numRemoved, " lNew: ", lNew);
