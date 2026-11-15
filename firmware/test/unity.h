// Minimal stand-in for the Unity test framework: just the macros the SEM-1
// tests use, so the tests build with a plain C++ compiler and nothing else.
#pragma once
#include <math.h>
#include <setjmp.h>
#include <stdio.h>

namespace mini_unity {
inline int& failures() { static int n = 0; return n; }
inline int& tests() { static int n = 0; return n; }
inline jmp_buf& jump() { static jmp_buf j; return j; }
inline void fail(const char* file, int line, const char* what) {
  printf("%s:%d: FAIL: %s\n", file, line, what);
  longjmp(jump(), 1);
}
}  // namespace mini_unity

void setUp();
void tearDown();

#define MU_CHECK(cond, what) \
  do { if (!(cond)) mini_unity::fail(__FILE__, __LINE__, what); } while (0)

#define TEST_ASSERT_TRUE(c) MU_CHECK((c), #c " is not true")
#define TEST_ASSERT_FALSE(c) MU_CHECK(!(c), #c " is not false")
#define TEST_ASSERT_EQUAL(e, a) MU_CHECK((long long)(e) == (long long)(a), #a " != " #e)
#define TEST_ASSERT_EQUAL_UINT8(e, a) TEST_ASSERT_EQUAL(e, a)
#define TEST_ASSERT_EQUAL_UINT16(e, a) TEST_ASSERT_EQUAL(e, a)
#define TEST_ASSERT_EQUAL_UINT32(e, a) TEST_ASSERT_EQUAL(e, a)
#define TEST_ASSERT_NOT_EQUAL(e, a) MU_CHECK((long long)(e) != (long long)(a), #a " == " #e)
#define TEST_ASSERT_EQUAL_FLOAT(e, a) MU_CHECK(fabs((double)(e) - (double)(a)) < 1e-6, #a " != " #e)
#define TEST_ASSERT_FLOAT_WITHIN(d, e, a) \
  MU_CHECK(fabs((double)(e) - (double)(a)) <= (double)(d), #a " not within " #d " of " #e)
#define TEST_ASSERT_UINT32_WITHIN(d, e, a) TEST_ASSERT_FLOAT_WITHIN(d, e, a)

#define UNITY_BEGIN() (mini_unity::failures() = 0, mini_unity::tests() = 0)
#define RUN_TEST(fn)                                     \
  do {                                                   \
    mini_unity::tests()++;                               \
    if (setjmp(mini_unity::jump()) == 0) {               \
      setUp();                                           \
      fn();                                              \
      tearDown();                                        \
      printf("%-50s PASS\n", #fn);                       \
    } else {                                             \
      mini_unity::failures()++;                          \
    }                                                    \
  } while (0)
#define UNITY_END()                                                               \
  (printf("\n%d tests, %d failures: %s\n", mini_unity::tests(), mini_unity::failures(), \
          mini_unity::failures() ? "FAIL" : "OK"),                                \
   mini_unity::failures() ? 1 : 0)
