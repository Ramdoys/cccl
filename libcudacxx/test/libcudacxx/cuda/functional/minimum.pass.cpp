//===----------------------------------------------------------------------===//
//
// Part of libcu++, the C++ Standard Library for your entire system,
// under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
// SPDX-FileCopyrightText: Copyright (c) 2024 NVIDIA CORPORATION & AFFILIATES.
//
//===----------------------------------------------------------------------===//

#include <cuda/functional>

#include "test_macros.h"

template <typename OpT, typename T>
__host__ __device__ constexpr bool test_op(const T lhs, const T rhs, const T expected)
{
  return (OpT{}(lhs, rhs) == expected) && (OpT{}(lhs, rhs) == OpT{}(rhs, lhs));
}

template <typename T>
__host__ __device__ constexpr bool test(T lhs, T rhs, T expected)
{
  return test_op<cuda::minimum<T>>(lhs, rhs, expected) && //
         test_op<cuda::minimum<>>(lhs, rhs, expected) && //
         test_op<cuda::minimum<void>>(lhs, rhs, expected);
}

__host__ __device__ constexpr bool test()
{
  return test<int>(0, 1, 0) && //
         test<int>(1, 0, 0) && //
         test<int>(0, 0, 0) && //
         test<int>(-1, 1, -1) && //
         test<char>('a', 'b', 'a');
}

int main(int, char**)
{
  test();
  static_assert(test(), "");
  return 0;
}
