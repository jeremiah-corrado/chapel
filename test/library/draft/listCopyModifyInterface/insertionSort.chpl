use List, Time, Random;
use Memory.Diagnostics;

config param useInsertCpy = true,
             memDiag = false;

config const verbose = false,
             n = 100;

proc insertSort(in values: list(int)): list(int)
  where useInsertCpy == true
{
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

proc insertSort(in values: list(int)): list(int)
  where useInsertCpy == false
{
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

var x : [0..<n] int; fillRandom(x);
var unsorted = new list(x);

var s = new stopwatch();
s.start();
if memDiag then startVerboseMemHere();
var sorted = insertSort(unsorted);
if memDiag then stopVerboseMemHere();
s.stop();

if verbose {
  if n <= 20 then writeln("unsorted: ", unsorted);
  if n <= 20 then writeln("sorted: ", sorted);
  writeln("elpased: ", s.elapsed());
}

if memDiag then printMemAllocs();
if memDiag then printMemAllocStats();
