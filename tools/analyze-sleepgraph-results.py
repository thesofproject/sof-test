from bs4 import BeautifulSoup
from pathlib import Path
import re
import sys
import json
import os


# pylint: disable=R0914
def analyze_sleepgraph_file(file, thresholds, acceptance_range):
    with open(file, 'r', encoding='utf-8') as f:
        soup = BeautifulSoup(f, 'lxml')
        complete_results={}
        test_passed=True

        components=thresholds.keys()
        for component in components:
            # pylint: disable=W0621
            results = {}
            divs = soup.find_all("div", title=lambda t, component=component: t and component in t)

            for div in divs:
                title = div.get('title')
                match = re.search(r'\((\d+(?:\.\d+)?)\s*ms\)\s+(\S+)$', title)
                if match:
                    time_ms = float(match.group(1))
                    measurement_name = match.group(2)
                    if measurement_name in thresholds[component]:
                        results[measurement_name] = {"value": time_ms, "pass": True}
                        threshold = float(thresholds[component][measurement_name])
                        # pylint: disable=R1716
                        if time_ms<(threshold * (1-acceptance_range)) or time_ms>(threshold * (1+acceptance_range)):
                            results[measurement_name]["pass"] = False
                            test_passed = False

            complete_results[component]=results

        print(complete_results)
        return test_passed, complete_results


def save_results_to_file(result):
    # pylint: disable=W0621
    results_file = f'{os.getenv("LOG_ROOT")}/resume_time_results.json'
    data = []

    if Path(results_file).is_file():
        with open(results_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
            
    data.append(result)
    print(f"Current results: {data}")

    with open(results_file, "w", encoding='utf-8') as f:
        f.write(json.dumps(data))
    return results_file
    

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print("Incorrect number of args!")
        sys.exit(1)

    sleepgraph_file = sys.argv[1]
    sleepgraph_thresholds = json.loads(sys.argv[2])
    thresholds_buffer = float(sys.argv[3])
    
    test_pass, results = analyze_sleepgraph_file(sleepgraph_file, sleepgraph_thresholds, thresholds_buffer)
    print(f"Sleepgraph report analysis passed: {test_pass}")

    results_file = save_results_to_file(results)
    print(f"Saved results to file: {results_file}")
    
    sys.exit(0 if test_pass else 1)
