
#include "add_one_helper.h"

int add_one(int x) {
    x = add_one_helper(x);
    return x + 1;
}
