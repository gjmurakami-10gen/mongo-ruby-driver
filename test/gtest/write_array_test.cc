#include <string>
#include <ostream>
#include <sstream>
#include <iomanip>
using namespace std;

#include "ruby.h"
#include "gtest/gtest.h"
#include "ruby/version.h"

struct bson_buffer {
    char* buffer;
    int size;
    int position;
    int max_size;
};

extern "C" {
    #include "bson_buffer.h"
};

#define SAFE_WRITE(buffer, data, size)                                  \
    if (bson_buffer_write((buffer), (data), (size)) != 0)                    \
        rb_raise(rb_eNoMemError, "failed to allocate memory in bson_buffer.c")

#define SAFE_WRITE_AT_POS(buffer, position, data, size)                 \
    if (bson_buffer_write_at_position((buffer), (position), (data), (size)) != 0) \
        rb_raise(rb_eRuntimeError, "invalid write at position in bson_buffer.c")

#define FREE_INTSTRING(buffer) free(buffer)
/*
#define INT2STRING(buffer, i)                   \
    {                                           \
        int vslength = snprintf(NULL, 0, "%d", i) + 1;  \
        cout << "vslength:" << vslength << endl; \
        *buffer = (char *)malloc(vslength);             \
        snprintf(*buffer, vslength, "%d", i);   \
    }
    */
#define INT2STRING(buffer, i) asprintf(buffer, "%d", i);

static char zero = 0;

extern "C" {
    int write_element_with_id(VALUE key, VALUE value, VALUE extra);
    VALUE pack_extra(bson_buffer_t buffer, VALUE check_keys);
    void write_name_and_type(bson_buffer_t buffer, VALUE name, char type);
};

string inspect(string s) {
    stringstream ss;
    ss.width(2);
    ss << "\"" << hex << setfill('0');
    for (unsigned int i = 0; i < s.length(); i++)
        ss << "\\x" << setw(2) << (int)s[i];
    ss << "\"";
    return ss.str();
}

string inspect(VALUE value) {
    stringstream ss;
    VALUE rbs = rb_inspect(value);
    ss << RSTRING_PTR(rbs);
    return ss.str();
}

string inspect(bson_buffer_t buffer) {
    stringstream ss;
    ss << "#<bson_buffer"
       << " size=" << buffer->size
       << " position:" << buffer->position
       << " buffer:" << inspect(string(buffer->buffer, buffer->position)) << ">";
    return ss.str();
}

int bson_buffer_eq(bson_buffer_t a, bson_buffer_t b) {
    return (a->position == b->position && strncmp(a->buffer, b->buffer, a->position) == 0);
}

int write_element_old(VALUE key, VALUE value, VALUE extra, int allow_id) {
    bson_buffer_t buffer = (bson_buffer_t)NUM2LL(rb_ary_entry(extra, 0));
    VALUE check_keys = rb_ary_entry(extra, 1);

    switch(TYPE(value)) {
    case T_ARRAY:
        {
            bson_buffer_position length_location, start_position, obj_length;
            int items, i;
            VALUE* values;

            write_name_and_type(buffer, key, 0x04);
            start_position = bson_buffer_get_position(buffer);

            // save space for length
            length_location = bson_buffer_save_space(buffer, 4);
            if (length_location == -1) {
                rb_raise(rb_eNoMemError, "failed to allocate memory in buffer.c");
            }

            items = RARRAY_LENINT(value);
            for(i = 0; i < items; i++) {
                char* name;
                VALUE key;
                INT2STRING(&name, i);
                key = rb_str_new2(name);
                write_element_with_id(key, rb_ary_entry(value, i), pack_extra(buffer, check_keys));
                FREE_INTSTRING(name);
            }

            // write null byte and fill in length
            SAFE_WRITE(buffer, &zero, 1);
            obj_length = bson_buffer_get_position(buffer) - start_position;
            SAFE_WRITE_AT_POS(buffer, length_location, (const char*)&obj_length, 4);
            break;
        }
    }
    return ST_CONTINUE;
}

