import sys
import json
import re

ACCEPTANCE_BUFFER = 8.0


def compare_values(real, expected):
    if abs(real-expected) <= ACCEPTANCE_BUFFER:
        return True
    return False


def analyze_pc_states(pc_states_file, expected_results):
    pattern = re.compile(r'^PC(\d+)\s*,\s*(\d+(?:\.\d+)?)\s*,\s*(\d+(?:\.\d+)?)\s*$')
    # Example lines we want to catch:
    # PC0    , 81.09                , 119.51
    # PC2    , 18.91                , 27.87
    failures = 0

    with open(pc_states_file, encoding="utf-8") as file:
        for line in file:
            m = pattern.match(line)
            if not m:
                continue
            
            pc_state_nr = int(m.group(1))
            pc_state = "PC"+str(pc_state_nr)
            value = float(m.group(2))
            expected_value = expected_results.get(pc_state)
            if not expected_value:
                continue
            if not compare_values(value, float(expected_value)):
                print(f"Incorrect value: {pc_state} time % was {value}, expected {expected_value}")
                failures += 1

    if failures:
        return 1
    return 0


# This script analyzes if the % of the time spent in given PC state was as expected
if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Incorrect number of args!")
        sys.exit(1)

    pc_states_results_file = sys.argv[1]
    pc_states_thresholds = json.loads(sys.argv[2])
    
    result = analyze_pc_states(pc_states_results_file, pc_states_thresholds)
    sys.exit(result)
