package main

// #include <stdint.h>
import "C"

// Keep the supported Go signature explicit. Changes to this contract fail the build.
var _ func(int64, int64) int64 = add

//export zerox_go_add
func zerox_go_add(left, right C.int64_t) C.int64_t {
	return C.int64_t(add(int64(left), int64(right)))
}

func main() {}
