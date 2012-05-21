#include "ruby.h"
#include "ruby/version.h"
#include "gtest/gtest.h"

#define BSON_UTC_DATETIME_2099_01_01 "\x00\xAC\x12\xD5\xB3\x03\x00\x00\x00"

namespace {

// The fixture for testing class Foo.
class LargeDateTest : public ::testing::Test {
 protected:
  // You can remove any or all of the following functions if its body
  // is empty.

  LargeDateTest() {
    // You can do set-up work for each test here.
  }

  virtual ~LargeDateTest() {
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

// > BSON.serialize(t: DateTime.parse('2099-01-01T00:00:00Z').to_time).to_s
// => "\x10\x00\x00\x00\tt\x00\x00\xAC\x12\xD5\xB3\x03\x00\x00\x00"
// note that "\t" == "\x09"
// > BSON.serialize(t: DateTime.parse('2099-01-01T00:00:00Z').to_time).to_s[7..15]
// => "\x00\xAC\x12\xD5\xB3\x03\x00\x00\x00"

TEST_F(LargeDateTest, Ruby_1_8) {
    static ID utc_method = rb_intern("utc");
    const char* buffer = BSON_UTC_DATETIME_2099_01_01;
    int iposition = 0;
    int* position = &iposition;
    VALUE value;
    //case 9:
        {
            int64_t millis;
            memcpy(&millis, buffer + *position, 8);

            value = rb_time_new(millis / 1000, (millis % 1000) * 1000);
            value = rb_funcall(value, utc_method, 0);
            *position += 8;
            //break;
        }
    VALUE rbs = rb_inspect(value);
    printf("inspect: %s\n", RSTRING_PTR(rbs));
    ASSERT_STREQ("2099-01-01 00:00:00 UTC", RSTRING_PTR(rbs));
}

TEST_F(LargeDateTest, Ruby_1_9) {
    printf("RUBY_API_VERSION_CODE: %d\n", RUBY_API_VERSION_CODE);
    static ID utc_method = rb_intern("utc");
    const char* buffer = BSON_UTC_DATETIME_2099_01_01;
    int iposition = 0;
    int* position = &iposition;
    VALUE value;
    //case 9:
        {
            int64_t millis;
            memcpy(&millis, buffer + *position, 8);
            #if RUBY_API_VERSION_CODE >= 10900
            #define add(x,y) (rb_funcall((x), '+', 1, (y)))
            #define mul(x,y) (rb_funcall((x), '*', 1, (y)))
            #define quo(x,y) (rb_funcall((x), rb_intern("quo"), 1, (y)))
            VALUE d, timev;
            d = ULL2NUM(1000ULL);
            timev = add(LL2NUM(millis / 1000), quo(LL2NUM(millis % 1000), d));
            //VALUE now = time_s_now(Qnil);
            //VALUE offset = rb_funcall(now, rb_intern("utc_offset"), 0);
            value = rb_time_num_new(timev, Qnil);
            //printf("DIAG: %d %d\n", ((struct time_obj*)value)->gmt, ((struct time_obj*)value)->tm_got);
            #else
            value = rb_time_new(millis / 1000, (millis % 1000) * 1000);
            #endif
            value = rb_funcall(value, utc_method, 0);
            *position += 8;
            //break;
        }
    VALUE rbs = rb_inspect(value);
    printf("inspect: %s\n", RSTRING_PTR(rbs));
    ASSERT_STREQ("2099-01-01 00:00:00 UTC", RSTRING_PTR(rbs));
}

extern "C" {
    VALUE get_value(const char* buffer, int* position, int type);
    void Init_cbson();
};

/*
TEST_F(LargeDateTest, GetValue) {
    printf("RUBY_API_VERSION_CODE: %d\n", RUBY_API_VERSION_CODE);
    //static ID init = rb_intern("Init_cbson");
    //rb_funcall(0, init, 0);
    Init_cbson();
    const char* buffer = BSON_UTC_DATETIME_2099_01_01;
    int iposition = 0;
    int* position = &iposition;
    int type = 9;
    VALUE value = get_value(buffer, position, type);
    VALUE rbs = rb_inspect(value);
    printf("inspect: %s\n", RSTRING_PTR(rbs));
    ASSERT_STREQ("2099-01-01 00:00:00 UTC", RSTRING_PTR(rbs));
}
*/

}  // namespace

int main(int argc, char **argv) {
  ruby_init();
  ::testing::InitGoogleTest(&argc, argv);
  return RUN_ALL_TESTS();
}
