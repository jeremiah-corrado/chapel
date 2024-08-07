var globalArray : [1..4] int;

proc getter(ref arg) ref {
  writeln("REF");
  return arg;
}

proc getter(const ref arg) const ref {
  writeln("CONST REF");
  return arg;
}

proc readit(x) {
  var tmp = x;
}

proc readCaptureCoforall(ref A) {
  coforall i in 1..10 with (ref A) {
    readit(A);
  }
}

proc readCaptureCobegin(ref A) {
  cobegin with (ref A) {
    readit(A);
    readit(A);
  }
}

proc readCaptureBegin(ref A) {
  sync {
    begin with (ref A) {
      readit(A);
    }
  }
}



writeln("READS");
readCaptureCoforall(getter(globalArray));
readCaptureCobegin(getter(globalArray));
readCaptureBegin(getter(globalArray));

proc writeit(ref x) {
  x = 1;
}

proc writeCaptureForall(ref A) {
  forall i in 1..10 with (ref A) {
    writeit(A);
  }
}

proc writeCaptureCoforall(ref A) {
  coforall i in 1..10 with (ref A) {
    writeit(A);
  }
}

proc writeCaptureCobegin(ref A) {
  cobegin with (ref A) {
    writeit(A);
    writeit(A);
  }
}

proc writeCaptureBegin(ref A) {
  sync {
    begin with (ref A) {
      writeit(A);
    }
  }
}


writeln("WRITES");
writeCaptureForall(getter(globalArray));
writeCaptureCoforall(getter(globalArray));
writeCaptureCobegin(getter(globalArray));
writeCaptureBegin(getter(globalArray));
