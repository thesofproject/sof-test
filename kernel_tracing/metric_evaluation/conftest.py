import argparse
import os
import json
import subprocess
import re

# This file does all the setup for the "test_bpftrace_conditions" function in test.py
# It loads the test cases from the json file, and runs the bpftrace script and shell commands
# It collects the variables from the bpftrace script through stdout,
# and then uses Pytest Parameterization to run the test function for each condition


def pytest_addoption(parser):
    parser.addoption("--spec_file", type=argparse.FileType('r'),
                     help="json file with test cases", required=True)


def pytest_itemcollected(item):
    """ Overwrite test name with name defined in json file """
    item.name = item.name.split('[', 1)[1][:-1]
    # pylint: disable=protected-access
    item._nodeid = item.name


class BPFTrace:
    def __init__(self, bpftrace_script):
        self.script = bpftrace_script
        self.process = None

    def start(self):
        self.process = subprocess.Popen(
            ["bpftrace", self.script], stdout=subprocess.PIPE, encoding="utf-8")
        # Wait for bpftrace script to load
        while True:
            line = self.process.stdout.readline()
            if "Attaching" in line:
                break

    def stop(self):
        # Send ctrl-c
        self.process.send_signal(subprocess.signal.SIGINT)
        self.process.wait(10)

        # Collect printed variables for condition evaluation
        lines = self.process.stdout.read().split("\n")
        bpftrace_vars = {}
        for line in lines:
            # Check if line is outputting a variable from the script
            # bpftrace output format is `@name[key1, key2, ...]: val` (keys are optional)
            if re.match("@.*: .*", line):
                key, val = line.split(": ", 1)
                bpftrace_vars[key] = val
        return bpftrace_vars


def collect_test_results(test_case, working_dir):
    """ This runs the bpftrace script and the shell command, and collects the trace output from stdout """
    # Start bpftrace collection
    bpftrace_script = os.path.join(working_dir, test_case['bpftrace'])
    bpf = BPFTrace(bpftrace_script)
    bpf.start()

    # Execute shell command
    shell_cmd = test_case['shell']
    print("$", shell_cmd)
    subprocess.run(shell_cmd, cwd=working_dir, shell=False, check=True)

    # Stop tracing and return collected output vairables
    print("BPF tracing finished")
    bpf_vars = bpf.stop()
    return bpf_vars


def pytest_generate_tests(metafunc):
    """ Parametrize each JSON test case, once for each of its conditions """
    if not "bpftrace_condition" in metafunc.fixturenames:
        raise RuntimeError("Invalid test case.")
    spec_file = metafunc.config.option.spec_file
    spec_dir = os.path.dirname(os.path.realpath(spec_file.name))
    spec = json.load(spec_file)
    conditions = []
    # Generate a list of conditions to evaluate
    for test_case in spec['cases']:
        bpftrace_vars = collect_test_results(test_case, spec_dir)
        for condition in test_case['conditions']:
            conditions.append((test_case['name'], condition, bpftrace_vars))

    # Parameterize the conditions so that the test function gets run for each condition
    # We also set the ids of the functions to be "name: condition" for better reporting
    metafunc.parametrize("bpftrace_condition", conditions, ids=map(
        lambda c: f"{c[0]}: {c[1]}", conditions))
