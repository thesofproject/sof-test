import csv
import sys
import json
import re

ACCEPTANCE_BUFFER = 2.0


def compare_values(real, expected):
    if abs(real-expected) <= ACCEPTANCE_BUFFER:
        return True
    return False


def analyze_pc_states(pc_states_file, expected_results):
    pattern = re.compile(r'^PC(\d+)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*$')
    failures = 0

    with open(pc_states_file) as file:
        for line in file:
            m = pattern.match(line)
            if m:
                pc_state_nr = int(m.group(1))
                pc_state = "PC"+str(pc_state_nr)
                value = float(m.group(2))
                expected_value = float(expected_results.get(pc_state))
                if not expected_value:
                    continue
                if not compare_values(value, expected_value):
                    print(f"Incorrect value: {pc_state} time % was {value}, expected {expected_value}")
                    failures += 1

    return 0 if failures == 0 else 1    

    
# This script analyzes if the % of the time spent in given PC state was as expected
if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Incorrect number of args!")
        sys.exit(1)

    pc_states_results_file = sys.argv[1]
    pc_states_thresholds = json.loads(sys.argv[2])
    
    result = analyze_pc_states(pc_states_results_file, pc_states_thresholds)
    sys.exit(result)
