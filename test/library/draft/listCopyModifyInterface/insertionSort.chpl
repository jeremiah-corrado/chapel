use List;

use Memory.Diagnostics;

proc insertSortCpy(in values: list(int)): list(int) {
  var sorted = new list([values.pop()]);
  while values.size > 0 {
    var next = values.pop();
    for i in 0..sorted.size {
      if i > sorted.size - 1 {
        sorted.append(next);
        break;
      } else if sorted[i] > next {
        var (_, nextList) = sorted.insertCpy(i, next);
        sorted = nextList;
        break;
      }
    }
  }
  return sorted;
}

proc insertSort(in values: list(int)): list(int) {
  var sorted = new list([values.pop()]);
  while values.size > 0 {
    var next = values.pop();
    for i in 0..sorted.size {
      if i > sorted.size - 1 {
        sorted.append(next);
        break;
      } else if sorted[i] > next {
        sorted.insert(i, next);
        break;
      }
    }
  }
  return sorted;
}

var unsorted = new list([3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5]);

startVerboseMemHere();
var sortedViaCopyInsert = insertSortCpy(unsorted);
stopVerboseMemHere();

// startVerboseMemHere();
var sortedViaInsert = insertSort(unsorted);
// stopVerboseMemHere();

writeln("unsorted: ", unsorted);
writeln("sortedViaCopyInsert: ", sortedViaCopyInsert);
writeln("sortedViaInsert: ", sortedViaInsert);
