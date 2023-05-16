use IO, CTypes;
use YamlClassHierarchy;
require "yaml.h", "-lyaml";

extern record yaml_event_t {
  extern "type" var t: c_int;
  var data: opaque;
  var start_mark: yaml_mark_t;
  var end_mark: yaml_mark_t;
};
extern record yaml_mark_t {
  extern "index" var idx: c_size_t;
  var line: c_size_t;
  var column: c_size_t;
};

extern record yaml_emitter_t {}

extern record yaml_version_directive_t {
  var major: c_int;
  var minor: c_int;
};
extern record yaml_tag_directive_t {
  var handle: c_ptr(c_uchar);
  var prefix: c_ptr(c_uchar);
};
extern record yaml_char_t {}

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

private extern proc yaml_emitter_initialize(emitter: c_ptr(yaml_emitter_t)): c_int;
private extern proc yaml_emitter_set_output_file(emitter: c_ptr(yaml_emitter_t), file: c_FILE): c_int;
private extern proc yaml_emitter_set_canonical(emitter: c_ptr(yaml_emitter_t), isC: c_int);
private extern proc yaml_emitter_set_unicode(emitter: c_ptr(yaml_emitter_t), isU: c_int);
private extern proc yaml_emitter_emit(emitter: c_ptr(yaml_emitter_t), event: c_ptr(yaml_event_t)): c_int;
private extern proc yaml_emitter_delete(emitter: c_ptr(yaml_emitter_t));

private extern proc yaml_stream_start_event_initialize(event: c_ptr(yaml_event_t), encoding: c_int): c_int;
private extern proc yaml_document_start_event_initialize(
                      event: c_ptr(yaml_event_t),
                      version: c_ptr(yaml_version_directive_t),
                      start: c_ptr(yaml_tag_directive_t),
                      end: c_ptr(yaml_tag_directive_t),
                      implicit: c_int
                    ): c_int;
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
private extern proc yaml_event_delete(event: c_ptr(yaml_event_t));
private extern proc yaml_document_end_event_initialize(event: c_ptr(yaml_event_t), implicit: c_int): c_int;
private extern proc yaml_stream_end_event_initialize(event: c_ptr(yaml_event_t)): c_int;

private extern proc fopen(filename: c_string, mode: c_string): c_FILE;
private extern proc fclose(file: c_FILE): c_int;

proc writeYamlFile(path: string, documents: [] owned YamlValue) throws {
  var f = fopen(path.c_str(), c"w");

  var emitter: yaml_emitter_t,
      event: yaml_event_t;

  c_memset(c_ptrTo(emitter):c_void_ptr, 0, c_sizeof(yaml_emitter_t));
  c_memset(c_ptrTo(event):c_void_ptr, 0, c_sizeof(yaml_event_t));

  yaml_emitter_initialize(c_ptrTo(emitter));
  yaml_emitter_set_output_file(c_ptrTo(emitter), f);
  yaml_emitter_set_canonical(c_ptrTo(emitter), 0);
  yaml_emitter_set_unicode(c_ptrTo(emitter), 1);

  // start stream
  if !yaml_stream_start_event_initialize(c_ptrTo(event), YAML_UTF8_ENCODING)
    then throw new Error("failed to initialize stream start event");
  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit stream start event");

  for document in documents {
    try {
      emitYamlDocument(emitter, event, document);
    } catch e {
      yaml_event_delete(c_ptrTo(event));
      yaml_emitter_delete(c_ptrTo(emitter));
      fclose(f);
      throw e;
    }
  }

  // end stream
  if !yaml_stream_end_event_initialize(c_ptrTo(event))
    then throw new Error("failed to initialize stream end event");
  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit stream end event");

  yaml_event_delete(c_ptrTo(event));
  yaml_emitter_delete(c_ptrTo(emitter));

  fclose(f);
}

proc emitYamlDocument(ref emitter: yaml_emitter_t, ref event: yaml_event_t, v: borrowed YamlValue) throws {
  // start document
  if !yaml_document_start_event_initialize(c_ptrTo(event), nil, nil, nil, 0)
    then throw new Error("failed to initialize document start event");
  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit document start event");

  // emit the yaml value
  emitYamlValue(emitter, event, v);

  // end document
  if !yaml_document_end_event_initialize(c_ptrTo(event), 0)
    then throw new Error("failed to initialize document end event");
  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit document end event");
}

proc emitYamlValue(ref emitter: yaml_emitter_t, ref event: yaml_event_t, v: borrowed YamlValue) throws {
  select v.valueType() {
    when YamlValueType.Null do writeln("~");
    when YamlValueType.Scalar do emitYamlScalar(emitter, event, v: borrowed YamlScalar);
    when YamlValueType.Sequence do emitYamlSequence(emitter, event, v: borrowed YamlSequence);
    when YamlValueType.Mapping do emitYamlMapping(emitter, event, v: borrowed YamlMapping);
    when YamlValueType.Alias do emitYamlAlias(emitter, event, v: borrowed YamlAlias);
    otherwise throw new Error("unknown yaml value type");
  }
}

proc emitYamlScalar(ref emitter: yaml_emitter_t, ref event: yaml_event_t, v: borrowed YamlScalar) throws {
  const (c_val, len) = v.getCValue();
  var t = v.tag[0..];
  var tag: c_ptr(c_uchar) = if t == "" then nil else c_ptrTo(t);

  if !yaml_scalar_event_initialize(
        c_ptrTo(event),
        nil,
        tag,
        c_val,
        len,
        (if t.size > 0 then 0 else 1):c_int,
        (if t.size > 0 then 0 else 1):c_int,
        YAML_ANY_SCALAR_STYLE
      )
    then throw new Error("failed to initialize scalar event");

  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit scalar event");
}

proc emitYamlMapping(ref emitter: yaml_emitter_t, ref event: yaml_event_t, v: borrowed YamlMapping) throws {
  if !yaml_mapping_start_event_initialize(
        c_ptrTo(event),
        nil,
        nil,
        1,
        YAML_ANY_MAPPING_STYLE
      )
    then throw new Error("failed to initialize mapping start event");

  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit mapping start event");

  for (k, v) in v {
    emitYamlValue(emitter, event, k);
    emitYamlValue(emitter, event, v);
  }

  if !yaml_mapping_end_event_initialize(c_ptrTo(event))
    then throw new Error("failed to initialize mapping end event");

  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit mapping end event");
}

proc emitYamlSequence(ref emitter: yaml_emitter_t, ref event: yaml_event_t, v: borrowed YamlSequence) throws {
  if !yaml_sequence_start_event_initialize(
        c_ptrTo(event),
        nil,
        nil,
        1,
        YAML_ANY_SEQUENCE_STYLE
      )
    then throw new Error("failed to initialize sequence start event");

  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit sequence start event");

  for e in v {
    emitYamlValue(emitter, event, e);
  }

  if !yaml_sequence_end_event_initialize(c_ptrTo(event))
    then throw new Error("failed to initialize sequence end event");

  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit sequence end event");
}

proc emitYamlAlias(ref emitter: yaml_emitter_t, ref event: yaml_event_t, v: borrowed YamlAlias) throws {
  if !yaml_alias_event_initialize(c_ptrTo(event), v.getCValue())
    then throw new Error("failed to initialize alias event");

  if !yaml_emitter_emit(c_ptrTo(emitter), c_ptrTo(event))
    then throw new Error("failed to emit alias event");
}

proc main() {
  var docs : [1..1] owned YamlValue = [(new YamlScalar("hello world"):YamlValue),];
  writeYamlFile("test_single.yaml", docs);
}
