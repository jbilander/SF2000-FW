typedef enum {
  OP_NONE,
  OP_PROGRAM,
  OP_VERIFY,
  OP_ERASE_BANK,
  OP_ERASE_CHIP,
  OP_IDENTIFY
} operation_type;

typedef enum {
  SOURCE_NONE,
  SOURCE_FILE,
  SOURCE_ROM
} source_type;

struct Config {
  ULONG          programBank;
  operation_type op;
  source_type    source;
  bool           skipVerify;
  char           *ks_filename;
};

struct Config* configure(int, char* []);