# Metric Evaluation

The `test.py` script in this directory executes tests specified in a JSON file.
The JSON file is formatted as such:

```json
{
  "cases": [
    {
      "name": "Name to be displayed in output",
      "bpftrace": "path to the bpftrace script used to collect metrics, relative to spec file",
      "shell": "shell command to be run alongside bpftrace script, relative to spec file",
      "conditions": [
        "list of conditions that will be evaluated against bpftrace output",
        "these are python expressions",
        "bpftrace vars can be referenced with @{var name}, ie @avg",
        "maps are referenced by @{var name}[{key name(s)}], ie @avg[ipc_time]"
      ]
    }
  ]
}
```
See `sample_spec.json` for an example. `no_dependencies.json` is an alternative
spec file that should be able to run without any special kernel config.


To run a test file, pass it as an argument to the `test.py` script:

```bash
./test.py my_tests.json
```

If any of the tests fail, the script will exit with code 1. Individual test
output will also be printed.