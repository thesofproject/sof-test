#!/bin/bash

set -e

TESTDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Need "exec" otherwise it believes to be a Sub-Test
exec "$TESTDIR"/test-case/multiple-pipeline.sh -f c "$@"
