#!/usr/bin/gawk -f

# SPDX-License-Identifier: BSD-3-Clause
# Copyright(c) 2025 Intel Corporation. All rights reserved.

# A library of functions to re-use in AWK scripts.

function min(in_array,  min_value,idx)
{
  min_value = "N/A"
  if (! isarray(in_array) || length(in_array) == 0) return min_value
  for(idx in in_array) {
    if (min_value == "N/A" || in_array[idx] < min_value) {
        min_value = in_array[idx]
    }
  }
  return min_value
}

function max(in_array,  max_value,idx)
{
  max_value = "N/A"
  if (! isarray(in_array) || length(in_array) == 0) return max_value
  for(idx in in_array) {
    if (max_value == "N/A" || in_array[idx] > max_value) {
        max_value = in_array[idx]
    }
  }
  return max_value
}

function sum(in_array,  sum_items,idx)
{
  if (! isarray(in_array) || length(in_array) == 0) return 0
  sum_items=0
  for(idx in in_array) {
    sum_items += in_array[idx]
  }
  return sum_items
}

function stddev(in_array, sum_items,cnt_items,idx,avg,dev)
{
  if (! isarray(in_array) || length(in_array) == 0) return -1
  sum_items=0
  cnt_items=0
  for(idx in in_array) {
    sum_items += in_array[idx]
    cnt_items += 1
  }
  avg = sum_items / cnt_items
  dev = 0
  for(idx in in_array) dev += (in_array[idx] - avg)^2
  return sqrt(dev/(cnt_items - 1))
}
