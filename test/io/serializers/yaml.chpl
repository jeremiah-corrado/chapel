module Yaml {
  private use IO;

  config param YamlVerbose = true;

  public import this.SerializerHelp.SequenceStyle,
                this.SerializerHelp.MappingStyle,
                this.SerializerHelp.ScalarStyle;

  private import this.SerializerHelp.LibYamlEmitter,
                 this.DeserializerHelp.LibYamlParser;

  private import this.SerializerHelp.YamlEmitterError,
                 this.DeserializerHelp.YamlParserError,
                 this.DeserializerHelp.YamlTypeMismatchError,
                 this.DeserializerHelp.YamlEventMismatchError,
                 this.DeserializerHelp.EventType;

  type _writeType = fileWriter(serializerType=yamlSerializer, ?);
  type _readType = fileReader(deserializerType=yamlDeserializer, ?);

  record yamlSerializer {
    @chpldoc.nodoc
    var emitter: unmanaged LibYamlEmitter;
    @chpldoc.nodoc
    var contextLevel: uint = 0;
    @chpldoc.nodoc
    var contextStartOffset: uint = 0;

    proc init(
      seqStyle: SequenceStyle = SequenceStyle.Any,
      mapStyle: MappingStyle = MappingStyle.Any,
      scalarStyle: ScalarStyle = ScalarStyle.Any
    ) {
      this.emitter = new unmanaged LibYamlEmitter(seqStyle, mapStyle, scalarStyle);
      this.complete();
      try! this.emitter.prepSerialization();
    }

    @chpldoc.nodoc
    proc init(
      emitter: unmanaged LibYamlEmitter,
      contextLevel,
      contextStartOffset = 0
    ) {
      this.emitter = emitter;
      this.contextLevel = contextLevel;
      this.contextStartOffset = contextStartOffset;
    }

    @chpldoc.nodoc
    proc deinit() {
      delete this.emitter;
    }

    proc serializeValue(writer: _writeType, const val: ?t) throws {
      var startOffset, endOffset: uint(64) = 0;
      // import Reflection.canResolve;

      // TODO: should use reflection here, but this is not working:
      // if canResolve(":", val, bytes) {
      //   const valBytes = val: bytes;
      //   (startOffset, endOffset) = this.emitter.emit(valBytes);

      if _isIoPrimitiveType(t) || isRangeType(t) {
        const valBytes = "%t".format(val): bytes;
        (startOffset, endOffset) = this.emitter.emitScalar(valBytes);
      } else {
        if isClassType(t) {
          if val == nil {
            (startOffset, endOffset) = this.emitter.emitScalar(b"~");
          } else {
            val!.serialize(writer, new yamlSerializer(this.emitter, this.contextLevel + 1));
          }
        } else {
          val.serialize(writer, new yamlSerializer(this.emitter, this.contextLevel + 1));
        }
      }

      if contextLevel == 0 && endOffset > 0 {
        writer.writeBinary(this.emitter.extractBytes(startOffset..endOffset));
        this.contextStartOffset = endOffset;
      }
    }

    // -------- composite --------

    proc startClass(writer: _writeType, name: string, size: int) throws {
      this._startMapping(writer);
    }

    proc endClass(writer: _writeType) throws {
      this._endMapping(writer);
    }

    proc startRecord(writer: _writeType, name: string, size: int) throws {
      this._startMapping(writer);
    }

    proc endRecord(writer: _writeType) throws {
      this._endMapping(writer);
    }

    proc serializeField(writer: _writeType, key: string, const val: ?t) throws {
      this.emitter.emitScalar(key:bytes);
      this.serializeValue(writer, val);
    }

    // -------- list --------

    proc startTuple(writer: _writeType, size: int) throws {
      this._startSequence(writer, size);
    }

    proc endTuple(writer: _writeType) throws {
      this._endSequence(writer);
    }

    proc startArray(writer: _writeType, numElements: uint = 0) throws {
      const startOffset = this.emitter.beginSequence();
      if contextLevel == 0 then this.contextStartOffset = startOffset;
      contextLevel += 1;
    }

    proc endArray(writer: _writeType) throws {
      const endOffset = this.emitter.endSequence();
      contextLevel -= 1;
      if contextLevel == 0 {
        writer.writeBinary(this.emitter.extractBytes(this.contextStartOffset..endOffset));
        this.contextStartOffset = endOffset;
      }
    }

    proc startArrayDim(w: _writeType, len: uint) throws {
    }
    proc endArrayDim(w: _writeType) throws {
    }

    proc writeArrayElement(writer: _writeType, const elt: ?t) throws {
      this.serializeValue(writer, elt);
    }

    // -------- map --------

    proc startMap(writer: _writeType, size: uint = 0) throws {
      this._startMapping(writer);
    }

    proc endMap(writer: _writeType) throws {
      this._endMapping(writer);
    }

    proc writeKey(writer: _writeType, const key: ?t) throws {
      this.serializeValue(writer, key);
    }

    proc writeValue(writer: _writeType, const val: ?t) throws {
      this.serializeValue(writer, val);
    }

    // -------- helpers --------

    proc _startMapping(writer: _writeType) throws {
      const startOffset = this.emitter.beginMapping();
      if contextLevel == 0 then this.contextStartOffset = startOffset;
      contextLevel += 1;
    }

    proc _endMapping(writer: _writeType) throws {
      const endOffset = this.emitter.endMapping();
      contextLevel -= 1;
      if contextLevel == 0 {
        writer.writeBinary(this.emitter.extractBytes(this.contextStartOffset..endOffset));
        this.contextStartOffset = endOffset;
      }
    }

    proc _startSequence(writer: _writeType, size: int) throws {
      const startOffset = this.emitter.beginSequence();
      if contextLevel == 0 then this.contextStartOffset = startOffset;
      contextLevel += 1;
    }

    proc _endSequence(writer: _writeType) throws {
      const endOffset = this.emitter.endSequence();
      contextLevel -= 1;
      if contextLevel == 0 {
        writer.writeBinary(this.emitter.extractBytes(this.contextStartOffset..endOffset));
        this.contextStartOffset = endOffset;
      }
    }
  }

  record yamlDeserializer {
    var parser: unmanaged LibYamlParser;
    var strictTypeParsing: bool = false;

    proc init(respectTypeAnnotations: bool = false) {
      this.parser = new unmanaged LibYamlParser();
      this.strictTypeParsing = respectTypeAnnotations;

      // // this would be much better to do here if we could get the filepath upon initialization
      // this.complete()
      // this.parser.prepDeserialization(filePath = ????)
    }

    @chpldoc.nodoc
    proc init(other: yamlDeserializer) {
      this.parser = other.parser;
      this.strictTypeParsing = other.strictTypeParsing;
    }

    @chpldoc.nodoc
    proc deinit() {
      delete this.parser;
    }

    proc deserialize(reader: _readType, type t) : t throws {
      if _isIoPrimitiveType(t) {
        const (startOffset, endOffset) = this.parser.expectEvent(EventType.Scalar, reader);
        reader.seek((startOffset:int)..);
        const valString = reader.readString((endOffset - startOffset):int);

        if valString.startsWith("!!") { // yaml native type is specified...
          const (typeTag, _, value) = valString.partition(" ");
          _checkNativeTypeMatch(typeTag, t);
          return value: t;
        } else if valString.startsWith("!") { // custom type is specified
          const (typeTag, _, value) = valString.partition(" ");
          throw new YamlParserError("cannot parse a " + typeTag + " value as a " + t:string);
        } else { // no type specified
          return valString: t;
        }
      } else if canResolveTypeMethod(t, "deserializeFrom", reader, this) ||
                isArrayType(t) {
        var alias = reader.withDeserializer(new yamlDeserializer(this));
        return t.deserializeFrom(reader=alias, deserializer=alias.deserializer);
      } else {
        var alias = reader.withDeserializer(new yamlDeserializer(this));
        return new t(reader=alias, deserializer=alias.deserializer);
      }
    }

    // -------- composite --------

    proc startClass(reader: _readType, name: string, size: int) throws {
      const typeName = this._startMapping(reader);
      if name != typeName && strictTypeParsing
        then throw new YamlTypeMismatchError(name, typeName);
    }

    proc endClass(reader: _readType) throws {
      this._endMapping(reader);
    }

    proc startRecord(reader: _readType, name: string, size: int) throws {
      const typeName = this._startMapping(reader);
      if name != typeName && strictTypeParsing
        then throw new YamlTypeMismatchError(name, typeName);
    }

    proc endRecord(reader: _readType) throws {
      this._endMapping(reader);
    }

    proc deserializeField(reader: _readType, key: string, type t): t throws {
      const (keyStart, keyEnd) = this.parser.expectEvent(EventType.Scalar, reader);
      reader.seek((keyStart:int)..);
      const foundKey = reader.readString((keyEnd - keyStart):int);

      if foundKey == key then
        throw new YamlParserError("Field not found: " + key);

      return this.deserialize(reader, t);
    }

    // -------- sequence --------

    proc startTuple(reader: _readType, size: int) throws {
      this._startSequence(reader);
    }

    proc endTuple(reader: _readType) throws {
      this._endSequence(reader);
    }

    proc startArray(reader: _readType) throws {
      this._startSequence(reader);
    }

    proc endArray(reader: _readType) throws {
      this._endSequence(reader);
    }

    proc readArrayElement(reader: _readType, type t): t throws {
      return this.deserialize(reader, t);
    }

    // -------- map --------

    proc startMap(reader: _readType) throws {
      this._startMapping(reader);
    }

    proc endMap(reader: _readType) throws {
      this._endMapping(reader);
    }

    proc readKey(reader: _readType, type t) throws {
      return this.deserialize(reader, t);
    }

    proc readValue(reader: _readType, type t) throws {
      return this.deserialize(reader, t);
    }

    // ---------- helpers ----------

    proc _startMapping(reader: _readType): string throws {
      // TODO: expect a scalar event first in case there is a type-tag or anchor
      const typeName = "";
      const (startOffset, _) = this.parser.expectEvent(EventType.MappingStart, reader);
      return typeName;
    }

    proc _endMapping(reader: _readType) throws {
      const (_, endOffset) = this.parser.expectEvent(EventType.MappingEnd, reader);
    }

    proc _startSequence(reader: _readType) throws {
      // TODO: expect a scalar event first in case there is a type-tag or anchor
      const typeName = "";
      const (startOffset, _) = this.parser.expectEvent(EventType.SequenceStart, reader);
      return typeName;
    }

    proc _endSequence(reader: _readType) throws {
      const (_, endOffset) = this.parser.expectEvent(EventType.SequenceEnd, reader);
    }

    proc _checkNativeTypeMatch(typeTag: string, type t) throws {
      if this.strictTypeParsing {
        var matches = false;
        select typeTag {
          when "!!float" do matches = t == real;
          when "!!int" do matches = t == int;
          when "!!str" do matches = t == string || t == bytes;
          when "!!bool" do matches = t == bool;
          when "!!binary" do matches = t == bytes; //???
          otherwise matches = false;
        }
        if !matches then
          throw new YamlTypeMismatchError(t, typeTag);
      }
    }
  }

  private module SerializerHelp {
    private use CTypes;
    require "yaml.h", "-lyaml";

    config param YamlVerbose = true;

    // a chapel wrapper around the libyaml emitter
    class LibYamlEmitter {
      var seqStyle: SequenceStyle;
      var mapStyle: MappingStyle;
      var sStyle: ScalarStyle;

      var emitter: yaml_emitter_t;
      var event: yaml_event_t;

      var file: c_FILE;
    }

    // ----------------------------------------
    // initialization
    // ----------------------------------------

    proc LibYamlEmitter.init(
      sequences = SequenceStyle.Any,
      mappings = MappingStyle.Any,
      scalars = ScalarStyle.Any
    ) {
      this.seqStyle = sequences;
      this.mapStyle = mappings;
      this.sStyle = scalars;

      var emitter: yaml_emitter_t;
      var event: yaml_event_t;
      c_memset(c_ptrTo(emitter):c_void_ptr, 0, c_sizeof(yaml_emitter_t));
      c_memset(c_ptrTo(event):c_void_ptr, 0, c_sizeof(yaml_event_t));
      this.emitter = emitter;
      this.event = event;
    }

    proc LibYamlEmitter.prepSerialization() throws {
      this.file = tmpfile();
      // if this.file == nil then
      //   throw new YamlEmitterError("Failed to open temporary file");

      if !yaml_emitter_initialize(c_ptrTo(this.emitter))
        then throw new YamlEmitterError("Failed to initialize emitter");

      yaml_emitter_set_output_file(c_ptrTo(this.emitter), this.file);
      yaml_emitter_set_canonical(c_ptrTo(this.emitter), 0);
      yaml_emitter_set_unicode(c_ptrTo(this.emitter), 1);

      this._startOutputStream();
      this.startDocument();
    }

    proc LibYamlEmitter.extractBytes(r: range(idxType=uint, stridable=false, ?)): bytes {
      if YamlVerbose then writeln("Extracting bytes: ", r.low, "..", r.high);
      fseek(this.file, r.low:c_ssize_t, SEEK_SET);
      var buf = c_malloc(uint(8), r.size);
      fread(buf, 1, r.size, this.file);

      const b = createBytesWithOwnedBuffer(buf, r.size, r.size);
      c_free(buf);

      return b;
    }

    proc LibYamlEmitter.deinit() {
      try! this.endDocument();
      try! this._endOutputStream();
      // TODO: fix this after:  https://github.com/chapel-lang/chapel/issues/22073
      // if this.file != nil then
        fclose(this.file);
      yaml_emitter_delete(c_ptrTo(this.emitter));
      yaml_event_delete(c_ptrTo(this.event));
    }

    // this is weird
    proc LibYamlEmitter.serialize(fw, serializer) throws {
      fw.write("---LimYamlEmitter---");
    }

    // ----------------------------------------
    // serialization
    // ----------------------------------------

    proc LibYamlEmitter._startOutputStream() throws {
      if YamlVerbose then writeln("Starting output stream");

      if !yaml_stream_start_event_initialize(
        c_ptrTo(this.event),
        YAML_UTF8_ENCODING
      ) then throw new YamlEmitterError("Failed to initialize stream start event");

      this.emitEvent(errorMsg = "Failed to emit stream start event");
    }

    proc LibYamlEmitter._endOutputStream() throws {
      if YamlVerbose then writeln("Ending output stream");

      if !yaml_stream_end_event_initialize(c_ptrTo(this.event))
        then throw new YamlEmitterError("Failed to initialize stream end event");

      this.emitEvent(errorMsg = "Failed to emit stream end event");
    }

    proc LibYamlEmitter.beginSequence(): uint throws {
      if YamlVerbose then writeln("Starting sequence");

      if !yaml_sequence_start_event_initialize(
        c_ptrTo(this.event),
        nil, // TODO: anchor support
        nil, // TODO: tag support
        1,
        this.seqStyleC
      ) then throw new YamlEmitterError("Failed to initialize sequence start event");

      return this.emitEvent(errorMsg = "Failed to emit sequence start event")[0];
    }

    proc LibYamlEmitter.endSequence(): uint throws {
      if YamlVerbose then writeln("Ending sequence");

      if !yaml_sequence_end_event_initialize(c_ptrTo(this.event))
        then throw new YamlEmitterError("Failed to initialize sequence end event");

      return this.emitEvent(errorMsg = "Failed to emit sequence end event")[1];
    }

    proc LibYamlEmitter.beginMapping(): uint throws {
      if YamlVerbose then writeln("Starting mapping");

      if !yaml_mapping_start_event_initialize(
        c_ptrTo(this.event),
        nil, // TODO: anchor support
        nil, // TODO: tag support
        1,
        this.mapStyleC
      ) then throw new YamlEmitterError("Failed to initialize mapping start event");

      return this.emitEvent(errorMsg = "Failed to emit mapping start event")[0];
    }

    proc LibYamlEmitter.endMapping(): uint throws {
      if YamlVerbose then writeln("Ending mapping");

      if !yaml_mapping_end_event_initialize(c_ptrTo(this.event))
        then throw new YamlEmitterError("Failed to initialize mapping end event");

      return this.emitEvent(errorMsg = "Failed to emit mapping end event")[1];
    }

    proc LibYamlEmitter.emitScalar(value: bytes, tag: bytes = b""): 2*uint throws {
      if YamlVerbose then writeln("Emitting scalar: ", value);

      var v = value, t = tag;
      if !yaml_scalar_event_initialize(
        c_ptrTo(this.event),
        nil, // TODO: anchor support
        if tag.numBytes > 0 then c_ptrTo(t) else nil,
        c_ptrTo(v),
        value.numBytes: c_int,
        (if tag.numBytes > 0 then 0 else 1): c_int,
        (if tag.numBytes > 0 then 0 else 1): c_int,
        this.sStyleC
      ) then throw new YamlEmitterError("Failed to initialize scalar event");

      return this.emitEvent(errorMsg = "Failed to emit scalar event");
    }

    proc LibYamlEmitter.emitAlias(value: bytes): 2*uint throws {
      if !yaml_alias_event_initialize(c_ptrTo(this.event), c_ptrTo(value))
        then throw new YamlEmitterError("Failed to initialize alias event");

      return this.emitEvent(errorMsg = "Failed to emit alias event");
    }

    proc LibYamlEmitter.startDocument(implicitStart: bool = true): uint throws {
      if !yaml_document_start_event_initialize(c_ptrTo(this.event), nil, nil, nil, implicitStart:c_int)
        then throw new YamlEmitterError("Failed to initialize document start event");

      return this.emitEvent(errorMsg = "Failed to emit document start event")[0];
    }

    proc LibYamlEmitter.endDocument(implicitEnd: bool = true): uint throws {
      if !yaml_document_end_event_initialize(c_ptrTo(this.event), implicitEnd:c_int)
        then throw new YamlEmitterError("Failed to initialize document end event");

      return this.emitEvent(errorMsg = "Failed to emit document end event")[1];
    }

    // ----------------------------------------
    // helpers
    // ----------------------------------------

    proc LibYamlEmitter.emitEvent(param errorMsg: string): 2*uint throws {
      const start_pos = ftell(this.file);

      if !yaml_emitter_emit(c_ptrTo(this.emitter), c_ptrTo(this.event))
        then throw new YamlEmitterError(errorMsg);

      // if YamlVerbose then writeln("Emitting event over: ", this.event.start_mark.idx, " to ", this.event.end_mark.idx);
      // writeln("start column: ", this.event.start_mark.column, " end column: ", this.event.end_mark.column);
      // writeln("start line: ", this.event.start_mark.line, " end line: ", this.event.end_mark.line);

      const end_pos = ftell(this.file);
      writeln("emitting event over: ", start_pos, " to ", end_pos);

      return (start_pos, end_pos);

      // return (this.event.start_mark.idx, this.event.end_mark.idx);
    }

    proc LibYamlEmitter.seqStyleC: c_int {
      select this.seqStyle {
        when SequenceStyle.Any do return YAML_ANY_SEQUENCE_STYLE;
        when SequenceStyle.Block do return YAML_BLOCK_SEQUENCE_STYLE;
        when SequenceStyle.Flow do return YAML_FLOW_SEQUENCE_STYLE;
      }
      return YAML_ANY_SEQUENCE_STYLE;
    }

    proc LibYamlEmitter.mapStyleC: c_int {
      select this.mapStyle {
        when MappingStyle.Any do return YAML_ANY_MAPPING_STYLE;
        when MappingStyle.Block do return YAML_BLOCK_MAPPING_STYLE;
        when MappingStyle.Flow do return YAML_FLOW_MAPPING_STYLE;
      }
      return YAML_ANY_MAPPING_STYLE;
    }

    proc LibYamlEmitter.sStyleC: c_int {
      select this.sStyle {
        when ScalarStyle.Any do return YAML_ANY_SCALAR_STYLE;
        when ScalarStyle.Plain do return YAML_PLAIN_SCALAR_STYLE;
        when ScalarStyle.SingleQuoted do return YAML_SINGLE_QUOTED_SCALAR_STYLE;
        when ScalarStyle.DoubleQuoted do return YAML_DOUBLE_QUOTED_SCALAR_STYLE;
        when ScalarStyle.Literal do return YAML_LITERAL_SCALAR_STYLE;
        when ScalarStyle.Folded do return YAML_FOLDED_SCALAR_STYLE;
      }
      return YAML_ANY_SCALAR_STYLE;
    }

    // ----------------------------------------
    // libyaml C API
    // ----------------------------------------

    // relevant types
    extern record yaml_emitter_t { }
    extern record yaml_event_t {
      var start_mark: yaml_mark_t;
      var end_mark: yaml_mark_t;
    }
    extern record yaml_mark_t {
      extern "index" var idx: c_size_t; // byte index in the file
      var line: c_size_t;
      var column: c_size_t;
    }
    extern record yaml_version_directive_t {
      var major: c_int;
      var minor: c_int;
    }
    extern record yaml_tag_directive_t {
      var handle: c_string;
      var prefix: c_string;
    }

    // encodings and styles
    extern const YAML_ANY_ENCODING: c_int;
    extern const YAML_UTF8_ENCODING: c_int;
    extern const YAML_UTF16LE_ENCODING: c_int;
    extern const YAML_UTF16BE_ENCODING: c_int;

    extern const YAML_ANY_SEQUENCE_STYLE: c_int;
    extern const YAML_BLOCK_SEQUENCE_STYLE: c_int;
    extern const YAML_FLOW_SEQUENCE_STYLE: c_int;

    extern const YAML_ANY_MAPPING_STYLE: c_int;
    extern const YAML_BLOCK_MAPPING_STYLE: c_int;
    extern const YAML_FLOW_MAPPING_STYLE: c_int;

    extern const YAML_ANY_SCALAR_STYLE: c_int;
    extern const YAML_PLAIN_SCALAR_STYLE: c_int;
    extern const YAML_SINGLE_QUOTED_SCALAR_STYLE: c_int;
    extern const YAML_DOUBLE_QUOTED_SCALAR_STYLE: c_int;
    extern const YAML_LITERAL_SCALAR_STYLE: c_int;
    extern const YAML_FOLDED_SCALAR_STYLE: c_int;

    // emitter API
    private extern proc yaml_emitter_initialize(emitter: c_ptr(yaml_emitter_t)): c_int;
    private extern proc yaml_emitter_set_output_file(emitter: c_ptr(yaml_emitter_t), file: c_FILE): c_int;
    private extern proc yaml_emitter_set_canonical(emitter: c_ptr(yaml_emitter_t), isC: c_int);
    private extern proc yaml_emitter_set_unicode(emitter: c_ptr(yaml_emitter_t), isU: c_int);
    private extern proc yaml_emitter_emit(emitter: c_ptr(yaml_emitter_t), event: c_ptr(yaml_event_t)): c_int;
    private extern proc yaml_emitter_delete(emitter: c_ptr(yaml_emitter_t));

    // event API
    private extern proc yaml_event_delete(event: c_ptr(yaml_event_t));

    private extern proc yaml_stream_start_event_initialize(event: c_ptr(yaml_event_t), encoding: c_int): c_int;
    private extern proc yaml_stream_end_event_initialize(event: c_ptr(yaml_event_t)): c_int;

    private extern proc yaml_document_start_event_initialize(
                        event: c_ptr(yaml_event_t),
                        version: c_ptr(yaml_version_directive_t),
                        start: c_ptr(yaml_tag_directive_t),
                        end: c_ptr(yaml_tag_directive_t),
                        implicit: c_int
                      ): c_int;
    private extern proc yaml_document_end_event_initialize(event: c_ptr(yaml_event_t), implicit: c_int): c_int;

    private extern proc yaml_sequence_start_event_initialize(
                          event: c_ptr(yaml_event_t),
                          anchor: c_ptr(c_uchar),
                          tag: c_ptr(c_uchar),
                          implicit: c_int,
                          style: c_int
                        ): c_int;
    private extern proc yaml_sequence_end_event_initialize(event: c_ptr(yaml_event_t)): c_int;

    private extern proc yaml_mapping_start_event_initialize(
                          event: c_ptr(yaml_event_t),
                          anchor: c_ptr(c_uchar),
                          tag: c_ptr(c_uchar),
                          implicit: c_int,
                          style: c_int
                        ): c_int;
    private extern proc yaml_mapping_end_event_initialize(event: c_ptr(yaml_event_t)): c_int;

    private extern proc yaml_scalar_event_initialize(
                          event: c_ptr(yaml_event_t),
                          anchor: c_ptr(c_uchar),
                          tag: c_ptr(c_uchar),
                          value: c_ptr(c_uchar),
                          length: c_int,
                          plain_implicit: c_int,
                          quoted_implicit: c_int,
                          style: c_int
                        ): c_int;
    private extern proc yaml_alias_event_initialize(event: c_ptr(yaml_event_t), anchor: c_ptr(c_uchar)): c_int;

    private extern proc fopen(filename: c_string, mode: c_string): c_FILE;
    private extern proc fclose(file: c_FILE): c_int;
    private extern proc fseek(file: c_FILE, offset: c_long, origin: c_int): c_int;
    private extern proc tmpfile(): c_FILE;
    private extern proc fread(ptr: c_ptr(c_uchar), size: c_size_t, nmemb: c_size_t, stream: c_FILE): c_size_t;
    private extern proc ftell(stream: c_FILE): c_long;
    extern const SEEK_SET: c_int;

    // ----------------------------------------
    // enums and errors
    // ----------------------------------------

    /*
      The style to use when serializing a sequence.

      * ``Default`` - let the implementation decide
      * ``Block`` - wrap the sequence in '[' and ']' with elements separated by ','
      * ``Flow`` - represent the sequence on multiple lines starting with '-'
    */
    enum SequenceStyle {
      Any, // YAML_ANY_SEQUENCE_STYLE,
      Block, // YAML_BLOCK_SEQUENCE_STYLE,
      Flow // YAML_FLOW_SEQUENCE_STYLE
    }

    /*
      The style to use when serializing a mapping. This includes
      records, classes, and the Chapel ``map`` type

      * ``Any`` - let the implementation decide
      * ``Block`` - wrap the mapping in '{' and '}' with keys and values separated by ':'
      * ``Flow`` - represent the mapping as a heirarchy of key-value pairs separated by ':'
    */
    enum MappingStyle {
      Any, // YAML_ANY_MAPPING_STYLE,
      Block, // YAML_BLOCK_MAPPING_STYLE,
      Flow // YAML_FLOW_MAPPING_STYLE
    }

    /*
      The style to use when serializing a scalar.

      * ``Any`` - let the implementation decide
      * ``Plain`` - use the plain scalar style
      * ``SingleQuoted`` - wrap string values in single-quotes
      * ``DoubleQuoted`` - wrap string values in double-quotes
      * ``Literal`` - represent string values literally
      * ``Folded`` - represent string values as a folded block
    */
    enum ScalarStyle {
      Any, // YAML_ANY_SCALAR_STYLE,
      Plain, // YAML_PLAIN_SCALAR_STYLE,
      SingleQuoted, // YAML_SINGLE_QUOTED_SCALAR_STYLE,
      DoubleQuoted, // YAML_DOUBLE_QUOTED_SCALAR_STYLE,
      Literal, // YAML_LITERAL_SCALAR_STYLE,
      Folded // YAML_FOLDED_SCALAR_STYLE
    }

    class YamlEmitterError: Error {}

    proc YamlEmitterError.init(msg: string) {
      super.init(msg);
    }
  }

  private module DeserializerHelp {
    private use CTypes;
    require "yaml.h", "-lyaml";

    // a chapel wrapper around the libyaml parser
    class LibYamlParser {
      @chpldoc.nodoc
      var parser: yaml_parser_t;
      @chpldoc.nodoc
      var event: yaml_event_t;

      @chpldoc.nodoc
      var f: c_FILE;
      @chpldoc.nodoc
      var fileIsInit = false;
    }

    // ----------------------------------------
    // initialization
    // ----------------------------------------

    proc LibYamlParser.init() {
      var p: yaml_parser_t;
      var e: yaml_event_t;
      c_memset(c_ptrTo(p):c_void_ptr, 0, c_sizeof(yaml_parser_t));
      c_memset(c_ptrTo(e):c_void_ptr, 0, c_sizeof(yaml_event_t));
      this.parser = p;
      this.event = e;
    }

    proc LibYamlParser.prepDeserialization(filePath: string) throws {
      var f = fopen(filePath.c_str(), c"r");
      // TODO: error handling for file not found
      this.f = f;

      if !yaml_parser_initialize(c_ptrTo(this.parser)) then
        throw new YamlParserError("Failed to initialize YAML parser");

      yaml_parser_set_input_file(c_ptrTo(this.parser), this.f);
      this.fileIsInit = true;
    }

    proc LibYamlParser.deinit() {
      if fileIsInit then fclose(this.f);
      yaml_parser_delete(c_ptrTo(this.parser));
      yaml_event_delete(c_ptrTo(this.event));
    }

    proc LibYamlParser.serialize(fw, serializer) throws {
      fw.write("---LibYamlParser---");
    }

    // ----------------------------------------
    // parsing
    // ----------------------------------------

    proc LibYamlParser._parseNextEvent(fr): (EventType, uint, uint) throws {
      // initialize the parser if not already initialized
      if !fileIsInit {
        const p = fr._tryGetFilePath();
        this.prepDeserialization(p);
      }

      if !yaml_parser_parse(c_ptrTo(this.parser), c_ptrTo(this.event)) then
        throw new YamlParserError("Failed to parse YAML event");

      return (
        parseEventType(event.t),
        this.event.start_mark.idx,
        this.event.end_mark.idx
      );
    }

    proc LibYamlParser.expectEvent(et: EventType, fr): 2*uint throws {
      var (t, s, e) = this._parseNextEvent(fr);
      if t != et then
        throw new YamlEventMismatchError(et, t);
      return (s, e);
    }

    // ----------------------------------------
    // libyaml C API
    // ----------------------------------------

    // relevant types
    extern record yaml_parser_t { }
    extern record yaml_event_t {
      // one of the event types below
      extern "type" var t: c_int;
      // union of structs of event data (not yet representable in Chapel)
      var data: opaque;
      // start and end locations for the event in the input file
      var start_mark: yaml_mark_t;
      var end_mark: yaml_mark_t;
    }
    extern record yaml_mark_t {
      extern "index" var idx: c_size_t; // byte index in the file
      var line: c_size_t;
      var column: c_size_t;
    }

    // parsing event types
    extern const YAML_NO_EVENT: c_int;
    extern const YAML_STREAM_START_EVENT: c_int;
    extern const YAML_STREAM_END_EVENT: c_int;
    extern const YAML_DOCUMENT_START_EVENT: c_int;
    extern const YAML_DOCUMENT_END_EVENT: c_int;
    extern const YAML_ALIAS_EVENT: c_int;
    extern const YAML_SCALAR_EVENT: c_int;
    extern const YAML_SEQUENCE_START_EVENT: c_int;
    extern const YAML_SEQUENCE_END_EVENT: c_int;
    extern const YAML_MAPPING_START_EVENT: c_int;
    extern const YAML_MAPPING_END_EVENT: c_int;

    inline proc parseEventType(t: c_int): EventType throws {
      select t {
        when YAML_NO_EVENT do return EventType.None;
        when YAML_STREAM_START_EVENT do return EventType.StreamStart;
        when YAML_STREAM_END_EVENT do return EventType.StreamEnd;
        when YAML_DOCUMENT_START_EVENT do return EventType.DocumentStart;
        when YAML_DOCUMENT_END_EVENT do return EventType.DocumentEnd;
        when YAML_ALIAS_EVENT do return EventType.Alias;
        when YAML_SCALAR_EVENT do return EventType.Scalar;
        when YAML_SEQUENCE_START_EVENT do return EventType.SequenceStart;
        when YAML_SEQUENCE_END_EVENT do return EventType.SequenceEnd;
        when YAML_MAPPING_START_EVENT do return EventType.MappingStart;
        when YAML_MAPPING_END_EVENT do return EventType.MappingEnd;
        otherwise throw new YamlParserError("Unknown YAML event type");
      }
    }

    // parser API
    private extern proc yaml_parser_initialize(parser: c_ptr(yaml_parser_t)): c_int;
    private extern proc yaml_parser_delete(parser: c_ptr(yaml_parser_t)): c_int;
    private extern proc yaml_parser_set_input_file(parser: c_ptr(yaml_parser_t), file: c_FILE): c_int;
    private extern proc yaml_parser_parse(parser: c_ptr(yaml_parser_t), event: c_ptr(yaml_event_t)): c_int;
    private extern proc yaml_event_delete(event: c_ptr(yaml_event_t));

    private extern proc fopen(filename: c_string, mode: c_string): c_FILE;
    private extern proc fclose(file: c_FILE): c_int;
    extern const SEEK_SET: c_int;

    // ----------------------------------------
    // enums and errors
    // ----------------------------------------

    enum EventType {
      None, // YAML_NO_EVENT
      StreamStart, // YAML_STREAM_START_EVENT
      StreamEnd, // YAML_STREAM_END_EVENT
      DocumentStart, // YAML_DOCUMENT_START_EVENT
      DocumentEnd, // YAML_DOCUMENT_END_EVENT
      Alias, // YAML_ALIAS_EVENT
      Scalar, // YAML_SCALAR_EVENT
      SequenceStart, // YAML_SEQUENCE_START_EVENT
      SequenceEnd, // YAML_SEQUENCE_END_EVENT
      MappingStart, // YAML_MAPPING_START_EVENT
      MappingEnd // YAML_MAPPING_END_EVENT
    }

    class YamlParserError: Error {}

    proc YamlParserError.init(msg: string) {
      super.init(msg);
    }

    class YamlEventMismatchError: YamlParserError {}

    proc YamlEventMismatchError.init(expected: EventType, actual: EventType) {
      super.init("Expected event type " + expected:string + ", got " + actual:string);
    }

    class YamlTypeMismatchError: YamlParserError {}

    proc YamlTypeMismatchError.init(type expected, actual: string) {
      super.init("Expected type " + expected:string + ", got " + actual);
    }

    proc YamlTypeMismatchError.init(expected: string, actual: string) {
      super.init("Expected type " + expected + ", got " + actual);
    }
  }
}
