---
name: Bug report
about: Create a report to help us improve
title: "[BUG]"
labels: bug
assignees: ''

---

**Describe the bug**
A clear and concise description of what the bug is.
What have you tried to diagnose or workaround this issue?

**To Reproduce**
Steps to reproduce the behavior: (e.g. list commands or actions used to reproduce the bug)

**Expected behavior**
A clear and concise description of what you expected to happen.

**Detail Info**
1) Branch name and commit hash of the 3 repositories: sof (firmware/topology), linux (kernel driver) and sof-test (test case)
    * Kernel: {SHA}
    * SOF: {SHA}
    * SOF-TEST: {SHA}
2) Test report ID (if you find it from test report)
    * ID: {NUMBER}
3) Test DUT Model (or a brief discribtion about the device)
    * MODEL: {DUT MODEL}
4) Test TPLG
    * TPLG: {TPLG NAME}
5) Test case (what test script and how you run it)
    * TESTCASE: {TEST SCRIPT AND CMD}

**Screenshots or console output**
If applicable, add a screenshot (drag-and-drop an image), or console logs
(cut-and-paste text and put a code fence (\`\`\`) before and after, to help
explain the issue.

Please also include the relevant sections from the firmware log and kernel log in the report (and attach the full logs for complete reference). Kernel log is taken from *dmesg* and firmware log from *sof-logger*. See https://thesofproject.github.io/latest/developer_guides/debugability/logger/index.html
