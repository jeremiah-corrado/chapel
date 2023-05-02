use IO, CTypes;
use YamlClassHierarchy;
require "yaml.h", "-lyaml";

extern record yaml_parser_t {
  var offset: c_size_t;
  var mark: yaml_mark_t;
};
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

private extern proc yaml_parser_initialize(parser: c_ptr(yaml_parser_t)): c_int;
private extern proc yaml_parser_delete(parser: c_ptr(yaml_parser_t)): c_int;
private extern proc yaml_parser_set_input_file(parser: c_ptr(yaml_parser_t), file: c_FILE): c_int;
private extern proc yaml_parser_parse(parser: c_ptr(yaml_parser_t), event: c_ptr(yaml_event_t)): c_int;
private extern proc yaml_event_delete(event: c_ptr(yaml_event_t));

private extern proc fopen(filename: c_string, mode: c_string): c_FILE;
private extern proc fclose(file: c_FILE): c_int;

proc parseYamlFile(filePath: string): [] owned YamlValue throws {
  var file = fopen(filePath.c_str(), "r".c_str()),
      fr = openReader(filePath, locking=false);

  var parser: yaml_parser_t;
  c_memset(c_ptrTo(parser):c_void_ptr, 0, c_sizeof(yaml_parser_t));

  if !yaml_parser_initialize(c_ptrTo(parser)) then
    throw new Error("Failed to initialize parser");
  yaml_parser_set_input_file(c_ptrTo(parser), file);

  var yvs = parseUntilEvent(YAML_STREAM_END_EVENT, parser, fr);

  yaml_parser_delete(c_ptrTo(parser));
  fclose(file);

  return yvs;
}

iter parseUntilEvent(e_stop: c_int, ref parser: yaml_parser_t, reader: fileReader): owned YamlValue {
  var event: yaml_event_t;
  c_memset(c_ptrTo(event):c_void_ptr, 0, c_sizeof(yaml_event_t));

  inline proc finish() do
    yaml_event_delete(c_ptrTo(event));

  while true {
    // parse until the next event
    if !yaml_parser_parse(c_ptrTo(parser), c_ptrTo(event)) then
        halt("Failed to parse next YAML event");

    // handle event
    select event.t {
      when YAML_STREAM_START_EVENT {
        for e in parseUntilEvent(YAML_STREAM_END_EVENT, parser, reader) do
          yield e;
      }
      when YAML_STREAM_END_EVENT {
        checkClosingEventMatch(e_stop, event.t);
        finish(); return;
      }
      when YAML_DOCUMENT_START_EVENT {
        for e in parseUntilEvent(YAML_DOCUMENT_END_EVENT, parser, reader) do
          yield e;
      }
      when YAML_DOCUMENT_END_EVENT {
        checkClosingEventMatch(e_stop, event.t);
        finish(); return;
      }
      when YAML_ALIAS_EVENT {
        reader.seek((event.start_mark.idx:int)..);
        yield new YamlAlias(reader.readString((event.end_mark.idx - event.start_mark.idx):int));
      }
      when YAML_SCALAR_EVENT {
        reader.seek((event.start_mark.idx:int)..);
        yield new YamlScalar(reader.readString((event.end_mark.idx - event.start_mark.idx):int));
      }
      when YAML_SEQUENCE_START_EVENT {
        var seq = new YamlSequence();
        for e in parseUntilEvent(YAML_SEQUENCE_END_EVENT, parser, reader) do
          seq._append(e);
        yield seq;
      }
      when YAML_SEQUENCE_END_EVENT {
        checkClosingEventMatch(e_stop, event.t);
        finish(); return;
      }
      when YAML_MAPPING_START_EVENT {
        var mapping = new YamlMapping(),
            nextKey = new owned YamlValue(),
            key = true;

        for e in parseUntilEvent(YAML_MAPPING_END_EVENT, parser, reader) {
          // TODO: is there a better way to do this without using unmanaged?
          // should this pattern be allowed for cpy:owned?
          var cpy: unmanaged YamlValue = owned.release(e);
          if key {
            nextKey = owned.adopt(cpy);
            key = false;
          } else {
            mapping._add(nextKey, owned.adopt(cpy));
            key = true;
          }
        }
        yield mapping;
      }
      when YAML_MAPPING_END_EVENT {
        checkClosingEventMatch(e_stop, event.t);
        finish(); return;
      }
      when YAML_NO_EVENT {
        finish(); return;
      }
      otherwise {
        yaml_event_delete(c_ptrTo(event));
        writeln("Unknown YAML event! ", event.t);
        finish(); return;
      }
    }
    yaml_event_delete(c_ptrTo(event));
  }
}

private proc checkClosingEventMatch(expected: c_int, actual: c_int) {
  if expected != actual {
    write("Mismatched closing event. Expected ");
    select expected {
      when YAML_STREAM_END_EVENT { write("YAML_STREAM_END_EVENT"); }
      when YAML_DOCUMENT_END_EVENT { write("YAML_DOCUMENT_END_EVENT"); }
      when YAML_SEQUENCE_END_EVENT { write("YAML_SEQUENCE_END_EVENT"); }
      when YAML_MAPPING_END_EVENT { write("YAML_MAPPING_END_EVENT"); }
    }
    write(" got ");
    select actual {
      when YAML_STREAM_END_EVENT { write("YAML_STREAM_END_EVENT"); }
      when YAML_DOCUMENT_END_EVENT { write("YAML_DOCUMENT_END_EVENT"); }
      when YAML_SEQUENCE_END_EVENT { write("YAML_SEQUENCE_END_EVENT"); }
      when YAML_MAPPING_END_EVENT { write("YAML_MAPPING_END_EVENT"); }
    }
    writeln();
  }
}
