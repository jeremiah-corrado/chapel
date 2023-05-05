module Yaml {
  private use IO;

  public import this.SerializerHelp.SequenceStyle,
                this.SerializerHelp.MappingStyle,
                this.SerializerHelp.ScalarStyle;

  private import this.SerializerHelp.LibYamlEmitter,
                 this.DeserializerHelp.libYamlParser;

  private import this.SerializerHelp.YamlEmitterError,
                 this.DeserializerHelp.YamlParserError,
                 this.DeserializerHelp.EventType;

  record yamlSerializer {
    var emitter: unmanaged LibYamlEmitter;
    var contextLevel: int = 0;
    var contextStartOffset: int = 0;

    proc init(
      seqStyle: SequenceStyle = SequenceStyle.Any,
      mapStyle: MappingStyle = MappingStyle.Any,
      scalarStyle: ScalarStyle = ScalarStyle.Any
    ) {
      this.emitter = new unmanaged LibYamlEmitter(seqStyle, mapStyle, scalarStyle);
    }

    proc init(
      emitter: unmanaged LibYamlEmitter,
      contextLevel,
      contextStartOffset = 0
    ) {
      this.emitter = emitter;
      this.contextLevel = contextLevel;
      this.contextStartOffset = contextStartOffset;
    }

    proc deinit() {
      delete this.emitter;
    }

    proc serialize(writer: fileWriter, const val: ?t): void throws {
      var startOffset, endOffset = 0;
      import Reflection.canResolve;

      if canResolve(":", val, bytes) {
        const valBytes = val: bytes;
        (startOffset, endOffset) = this.emitter.emit(valBytes);
      } else if isClassType(t) {
        if val == nil {
          (startOffset, endOffset) = this.emitter.emit("~");
        } else {
          val!.serialize(writer, new yamlSerializer(this.emitter, this.contextLevel + 1));
        }
      } else {
        val.serialize(writer, new yamlSerializer(this.emitter, this.contextLevel + 1));
      }

      if contextLevel == 0 && endOffset > 0 {
        writer.writeBytes(this.emitter.extractBytes(startOffset..endOffset));
        this.contextStartOffset = endOffset;
      }
    }

    proc startType(writer: fileWriter, type t, size: int = -1) throws {
      const startOffset = this.emitter.beginMapping();
      if contextLevel == 0 then this.contextStartOffset = startOffset;
      contextLevel += 1;
    }

    proc endType(writer: fileWriter, type t) throws {
      const endOffset = this.emitter.endMapping();
      contextLevel -= 1;
      if contextLevel == 0 {
        writer.writeBytes(this.emitter.extractBytes(this.contextStartOffset..endOffset));
        this.contextStartOffset = endOffset;
      }
    }

    proc serializeField(writer: fileWriter, name: string, const val: ?t) throws {
      this.emitter.emitScalar(name);
      this.serialize(writer, val);
    }

    proc startArray(writer: fileWriter, size: uint = 0) throws {
      const startOffset = this.emitter.beginSequence();
      if contextLevel == 0 then this.contextStartOffset = startOffset;
      contextLevel += 1;
    }

    proc endArray(writer: fileWriter) throws {
      const endOffset = this.emitter.endSequence();
      contextLevel -= 1;
      if contextLevel == 0 {
        writer.writeBytes(this.emitter.extractBytes(this.contextStartOffset..endOffset));
        this.contextStartOffset = endOffset;
      }
    }

    proc serializeElement(writer: fileWriter, const idx: ?, const elt: ?t) throws {
      this.serialize(writer, elt);
    }
  }

  record yamlDeserializer {
    var parser: libYamlParser;

    proc init() {
      this.parser = new libYamlParser();
    }

    proc deserialize(reader: fileReader, type readType) : readType throws {

    }
  }

  // testing
  proc main() {
    var s = try! new yamlSerializer();
    var d = try! new yamlDeserializer();
  }

  private module SerializerHelp {
    private use CTypes;
    require "yaml.h", "-lyaml";

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
      this.file = opentmp();
      if this.file == nil then
        throw new YamlEmitterError("Failed to open temporary file");

      if !yaml_emitter_initialize(this.emitterPtr)
        then throw new YamlEmitterError("Failed to initialize emitter");

      yaml_emitter_set_output_file(this.emitterPtr, this.file);
      yaml_emitter_set_canonical(this.emitterPtr, 0);
      yaml_emitter_set_unicode(this.emitterPtr, 1);
    }

    proc LibYamlEmitter.extractBytes(r: range): bytes {
      fseek(this.file, r.low, SEEK_SET);
      var buf = c_malloc(uint(8), r.size);
      fread(buf, 1, r.size, this.file);

      const b = createBytesWithOwnedBuffer(buf, r.size, r.size);
      c_free(buf);

      return b;
    }

    proc LibYamlEmitter.deinit() {
      // TODO: fix this after:  https://github.com/chapel-lang/chapel/issues/22073
      // if this.file != nil then
        fclose(this.file);
      yaml_emitter_delete(this.emitterPtr);
      yaml_event_delete(this.eventPtr);
    }

    // ----------------------------------------
    // serialization
    // ----------------------------------------

    proc LibYamlEmitter._startOutputStream() throws {
      if !yaml_stream_start_event_initialize(
        this.eventPtr,
        YAML_UTF8_ENCODING
      ) then throw new YamlEmitterError("Failed to initialize stream start event");

      this.emitEvent(errorMsg = "Failed to emit stream start event");
    }

    proc LibYamlEmitter._endOutputStream() throws {
      if !yaml_stream_end_event_initialize(this.eventPtr)
        then throw new YamlEmitterError("Failed to initialize stream end event");

      this.emitEvent(errorMsg = "Failed to emit stream end event");
    }

    proc LibYamlEmitter.beginSequence(): int throws {
      if !yaml_sequence_start_event_initialize(
        this.eventPtr,
        nil, // TODO: anchor support
        nil, // TODO: tag support
        1,
        this.seqStyleC
      ) then throw new YamlEmitterError("Failed to initialize sequence start event");

      return this.emitEvent(errorMsg = "Failed to emit sequence start event")[0];
    }

    proc LibYamlEmitter.endSequence(): int throws {
      if !yaml_sequence_end_event_initialize(this.eventPtr)
        then throw new YamlEmitterError("Failed to initialize sequence end event");

      return this.emitEvent(errorMsg = "Failed to emit sequence end event")[1];
    }

    proc LibYamlEmitter.beginMapping(): int throws {
      if !yaml_mapping_start_event_initialize(
        this.eventPtr,
        nil, // TODO: anchor support
        nil, // TODO: tag support
        1,
        this.mapStyleC
      ) then throw new YamlEmitterError("Failed to initialize mapping start event");

      return this.emitEvent(errorMsg = "Failed to emit mapping start event")[0];
    }

    proc LibYamlEmitter.endMapping(): int throws {
      if !yaml_mapping_end_event_initialize(this.eventPtr)
        then throw new YamlEmitterError("Failed to initialize mapping end event");

      return this.emitEvent(errorMsg = "Failed to emit mapping end event")[1];
    }

    proc LibYamlEmitter.emitScalar(value: bytes, tag: bytes = b""): 2*int throws {
      if !yaml_scalar_event_initialize(
        this.eventPtr,
        nil, // TODO: anchor support
        if tag.size > 0 then c_ptrTo(tag) else nil,
        c_ptrTo(value),
        value.size,
        (if tag.size > 0 then 0 else 1):c_int,
        (if tag.size > 0 then 0 else 1):c_int,
        this.sStyleC
      ) then throw new YamlEmitterError("Failed to initialize scalar event");

      return this.emitEvent(errorMsg = "Failed to emit scalar event");
    }

    proc LibYamlEmitter.emitAlias(value: bytes): 2*int throws {
      if !yaml_alias_event_initialize(this.eventPtr, c_ptrTo(value))
        then throw new YamlEmitterError("Failed to initialize alias event");

      return this.emitEvent(errorMsg = "Failed to emit alias event");
    }

    proc LibYamlEmitter.startDocument(implicitStart: bool = true): int throws {
      if !yaml_document_start_event_initialize(this.eventPtr, nil, nil, nil, implicitStart:c_int)
        then throw new YamlEmitterError("Failed to initialize document start event");

      return this.emitEvent(errorMsg = "Failed to emit document start event")[0];
    }

    proc LibYamlEmitter.endDocument(implicitEnd: bool = true): int throws {
      if !yaml_document_end_event_initialize(this.eventPtr, implicitEnd:c_int)
        then throw new YamlEmitterError("Failed to initialize document end event");

      return this.emitEvent(errorMsg = "Failed to emit document end event")[1];
    }

    // ----------------------------------------
    // helpers
    // ----------------------------------------

    proc LibYamlEmitter.emitEvent(param errorMsg: string): int throws {
      if !yaml_emitter_emit(this.emitterPtr, this.eventPtr)
        then throw new YamlEmitterError(errorMsg);

      return (this.event.start_mark.idx, this.event.end_mark.idx);
    }

    proc LibYamlEmitter.emitterPtr: c_ptr(yaml_emitter_t) {
      return c_ptrTo(this.emitter);
    }

    proc LibYamlEmitter.eventPtr: c_ptr(yaml_event_t) {
      return c_ptrTo(this.event);
    }

    proc LibYamlEmitter.seqStyleC: c_int {
      select this.seqStyle {
        when SequenceStyle.Any do return YAML_ANY_SEQUENCE_STYLE;
        when SequenceStyle.Block do return YAML_BLOCK_SEQUENCE_STYLE;
        when SequenceStyle.Flow do return YAML_FLOW_SEQUENCE_STYLE;
      }
    }

    proc LibYamlEmitter.mapStyleC: c_int {
      select this.mapStyle {
        when MappingStyle.Any do return YAML_ANY_MAPPING_STYLE;
        when MappingStyle.Block do return YAML_BLOCK_MAPPING_STYLE;
        when MappingStyle.Flow do return YAML_FLOW_MAPPING_STYLE;
      }
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
    }

    // ----------------------------------------
    // libyaml C API
    // ----------------------------------------

    // relevant types
    extern record yaml_emitter_t {}
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

    record libYamlParser {
      var parser: yaml_parser_t;
      var event: yaml_event_t;
      var file: c_ptr(c_FILE) = c_nil;
    }

    // ----------------------------------------
    // initialization
    // ----------------------------------------

    proc libYamlParser.init() {
      var p: yaml_parser_t;
      var e: yaml_event_t;
      c_memset(c_ptrTo(p):c_void_ptr, 0, c_sizeof(yaml_parser_t));
      c_memset(c_ptrTo(e):c_void_ptr, 0, c_sizeof(yaml_event_t));
      this.parser = p;
      this.event = e;
    }

    // give the parser a file to read from
    proc libYamlParser.attachFile(path: string) throws {
      var f = fopen(path, c"r");
      if f == nil then
        throw new YamlParserError("Failed to open file for reading");
      this.file = c_ptrTo(f);
      this._parserInit();
      yaml_parser_set_input_file(this.parserPtr, f);
    }

    // give the parser a file to read from, starting from some offset
    proc libYamlParser.attachFileAt(path: string, offset: int) throws {
      var f = fopen(path, c"r");
      if f == nil then
        throw new YamlParserError("Failed to open file for reading");
      fseek(f, offset, SEEK_SET);
      this.file = c_ptrTo(f);
      this._parserInit();
      yaml_parser_set_input_file(this.emitterPtr, f);
    }

    proc libYamlParser._parserInit() throws {
      if !yaml_parser_initialize(this.parserPtr) then
        throw new YamlParserError("Failed to initialize YAML parser");
    }

    proc libYamlParser.deinit() {
      if this.file != nil then
        fclose(this.file.deref());
      yaml_parser_delete(this.parserPtr);
      yaml_event_delete(this.eventPtr);
    }

    // ----------------------------------------
    // parsing
    // ----------------------------------------

    proc libYamlParser.parseNextEvent(): (EventType, int, int) throws {
      if !yaml_parser_parse(this.parserPtr, this.eventPtr) then
        throw new YamlParserError("Failed to parse YAML event");

      return (
        parseEventType(event.t),
        this.event.start_mark.idx,
        this.event.end_mark.idx
      );
    }

    // ----------------------------------------
    // helpers
    // ----------------------------------------

    proc libYamlParser.parserPtr: c_ptr(yaml_parser_t) {
      return c_ptrTo(this.parser);
    }

    proc libYamlParser.eventPtr: c_ptr(yaml_event_t) {
      return c_ptrTo(this.event);
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
  }
}
