#!/usr/bin/python3

import itertools
import argparse

parser = argparse.ArgumentParser(description='''
Help to dump the permutation and combination:
each combine split by SPACE,
each element split by \',\'

for example:
    target: C 4 2
    parameter: -t c -n 4 -p 2
    output: "0,1 0,2 0,3 1,2 1,3 2,3"

    target: P 4 2
    parameter: -t p -n 4 -p 2
    output: "0,1 0,2 0,3 1,0 1,2 1,3 2,0 2,1 2,3 3,0 3,1 3,2"
''', add_help=True, formatter_class=argparse.RawTextHelpFormatter)

parser.add_argument('-t', '--type', choices=['c','p'], help='p: permutation; c: combination', default='c')
parser.add_argument('-n', '--number', type=int, help='total number count', required=True)
parser.add_argument('-p', '--pick', type=int, help='pick up count', required=True)
parser.add_argument('-s', '--start', type=int, help='index start value', default=0)

ret_args = vars(parser.parse_args())

if ret_args['number'] < ret_args['pick']:
    print(f"Count:{ret_args['pick']} > Number Count:{ret_args['number']} is not allowed")
    exit(2)

number = ret_args['number']
pickup = ret_args['pick']
start = ret_args['start']

if start != 0:
    number = number + start

if ret_args['type'] == 'c':
    result_lst=list(itertools.combinations(range(start, number), pickup))
else:
    result_lst=list(itertools.permutations(range(start, number), pickup))

output_str=""
for combine in result_lst:
    output_str += " " + ",".join([str(i) for i in combine])
print(output_str.strip())
