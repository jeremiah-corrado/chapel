module Yaml {
  private use IO;

  public import this.SerializerHelp.SequenceStyle,
                this.SerializerHelp.MappingStyle,
                this.SerializerHelp.ScalarStyle;

  private import this.SerializerHelp.libYamlEmitter,
                 this.DeserializerHelp.libYamlParser;

  record YamlSerializer {
    var emitter: libYamlEmitter;

    proc init() throws {
      this.complete();
      this.emitter = new libYamlEmitter();
    }

    proc serialize(writer: fileWriter, const val: ?t) : void throws {

    }
  }

  record YamlDeserializer {
    var parser: libYamlParser;

    proc init() throws {
      this.complete();
      this.parser = new libYamlParser();
    }

    proc deserialize(reader: fileReader, type readType) : readType throws {

    }
  }

  // testing
  proc main() {
    var s = try! new YamlSerializer();
    var d = try! new YamlDeserializer();
  }

  private module SerializerHelp {
    private use CTypes;
    require "yaml.h", "-lyaml";

    record libYamlEmitter {
      var SeqStyle: SequenceStyle;
      var MapStyle: MappingStyle;
      var SStyle: ScalarStyle;

      var emitter: yaml_emitter_t;
      var file: c_ptr(c_FILE) = c_nil;
    }

    proc libYamlEmitter.init(
      sequences = SequenceStyle.Any,
      mappings = MappingStyle.Any,
      scalars = ScalarStyle.Any
    ) throws {
      this.SeqStyle = sequences;
      this.MapStyle = mappings;
      this.SStyle = scalars;

      var e: yaml_emitter_t;
      c_memset(c_ptrTo(e):c_void_ptr, 0, c_sizeof(yaml_emitter_t));
      this.emitter = e;

      this.complete();
      this._emitterInit();
    }

    proc libYamlEmitter._emitterInit() throws {
      if !yaml_emitter_initialize(this.emitterPtr)
        then throw new YamlEmitterError("Failed to initialize emitter");

      yaml_emitter_set_canonical(this.emitterPtr, 0);
      yaml_emitter_set_unicode(this.emitterPtr, 1);
    }

    proc libYamlEmitter.deinit() {
      if this.file != nil then
        fclose(this.file.deref());
      yaml_emitter_delete(this.emitterPtr);
    }

    proc libYamlEmitter.emitterPtr: c_ptr(yaml_emitter_t) {
      return c_ptrTo(this.emitter);
    }

    // ----------------------------------------
    // libyaml C API
    // ----------------------------------------

    // relevant types
    extern record yaml_emitter_t {}
    extern record yaml_event_t {}
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
      var file: c_ptr(c_FILE) = c_nil;

      /*
        this is the YAML context level at which the parser was created
        it is used to determine the cleanup that needs to occur when the
        parser is deleted

        For example, if it is ContextLevel.stream, then the stream needs
        to be closed, and the file needs to be closed when the parser
        is deinitialized
      */
      var startingContextLevel = ContextLevel.Stream;
    }

    proc libYamlParser.init() throws {
      var p: yaml_parser_t;
      c_memset(c_ptrTo(p):c_void_ptr, 0, c_sizeof(yaml_parser_t));
      this.parser = p;

      this.complete();
      this._parserInit();
    }

    // proc libYamlParser._fileInit(filePath: string) throws {
    //   var f = fopen(filePath, c"r");
    //   if f == nil then
    //     throw new YamlParserError("Failed to open file: ", filePath);
    //   this.file = f;
    // }

    proc libYamlParser._parserInit() throws {
      if !yaml_parser_initialize(this.parserPtr) then
        throw new YamlParserError("Failed to initialize YAML parser");
    }

    proc libYamlParser.deinit() {
      if this.file != nil then
        fclose(this.file.deref());
      yaml_parser_delete(this.parserPtr);
    }

    proc libYamlParser.parserPtr: c_ptr(yaml_parser_t) {
      return c_ptrTo(this.parser);
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

    // parser API
    private extern proc yaml_parser_initialize(parser: c_ptr(yaml_parser_t)): c_int;
    private extern proc yaml_parser_delete(parser: c_ptr(yaml_parser_t)): c_int;
    private extern proc yaml_parser_set_input_file(parser: c_ptr(yaml_parser_t), file: c_FILE): c_int;
    private extern proc yaml_parser_parse(parser: c_ptr(yaml_parser_t), event: c_ptr(yaml_event_t)): c_int;
    private extern proc yaml_event_delete(event: c_ptr(yaml_event_t));

    private extern proc fopen(filename: c_string, mode: c_string): c_FILE;
    private extern proc fclose(file: c_FILE): c_int;

    // ----------------------------------------

    enum ContextLevel {
      Stream,
      Document,
      Sequence,
      Mapping,
      Scalar,
      Unknown
    }

    class YamlParserError: Error {}

    proc YamlParserError.init(msg: string) {
      super.init(msg);
    }
  }
}
