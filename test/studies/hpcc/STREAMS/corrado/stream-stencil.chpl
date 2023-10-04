// a variation of '../bradc/stream-block1d-dom.chpl' to ensure that
// stencilDist incurs little to no overhead w.r.t. blockDist for stream
// (or other embarrassingly parallel computations)

use Time, Types, Random;
use StencilDist;

use HPCCProblemSize;


param numVectors = 3;
type elemType = real(64);

config const m = computeProblemSize(elemType, numVectors),
             alpha = 3.0;

config const numTrials = 10,
             epsilon = 0.0;

config const useRandomSeed = true,
             seed = if useRandomSeed then SeedGenerator.oddCurrentTime else 314159265;

config const printParams = true,
             printArrays = false,
             printStats = true;

enum KernelKind {
  access,
  zippered,
  promotion
}

config param Kernel = KernelKind.zippered_indices;

proc main() {
  printConfiguration();

  const SD = new stencilDist(rank=1, idxType=int(64), boundingBox={1..m}, targetLocales=Locales, fluff=(1,));

  const ProblemSpace = SD.createDomain({1..m});

  var A, B, C: [ProblemSpace] elemType;

  initVectors(B, C);

  var execTime: [1..numTrials] real;

  for trial in 1..numTrials {
    const startTime = timeSinceEpoch().totalSeconds();

    if Kernel == KernelKind.access {
      forall i in ProblemSpace with (ref A) do
        A(i) = B(i) + alpha * C(i);

    } else if Kernel == KernelKind.zippered {
      forall (a, b, c) in zip(A, B, C) do
        a = b + alpha * c;

    } else if Kernel == KernelKind.promotion {
      A = B + alpha * C;
    }

    execTime(trial) = timeSinceEpoch().totalSeconds() - startTime;
  }

  const validAnswer = verifyResults(A, B, C);
  printResults(validAnswer, execTime);
}


proc printConfiguration() {
  if (printParams) {
    printProblemSize(elemType, numVectors, m);
    writeln("Number of trials = ", numTrials, "\n");
  }
}


proc initVectors(ref B, ref C) {
  var randlist = new owned NPBRandomStream(eltType=real, seed=seed);

  randlist.fillRandom(B);
  randlist.fillRandom(C);

  if (printArrays) {
    writeln("B is: ", B, "\n");
    writeln("C is: ", C, "\n");
  }
}


proc verifyResults(A, B, C) {
  if (printArrays) then writeln("A is: ", A, "\n");

  const infNorm = max reduce [i in A.domain] abs(A(i) - (B(i) + alpha * C(i)));

  return (infNorm <= epsilon);
}


proc printResults(successful, execTimes) {
  writeln("Validation: ", if successful then "SUCCESS" else "FAILURE");
  if (printStats) {
    const totalTime = + reduce execTimes,
          avgTime = totalTime / numTrials,
          minTime = min reduce execTimes;
    writeln("Execution time:");
    writeln("  tot = ", totalTime);
    writeln("  avg = ", avgTime);
    writeln("  min = ", minTime);

    const GBPerSec = numVectors * numBytes(elemType) * (m / minTime) * 1e-9;
    writeln("Performance (GB/s) = ", GBPerSec);
  }
}
