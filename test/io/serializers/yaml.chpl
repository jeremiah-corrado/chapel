module Yaml {
  private use IO, Regex;

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
    var emitter: shared LibYamlEmitter;

    @chpldoc.nodoc
    var context: shared ContextCounter;

    proc init(
      seqStyle = SequenceStyle.Any,
      mapStyle = MappingStyle.Any,
      scalarStyle = ScalarStyle.Any
    ) {
      this.emitter = new shared LibYamlEmitter(seqStyle, mapStyle, scalarStyle);
      this.context = new shared ContextCounter();
      this.complete();
      // try! this.emitter.prepSerialization();
    }

    @chpldoc.nodoc
    proc init(emitter: shared LibYamlEmitter, context: shared ContextCounter) {
      this.emitter = emitter;
      this.context = context;
    }

    proc serializeValue(writer: _writeType, const val: ?t) throws {
      writeln("serializing value: ", val);

      if this.context.isBase {
        // we aren't in a mapping or a sequence.
        // simply write the value in it's YAML format
        // or call 'serialize' on it if it's a non-primitive type
        if isBoolType(t) {
          writer.writeBytes(if val then b"Yes" else b"No");
        } else if _isIoPrimitiveType(t) || isRangeType(t) {
          writer.writeString("%t".format(val));
        } else {
          if isClassType(t) {
            if val == nil then writer.writeLiteral("~");
            else val!.serialize(writer, new yamlSerializer(this.emitter, this.context));
          } else {
            val.serialize(writer, new yamlSerializer(this.emitter, this.context));
          }
        }
      } else {
        // we are in a mapping or a sequence.
        // write the value to the emitter
        // it will be extracted when the outermost context is closed
        if isBoolType(t) {
          var yamlBoolVal = if val then b"Yes" else b"No";
          this.emitter.emitScalar(yamlBoolVal);
        } else if _isIoPrimitiveType(t) || isRangeType(t) {
          var valBytes = "%t".format(val): bytes;
          this.emitter.emitScalar(valBytes);
        } else {
          if isClassType(t) {
            if val == nil {
              var nullSymbol = b"~";
              this.emitter.emitScalar(nullSymbol);
            } else {
              val!.serialize(writer, new yamlSerializer(this.emitter, this.context));
            }
          } else {
            val.serialize(writer, new yamlSerializer(this.emitter, this.context));
          }
        }
      }
    }

    // -------- composite --------

    proc startClass(writer: _writeType, name: string, size: int) throws {
      writeln("\tstarting class: '", name, "' w/ size: ", size);
      this.context.enterClass();
      this._startMapping(writer, name);
    }

    proc endClass(writer: _writeType) throws {
      writeln("\tending class");
      this._endMapping(writer);
      this.context.leaveClass();
    }

    proc startRecord(writer: _writeType, name: string, size: int) throws {
      writeln("\tstarting record: ", name, " size: ", size);
      this._startMapping(writer, name);
    }

    proc endRecord(writer: _writeType) throws {
      writeln("\tending record");
      this._endMapping(writer);
    }

    proc serializeField(writer: _writeType, key: string, const val: ?t) throws {
      writeln("\t\tserializing field: ", key, " = ", val);
      if key.size > 0 then {
        var kb = key: bytes;
        this.emitter.emitScalar(kb);
      }
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
      // const startOffset = this.emitter.beginSequence();
    }

    proc endArray(writer: _writeType) throws {
      // const endOffset = this.emitter.endSequence();
      //   writer.writeBytes(this.emitter.extractBytes(0..endOffset));
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

    proc _startMapping(writer: _writeType, name: string = "") throws {
      var nb = b"!" + name: bytes;
      if this.context.isBase then this.emitter.openContext();
      this.context.enter();

      // start a new mapping if we aren't already in a class
      if !this.context.inSuperClass then this.emitter.beginMapping(nb);
    }

    proc _endMapping(writer: _writeType) throws {
      this.context.leave();
      if !this.context.inSuperClass {
        this.emitter.endMapping();
      }
        if context.isBase then writer.writeBytes(this.emitter.closeContext());
    }

    proc _startSequence(writer: _writeType, size: int) throws {
      if context.isBase then this.emitter.openContext();
      this.emitter.beginSequence();
      this.context.enter();
    }

    proc _endSequence(writer: _writeType) throws {
      this.context.leave();
      this.emitter.endSequence();
      if this.context.isBase then writer.writeBytes(this.emitter.closeContext());
    }
  }

  class ContextCounter {
    var count = 0;
    var classDepth = 0;

    proc enter() do
      this.count += 1;

    proc leave() do
      this.count -= 1;

    proc isBase: bool do
      return this.count == 0;

    proc enterClass() {
      this.classDepth += 1;
      writeln("\tentered -- class depth: ", this.classDepth);
    }

    proc leaveClass() {
      this.classDepth -= 1;
      writeln("\tleft -- class depth: ", this.classDepth);
    }

    proc inSuperClass: bool do
      return this.classDepth > 1;
  }

  record yamlDeserializer {
    var parser: shared LibYamlParser;
    var context: shared ContextCounter();
    var strictTypeParsing: bool = false;

    proc init(respectTypeAnnotations: bool = false) {
      writeln("***deserializer init***");
      this.parser = new shared LibYamlParser();
      this.context = new shared ContextCounter();
      this.strictTypeParsing = respectTypeAnnotations;
    }

    @chpldoc.nodoc
    proc init(other: yamlDeserializer) {
      writeln("\t\t***deserializer copy init***");
      this.parser = other.parser;
      this.context = other.context;
      this.strictTypeParsing = other.strictTypeParsing;
    }

    proc deinit() {
      writeln("\t\t***deserializer deinit***");
      if this.context.isBase then this.parser.unprep();
    }

    proc deserialize(reader: _readType, type t) : t throws {
      writeln("deserializing type: ", t:string);

      if this.context.isBase {
        if _isIoPrimitiveType(t) {
          var des = reader.withDeserializer(new DefaultDeserializer());
          if isBoolType(t) {
            const v = des.readTo(" ");
            select v {
              when "Yes" do return true;
              when "No" do return false;
              otherwise throw new YamlParserError("invalid boolean value: " + v);
            }
          } else {
            return des.read(t);
          }
        } else if canResolveTypeMethod(t, "deserializeFrom", reader, this) ||
                  isArrayType(t) {
          var alias = reader.withDeserializer(new yamlDeserializer(this));
          const x = t.deserializeFrom(reader=alias, deserializer=alias.deserializer);
          return x;
        } else {
          writeln("\t\t---new alias (B)---");
          var alias = reader.withDeserializer(new yamlDeserializer(this));
          const x = new t(reader=alias, deserializer=alias.deserializer);
          writeln("\t\t---done with alias (B)---");
          return x;
        }
      } else {
        if _isIoPrimitiveType(t) {
          const (startOffset, endOffset) = this.parser.expectEvent(EventType.Scalar, reader);
          reader.seek((startOffset:int)..);
          const valString = reader.readString((endOffset - startOffset):int);
          writeln("\tGot: ", valString);

          proc castVal(v) throws {
            if isBoolType(t) {
              select v {
                when "Yes" do return true;
                when "No" do return false;
                otherwise throw new YamlParserError("Cannot parse: '" + v + "' as a bool");
              }
            } else {
              return v: t;
            }
          }

          if valString.startsWith("!!") { // yaml native type is specified...
            const (typeTag, _, value) = valString.partition(" ");
            _checkNativeTypeMatch(typeTag, t);
            return castVal(value);
          } else if valString.startsWith("!") { // custom type is specified, can't parse as a scalar
            const (typeTag, _, _) = valString.partition(" ");
            throw new YamlParserError("cannot parse a " + typeTag + " value as a " + t:string);
          } else { // no type specified
            return castVal(valString);
          }
        } else if isRangeType(t) {
          const (startOffset, endOffset) = this.parser.expectEvent(EventType.Scalar, reader);
          reader.seek((startOffset:int)..);

          var alias = reader.withDeserializer(new DefaultDeserializer());
          return new t(reader=alias, deserializer=alias.deserializer);
        } else if canResolveTypeMethod(t, "deserializeFrom", reader, this) ||
                  isArrayType(t) {
          writeln("\t\t---new alias (C)---");
          var alias = reader.withDeserializer(new yamlDeserializer(this));
          const x = t.deserializeFrom(reader=alias, deserializer=alias.deserializer);
          writeln("\t\t---done with alias (C)---");
          return x;
        } else {
          writeln("\t\t---new alias (A)---");
          var alias = reader.withDeserializer(new yamlDeserializer(this));
          const x = new t(reader=alias, deserializer=alias.deserializer);
          writeln("\t\t---done with alias (A)---");
          return x;
        }
      }
    }

    // -------- composite --------

    proc startClass(reader: _readType, name: string, size: int) throws {
      writeln("\tstarting class: ", name, " size: ", size);
      this.context.enterClass();
      const typeName = this._startMapping(reader);
      if name != typeName && strictTypeParsing
        then throw new YamlTypeMismatchError(name, typeName);
    }

    proc endClass(reader: _readType) throws {
      writeln("\tendClass");
      this._endMapping(reader);
      this.context.leaveClass();
    }

    proc startRecord(reader: _readType, name: string, size: int) throws {
      writeln("\tstartRecord: ", name, " size: ", size);
      const typeName = this._startMapping(reader);
      if name != typeName && strictTypeParsing
        then throw new YamlTypeMismatchError(name, typeName);
    }

    proc endRecord(reader: _readType) throws {
      writeln("\tendRecord");
      this._endMapping(reader);
    }

    proc deserializeField(reader: _readType, key: string, type t): t throws {
      if key.size > 0 {
        const (keyStart, keyEnd) = this.parser.expectEvent(EventType.Scalar, reader);
        reader.seek((keyStart:int)..);
        const foundKey = reader.readString((keyEnd - keyStart):int);

        if foundKey != key then
          throw new YamlParserError("Field not found: '" + key + "' (found: '" + foundKey + "' instead)");
      }

      return this.deserialize(reader, t);
    }

    // -------- sequence --------

    proc startTuple(reader: _readType, size: int) throws {
      writeln("startTuple: ", size);
      this._startSequence(reader);
    }

    proc endTuple(reader: _readType) throws {
      writeln("endTuple");
      this._endSequence(reader);
    }

    proc startArray(reader: _readType) throws {
      writeln("startArray");
      this._startSequence(reader);
    }

    proc endArray(reader: _readType) throws {
      writeln("endArray");
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
      this.context.enter();
      // TODO: expect a scalar event first in case there is a type-tag or anchor
      const typeName = "";
      if !this.context.inSuperClass
        then this.parser.expectEvent(EventType.MappingStart, reader);
      return typeName;
    }

    proc _endMapping(reader: _readType) throws {
      this.context.leave();
      if !this.context.inSuperClass then this.parser.expectEvent(EventType.MappingEnd, reader);
    }

    proc _startSequence(reader: _readType) throws {
      this.context.enter();
      // TODO: expect a scalar event first in case there is a type-tag or anchor
      const typeName = "";
      const (startOffset, _) = this.parser.expectEvent(EventType.SequenceStart, reader);
      return typeName;
    }

    proc _endSequence(reader: _readType) throws {
      this.context.leave();
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

    private extern proc fclose(file: c_FILE): c_int;
    private extern proc fseek(file: c_FILE, offset: c_long, origin: c_int): c_int;
    private extern proc tmpfile(): c_FILE;
    private extern proc fread(ptr: c_ptr(c_uchar), size: c_size_t, nmemb: c_size_t, stream: c_FILE): c_size_t;
    private extern proc ftell(stream: c_FILE): c_long;
    private extern proc fflush(stream: c_FILE): c_int;
    private extern proc fgets(s: c_ptr(c_uchar), size: c_int, stream: c_FILE): c_ptr(c_uchar);
    extern const SEEK_SET: c_int;
    extern const SEEK_END: c_int;

    proc LibYamlEmitter.openContext() throws {
      c_memset(c_ptrTo(emitter):c_void_ptr, 0, c_sizeof(yaml_emitter_t));
      if !yaml_emitter_initialize(c_ptrTo(this.emitter))
        then throw new YamlEmitterError("Failed to initialize emitter");

      this.file = tmpfile();

      yaml_emitter_set_output_file(c_ptrTo(this.emitter), this.file);
      yaml_emitter_set_canonical(c_ptrTo(this.emitter), 0);
      yaml_emitter_set_unicode(c_ptrTo(this.emitter), 1);

      this._startOutputStream();
      this.beginDocument(false);
    }

    proc LibYamlEmitter.closeContext(): bytes throws {
      this.endDocument(false);
      this._endOutputStream();
      yaml_emitter_delete(c_ptrTo(this.emitter));

      fseek(this.file, 0, SEEK_END);
      var size = ftell(this.file);
      fseek(this.file, 0, SEEK_SET);

      var buf = c_malloc(uint(8), size+1);
      fread(buf, 1, size, this.file);
      buf[size] = 0;

      const b = createBytesWithNewBuffer(buf, size, size+1);
      c_free(buf);

      fclose(this.file);
      return b;
    }

    proc LibYamlEmitter.deinit() {
      yaml_event_delete(c_ptrTo(this.event));
    }

    proc LibYamlEmitter.serialize(fw, serializer) throws {
      fw.write("---LimYamlEmitter---");
    }

    // ----------------------------------------
    // serialization
    // ----------------------------------------

    proc LibYamlEmitter._startOutputStream() throws {
      if !yaml_stream_start_event_initialize(
        c_ptrTo(this.event),
        YAML_UTF8_ENCODING
      ) then throw new YamlEmitterError("Failed to initialize stream start event");

      this.emitEvent(errorMsg = "Failed to emit stream start event");
    }

    proc LibYamlEmitter._endOutputStream() throws {
      if !yaml_stream_end_event_initialize(c_ptrTo(this.event))
        then throw new YamlEmitterError("Failed to initialize stream end event");

      this.emitEvent(errorMsg = "Failed to emit stream end event");
    }

    proc LibYamlEmitter.beginSequence(ref tag: bytes = b"") throws {
      if !yaml_sequence_start_event_initialize(
        c_ptrTo(this.event),
        nil, // TODO: anchor support
        if tag.numBytes > 0 then c_ptrTo(tag) else nil,
        1,
        this.seqStyleC
      ) then throw new YamlEmitterError("Failed to initialize sequence start event");

      this.emitEvent(errorMsg = "Failed to emit sequence start event");
    }

    proc LibYamlEmitter.endSequence() throws {
      if !yaml_sequence_end_event_initialize(c_ptrTo(this.event))
        then throw new YamlEmitterError("Failed to initialize sequence end event");

      this.emitEvent(errorMsg = "Failed to emit sequence end event");
    }

    proc LibYamlEmitter.beginMapping(ref tag: bytes = b"") throws {
      writeln("\t\t\temitting mapping start event");
      if !yaml_mapping_start_event_initialize(
        c_ptrTo(this.event),
        nil, // TODO: anchor support
        if tag.numBytes > 0 then c_ptrTo(tag) else nil,
        (if tag.numBytes > 0 then 0 else 1): c_int,
        this.mapStyleC
      ) then throw new YamlEmitterError("Failed to initialize mapping start event");

      this.emitEvent(errorMsg = "Failed to emit mapping start event");
    }

    proc LibYamlEmitter.endMapping() throws {
      writeln("\t\t\temitting mapping end event");
      if !yaml_mapping_end_event_initialize(c_ptrTo(this.event))
        then throw new YamlEmitterError("Failed to initialize mapping end event");

      this.emitEvent(errorMsg = "Failed to emit mapping end event");
    }

    proc LibYamlEmitter.emitScalar(ref value: bytes, ref tag: bytes = b"") throws {
      writeln("\t\t\temitting scalar event: ", value);
      if !yaml_scalar_event_initialize(
        c_ptrTo(this.event),
        nil, // TODO: anchor support
        if tag.numBytes > 0 then c_ptrTo(tag) else nil,
        c_ptrTo(value),
        value.numBytes: c_int,
        (if tag.numBytes > 0 then 0 else 1): c_int,
        (if tag.numBytes > 0 then 0 else 1): c_int,
        this.sStyleC
      ) then throw new YamlEmitterError("Failed to initialize scalar event");

      this.emitEvent(errorMsg = "Failed to emit scalar event");
    }

    proc LibYamlEmitter.emitAlias(value: bytes) throws {
      if !yaml_alias_event_initialize(c_ptrTo(this.event), c_ptrTo(value))
        then throw new YamlEmitterError("Failed to initialize alias event");

      this.emitEvent(errorMsg = "Failed to emit alias event");
    }

    proc LibYamlEmitter.beginDocument(implicitStart: bool = true) throws {
      if !yaml_document_start_event_initialize(c_ptrTo(this.event), nil, nil, nil, implicitStart:c_int)
        then throw new YamlEmitterError("Failed to initialize document start event");

      this.emitEvent(errorMsg = "Failed to emit document start event");
    }

    proc LibYamlEmitter.endDocument(implicitEnd: bool = true) throws {
      if !yaml_document_end_event_initialize(c_ptrTo(this.event), implicitEnd:c_int)
        then throw new YamlEmitterError("Failed to initialize document end event");

      this.emitEvent(errorMsg = "Failed to emit document end event");
    }

    // ----------------------------------------
    // helpers
    // ----------------------------------------

    inline proc LibYamlEmitter.emitEvent(param errorMsg: string) throws {
      if !yaml_emitter_emit(c_ptrTo(this.emitter), c_ptrTo(this.event)) {
        select this.emitter.error {
          when YAML_MEMORY_ERROR do
            writef("Memory error: Not enough memory for emitting");
          when YAML_WRITER_ERROR do
            writef("Writer error: %s\n", this.emitter.problem.deref());
          when YAML_EMITTER_ERROR {
            writef("Emitter error: %s\n", this.emitter.problem.deref());
          }
          otherwise do
            writeln("Internal error");
        }
        throw new YamlEmitterError(errorMsg);
      }
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
    extern record yaml_emitter_t {
      var error: c_int;
      var problem: c_ptr(c_uchar);
    }
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

    extern const YAML_MEMORY_ERROR: c_int;
    extern const YAML_WRITER_ERROR: c_int;
    extern const YAML_EMITTER_ERROR: c_int;

    // emitter API
    private extern proc yaml_emitter_initialize(emitter: c_ptr(yaml_emitter_t)): c_int;
    private extern proc yaml_emitter_set_output_file(emitter: c_ptr(yaml_emitter_t), file: c_FILE): c_int;
    private extern proc yaml_emitter_set_canonical(emitter: c_ptr(yaml_emitter_t), isC: c_int);
    private extern proc yaml_emitter_set_unicode(emitter: c_ptr(yaml_emitter_t), isU: c_int);
    private extern proc yaml_emitter_emit(emitter: c_ptr(yaml_emitter_t), event: c_ptr(yaml_event_t)): c_int;
    private extern proc yaml_emitter_delete(emitter: c_ptr(yaml_emitter_t));
    private extern proc yaml_emitter_flush(emitter: c_ptr(yaml_emitter_t)): c_int;

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
    private use CTypes, IO;
    require "yaml.h", "-lyaml";

    // a chapel wrapper around the libyaml parser
    class LibYamlParser {
      @chpldoc.nodoc
      var parser: yaml_parser_t;
      @chpldoc.nodoc
      var event: yaml_event_t;

      @chpldoc.nodoc
      var fileIsInit = false;
      @chpldoc.nodoc
      var f: c_FILE;
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
      this.fileIsInit = false;
    }

    private extern proc fdopen(fd: int(32), mode: c_string): c_FILE;
    private extern proc fclose(file: c_FILE): c_int;
    private extern proc fseek(file: c_FILE, offset: c_long, origin: c_int): c_int;
    extern const SEEK_SET: c_int;

    proc LibYamlParser.prepDeserialization(fp: c_FILE, fr: fileReader) throws {
      // TODO: error handling for file not found
      this.f = fp;
      fseek(this.f, fr.offset(), SEEK_SET);
      writeln("Initializing with file offset: ", fr.offset());

      if !yaml_parser_initialize(c_ptrTo(this.parser)) then
        throw new YamlParserError("Failed to initialize YAML parser");

      yaml_parser_set_input_file(c_ptrTo(this.parser), this.f);
      this.fileIsInit = true;

      // parse stream start event
      if !yaml_parser_parse(c_ptrTo(this.parser), c_ptrTo(this.event)) then
        throw new YamlParserError("Failed to parse sequence start");
      if this.event.t != YAML_STREAM_START_EVENT then
        throw new YamlParserError("Expected stream start event");

      // parse document start event
      if !yaml_parser_parse(c_ptrTo(this.parser), c_ptrTo(this.event)) then
        throw new YamlParserError("Failed to parse document start");
      if this.event.t != YAML_DOCUMENT_START_EVENT then
        throw new YamlParserError("Expected document start event");
    }

    proc LibYamlParser.unprep() {
      this.fileIsInit = false;
      // yaml_parser_delete(c_ptrTo(this.parser));
      // yaml_event_delete(c_ptrTo(this.event));
    }

    proc LibYamlParser.deinit() {
      this.unprep();
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
        const (hasFp, fp) = fr._getFp();
        if !hasFp then
          throw new YamlParserError("Cannot parse from a memory file");
        this.prepDeserialization(fp, fr);
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
      writeln("\t\texpecting event: ", et);
      var (t, s, e) = this._parseNextEvent(fr);
      if t != et {
        // try to recover from an unexpected document start/end event
        if t == EventType.DocumentEnd || t == EventType.DocumentStart {
          writeln("\t\tWARNING: unexpected document start/end event???");
          return this.expectEvent(et, fr);
        } else {
          throw new YamlEventMismatchError(et, t);
        }
      }
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

    inline proc isStartingEventType(et: EventType): bool {
      select et {
        when EventType.StreamStart do return true;
        when EventType.DocumentStart do return true;
        when EventType.SequenceStart do return true;
        when EventType.MappingStart do return true;
        otherwise return false;
      }
    }

    // parser API
    private extern proc yaml_parser_initialize(parser: c_ptr(yaml_parser_t)): c_int;
    private extern proc yaml_parser_delete(parser: c_ptr(yaml_parser_t)): c_int;
    private extern proc yaml_parser_set_input_file(parser: c_ptr(yaml_parser_t), file: c_FILE): c_int;
    private extern proc yaml_parser_parse(parser: c_ptr(yaml_parser_t), event: c_ptr(yaml_event_t)): c_int;
    private extern proc yaml_event_delete(event: c_ptr(yaml_event_t));

    // ----------------------------------------
    // enums and errors
    // ----------------------------------------

    enum EventType {
      None,           // YAML_NO_EVENT
      StreamStart,    // YAML_STREAM_START_EVENT
      StreamEnd,      // YAML_STREAM_END_EVENT
      DocumentStart,  // YAML_DOCUMENT_START_EVENT
      DocumentEnd,    // YAML_DOCUMENT_END_EVENT
      Alias,          // YAML_ALIAS_EVENT
      Scalar,         // YAML_SCALAR_EVENT
      SequenceStart,  // YAML_SEQUENCE_START_EVENT
      SequenceEnd,    // YAML_SEQUENCE_END_EVENT
      MappingStart,   // YAML_MAPPING_START_EVENT
      MappingEnd      // YAML_MAPPING_END_EVENT
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
