// Copyright Virginia Tech 2024, all rights reserved
// License granted to HPE for internal diagnostic, validation, and verification of the Chapel compiler and runtime's support for distributed parallel IO
// For all other uses please contact sath6220@cs.vt.edu and/or feng@cs.vt.edu
// Author: Paul Sathre
prototype module MLPageError {
  use IO;
  use IO.FormattedIO;
  use CTypes;

  config var filePrefix = "";
  config var avgDensity : int = 8;
  config var targetFileLength = 1024*1024*1024;
  config var producer : bool = false;
  config var replaceWeights : bool = false;
  config var numParts : int = 1;


  //Contains all the descriptor variables. Don't worry about binVers or flags, they are orthogonal to the bug
  class CSR_base : readDeserializable, writeSerializable {
    var binVers : int(64) = 0;
    var numVerts : int(64) = 0;
    var numEdges : int(64) = 0;
    var flags : int(64) = 0; //compat w/ C++ bitfield, contains runtime eltType info that's elided out of this reproducer
    override proc serialize(writer: fileWriter(?), ref serializer: ?st) throws {
      if (st == binarySerializer) {
        try! writer.write(binVers);
        try! writer.write(numVerts);
	    try! writer.write(numEdges);
        try! writer.write(flags);
      } else {
        var ret = "" : string;
        ret += try! "%?, %?".format(this.type:string, c_ptrToConst(this) : c_ptrConst(void)) + ": {";
        ret += try! "binVers = %?, numVerts = %?, numEdges = %?, flags = %?".format(binVers, numVerts, numEdges, flags);
        ret += "}";
        writer.write(ret);
      }
    }
    override proc deserialize(reader: fileReader(?), ref deserializer: ?dt) throws {
      if (dt == binaryDeserializer) {
        try! reader.read(binVers);
        try! reader.read(numVerts);
        try! reader.read(numEdges);
        try! reader.read(flags);
      } else {
        assert(false, "CSR_base text read not supported!");
      }
    }
    proc getPartition(numParts : int, partID : int) : CSR_part {
      var rem = this.numVerts % numParts;
      var size = this.numVerts / numParts;
      //Distribute any remainder to the first rem partitions
      var partStart = (partID*size + (if (partID < rem) then partID else rem));
      var partEnd = ((partID+1)*size + (if (partID < rem) then (partID+1) else rem));
      return new CSR_part(binVers = this.binVers, numVerts = this.numVerts, numEdges = this.numEdges, flags = this.flags, numParts = numParts, partID = partID, partStart = partStart, partEnd = partEnd);
    }
  }

  class CSR_part : CSR_base, readDeserializable, writeSerializable {
    var numParts : int = 1;
    var partID : int = 0;
    var partStart : int(64) = 0; //inclusive
    var partEnd : int(64) = numVerts; //exclusive
    //Above here is expected to be init'd during object creation, below in the deserialize
    var partStartIdx : int(64) = 0; //inclusive
    var partEndIdx : int(64) = numEdges; //exclusive
    var oDom : domain(1) = {0..0}; //partVerts+1
    var iDom : domain(1) = {0..0}; //partEdges
    var wDom : domain(1) = {0..0}; //partEdges
    //non-generic eltTypes for simplicity
    var offsets : [oDom] int(32);
    var indices : [iDom] int(32);
    var weights : [wDom] real(32);
    override proc serialize(writer: fileWriter(?), ref serializer: ?st) throws {
      if (st == binarySerializer) {
        super.serialize(writer, serializer); //This header write is invariant in practice, but technically violated "non-overlapping"
        var sizeOfBase = 32;
        var startOfOffsets = sizeOfBase;
        var startOfIndices = startOfOffsets + (numVerts+1)*numBytes(offsets.eltType);
        var startOfWeights = startOfIndices + (numEdges)*numBytes(indices.eltType);
        var oSize : int(64) = partEnd-partStart+(if (partID == numParts-1) then 1 else 0); //Don't overlap, last partition writes the extra elemen
        on writer._home {
          const olocal = offsets[0..#oSize],
                ilocal = indices,
                wlocal = weights;
          
          try! writer.seek((startOfOffsets+(partStart*numBytes(offsets.eltType)))..#(oSize*numBytes(offsets.eltType)));
          try! writer.write(olocal);
          var iwSize : int(64) = partEndIdx-partStartIdx;
          try! writer.seek((startOfIndices+(partStartIdx*numBytes(indices.eltType)))..#(iwSize*numBytes(indices.eltType)));
          try! writer.write(ilocal);
          try! writer.seek((startOfWeights+(partStartIdx*numBytes(weights.eltType)))..#(iwSize*numBytes(weights.eltType)));
          try! writer.write(wlocal);
        }
      } else {
        var ret = "" : string;
        super.serialize(writer, serializer);
        ret += " -> ";
        ret += try! "%?, %?".format(this.type:string, c_ptrToConst(this) : c_ptrConst(void)) + ": {";
        ret += try! "numParts = %?, partID = %?, partStart = %?, partEnd = %?, partStartIdx = %?, partEndIdx = %?,".format(numParts, partID, partStart, partEnd, partStartIdx, partEndIdx);
        if oDom.size <= 6
            then ret += try! "empty CSR_part: oDom = %?".format(oDom);
            else ret += try! "oDom = %?, offsets = [%? ... %?], iDom = %?, indices = [%? ... %?], wDom = %?, weights = [%? ... %?]".format(oDom, offsets[0..#3], offsets[..oDom.highBound#-3], iDom, indices[0..#3], indices[..iDom.highBound#-3], wDom, weights[0..#3], weights[..wDom.highBound#-3]);
        ret += "}\n";
        writer.write(ret);
      }
    }
    override proc deserialize(reader: fileReader(?), ref deserializer: ?dt) throws {
      if (dt == binaryDeserializer) {
        var header : CSR_base = new CSR_base();
        reader.read(header);
        //This is where we'd confirm that this instance matches the runtime eltType info that's been elided
        assert((this.binVers == header.binVers &&
                this.numVerts == header.numVerts &&
                this.numEdges == header.numEdges &&
                this.flags == header.flags),
                "Error reading ", this.type : string, " from incompatible binary representation header:%?, this:%?".format(header, this));
        var sizeOfBase = 32;
        var startOfOffsets = sizeOfBase;
        var startOfIndices = startOfOffsets + (numVerts+1)*numBytes(offsets.eltType);
        var startOfWeights = startOfIndices + (numEdges)*numBytes(indices.eltType);
        var oSize : int(64) = partEnd-partStart+1;
        oDom = {0..#oSize};
        try! reader.seek((startOfOffsets+(partStart*numBytes(offsets.eltType)))..#(oSize*numBytes(offsets.eltType)));
        try! reader.read(offsets);
        partStartIdx = offsets[0];
        partEndIdx = offsets[oDom.highBound];
        var iwSize : int(64) = partEndIdx-partStartIdx;
        iDom={0..#iwSize};
        try! reader.seek((startOfIndices+(partStartIdx*numBytes(indices.eltType)))..#(iwSize*numBytes(indices.eltType)));
        try! reader.read(indices);
        wDom={0..#iwSize};
        try! reader.seek((startOfWeights+(partStartIdx*numBytes(weights.eltType)))..#(iwSize*numBytes(weights.eltType)));
        try! reader.read(weights);
      } else {
        assert(false, "CSR_part text read not supported!");
      }
    }
    proc copyForOutput() : CSR_part {
      return new CSR_part (
        binVers = this.binVers,
        numVerts = this.numVerts,
        numEdges = this.numEdges,
        flags = this.flags,
        numParts = this.numParts,
        partID = this.partID,
        partStart = this.partStart,
        partEnd = this.partEnd,
        partStartIdx = this.partStartIdx,
        partEndIdx = this.partEndIdx,
        oDom = this.oDom,
        offsets = this.offsets,
        iDom = this.iDom,
        indices = this.indices,
        //Don't copy weights, just its domain, since we are replacing them with the kernel vals
        wDom = this.wDom
      );
    }
  }

  proc main () {
    if (producer) {
      produceFile();
    } else {
      consumeFile();
    }
  }

  inline proc compArrSize() : 2*int(64) { //returns (numVerts, numEdges)
    var elms : int(64) = (2*avgDensity+1); //1 vertex + avgDensity neighbors and weights, everybody is 32-bit
    var verts : int(64) = (targetFileLength / elms) + (if targetFileLength % elms != 0 then 1 else 0);
    var edges : int(64) = verts*avgDensity;
    return (verts, edges);
  }

  //This is just a single-task generator
  proc produceFile() {
    var arrSizes = compArrSize();
    var CSR = new CSR_part(binVers=2, numVerts = arrSizes(0), numEdges = arrSizes(1), flags=8675309, oDom = {0..arrSizes(0)}, iDom = {0..<arrSizes(1)}, wDom = {0..<arrSizes(1)});
    forall o in CSR.oDom do {
      CSR.offsets[o] = (o*avgDensity) : int(32); //let every vertex have exactly the same number of neighbors
    }
    forall i in CSR.iDom do {
      CSR.indices[i] = ((i * avgDensity + 1) % CSR.numVerts) : int(32); //typically these would be sorted and not a function, but as long as they are in the range {0..<numVerts} they're fine
    }
    CSR.weights = 42.0;

    var myFile = try! IO.open(filePrefix + ".csr", ioMode.cw);
    var myWriter = try! myFile.writer(serializer=new binarySerializer(endian = ioendian.little, _structured=false), locking = false, hints = IO.ioHintSet.sequential);
    try! myWriter.write(CSR);
    try! myWriter.flush();
    try! myWriter.close();
    try! myFile.fsync();
    try! myFile.close();
  }

  //This is what should trigger the bug(s)
  proc consumeFile() {
    var header = new CSR_base();
    var inFile = try! IO.open(filePrefix + ".csr", ioMode.r);
    var outFile = try! IO.open(filePrefix + ".out.csr", ioMode.cw);
    var myReader = try! inFile.reader(deserializer = new binaryDeserializer(endian = ioendian.little, _structured=false), locking = false, hints = IO.ioHintSet.sequential);
    try! myReader.read(header);
    try! myReader.close();
    writeln(filePrefix, "\'s Header: ", header);
    var myWriter = try! outFile.writer(serializer = new binarySerializer(endian = ioendian.little, _structured = false), locking = false, hints = IO.ioHintSet.sequential);
    //get the header on the FS so we can reopen it in each task in R/W
    try! myWriter.write(header);
    try! myWriter.flush();
    try! myWriter.close();
    try! outFile.fsync();
    try! outFile.close(); 
    //Reopen it in R/W
    outFile = try! IO.open(filePrefix + ".out.csr", ioMode.rw);
    coforall partID in 0..<numParts with (ref header, ref inFile, ref outFile, in myReader, in myWriter) {
      on Locales[partID % Locales.size] {
        //open a new per-task reader and writer to keep seeks separate
        var myInFile = try! IO.open(filePrefix + ".csr", ioMode.r);
        myReader = try! myInFile.reader(deserializer = new binaryDeserializer(endian = ioendian.little, _structured=false), locking = false, hints = IO.ioHintSet.sequential);
        //This is reliably segfaulting somewhere deep inside deserialize with mb=1, locs=2, parts=2
        //myReader = try! inFile.reader(deserializer = new binaryDeserializer(endian = ioendian.little, _structured=false), locking = false, hints = IO.ioHintSet.sequential);
        myWriter = try! outFile.writer(serializer = new binarySerializer(endian = ioendian.little, _structured = false), locking = false, hints = IO.ioHintSet.sequential);
        var myPart = header.getPartition(numParts, partID);
        try! myReader.read(myPart);
        try! myReader.close();
        try! myInFile.close();
        writeln("Read partition: ", myPart);
        var outPart = myPart.copyForOutput();
        if (replaceWeights) {
          outPart.weights = 42.0; //Replace the kernel outputs
        } else {
          outPart.weights = myPart.weights;
        }
        writeln("Writing partition: ", outPart);
        try! myWriter.write(outPart);
        try! myWriter.flush();
        try! myWriter.close();
      }
    }
    try! inFile.close();
    try! outFile.fsync();
    try! outFile.close();
  }
}