#define ARRAY_KEY_BUFFER_SIZE 10
// use 8^(ARRAY_KEY_BUFFER_SIZE-1) as CPP safe bounds approximation for limit of 10^(ARRAY_KEY_BUFFER_SIZE-1)-1
#define ARRAY_KEY_MAX_CPP (1 << (3 * (ARRAY_KEY_BUFFER_SIZE-1)))

#ifdef _WIN32 || _MSC_VER
#define SNPRINTF _snprintf
#else
#define SNPRINTF snprintf
#endif

int write_element_new(VALUE key, VALUE value, VALUE extra, int allow_id) {
    bson_buffer_t buffer = (bson_buffer_t)NUM2LL(rb_ary_entry(extra, 0));
    VALUE check_keys = rb_ary_entry(extra, 1);

    switch(TYPE(value)) {
    case T_ARRAY:
        {
            bson_buffer_position length_location, start_position, obj_length;
            int items, i;
            VALUE* values;
            char name[ARRAY_KEY_BUFFER_SIZE];

            write_name_and_type(buffer, key, 0x04);
            start_position = bson_buffer_get_position(buffer);

            // save space for length
            length_location = bson_buffer_save_space(buffer, 4);
            if (length_location == -1) {
                rb_raise(rb_eNoMemError, "failed to allocate memory in buffer.c");
            }

            items = RARRAY_LENINT(value);
            if (items > ARRAY_KEY_MAX_CPP)
                rb_raise(rb_eRangeError, "array size too large");
            for(i = 0; i < items; i++) {
                VALUE key;
                SNPRINTF(name, ARRAY_KEY_BUFFER_SIZE, "%d", i);
                key = rb_str_new2(name);
                write_element_with_id(key, rb_ary_entry(value, i), pack_extra(buffer, check_keys));
            }
            // write null byte and fill in length
            SAFE_WRITE(buffer, &zero, 1);
            obj_length = bson_buffer_get_position(buffer) - start_position;
            SAFE_WRITE_AT_POS(buffer, length_location, (const char*)&obj_length, 4);
            break;
        }
    }
    return ST_CONTINUE;
}

namespace {

// The fixture for testing class Foo.
class WriteArrayTest : public ::testing::Test {
 protected:
  // You can remove any or all of the following functions if its body
  // is empty.

  WriteArrayTest() {
    // You can do set-up work for each test here.
  }

  virtual ~WriteArrayTest() {
    // You can do clean-up work that doesn't throw exceptions here.
  }

  // If the constructor and destructor are not enough for setting up
  // and cleaning up each test, you can define the following methods:

  virtual void SetUp() {
    // Code here will be called immediately after the constructor (right
    // before each test).
  }

  virtual void TearDown() {
    // Code here will be called immediately after each test (right
    // before the destructor).
  }

  // Objects declared here can be used by all tests in the test case for Foo.
};

string write_element_test(int (*fn)(VALUE key, VALUE value, VALUE extra, int allow_id), VALUE key, VALUE value) {
   bson_buffer_t buffer = bson_buffer_new();
   (*fn)(key, value, pack_extra(buffer, Qfalse), 0);
   string result(buffer->buffer, buffer->position);
   bson_buffer_free(buffer);
   return result;
};

TEST_F(WriteArrayTest, t_array) {
    VALUE key = rb_str_new2("a");
    VALUE value = rb_eval_string("[47, 74]");
    cout << inspect(value) << endl;

    string bson_old = write_element_test(write_element_old, key, value);
    string bson_new = write_element_test(write_element_new, key, value);

    cout << "buffer_old:" << inspect(bson_old) << endl;
    cout << "buffer_new:" << inspect(bson_new) << endl;
    //"\x04\x61\x00\x13\x00\x00\x00\x10\x30\x00\x2f\x00\x00\x00\x10\x31\x00\x4a\x00\x00\x00\x00"
    assert(bson_old == bson_new);
}

TEST_F(WriteArrayTest, rstring_embed_len_max) {
    cout << "RSTRING_EMBED_LEN_MAX:" << RSTRING_EMBED_LEN_MAX << endl;
}

}  // namespace

int main(int argc, char **argv) {
  ruby_init();
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
