# Kernel Tracing

This hosts a WIP effort to use kernel tracing to evaluate performance and validate the execution
context of various functions and operations. The `bpftrace_scripts` folder contains short scripts
that you can run via the command line. They'll collect traces from the kernel via
[kprobes](https://lwn.net/Articles/132196) and
[tracepoints](https://blogs.oracle.com/linux/post/taming-tracepoints-in-the-linux-kernel), and
output data either as they run or when stopped with ctrl-c. To use them, you'll need to include the
kconfig/bpf-defconfig in your kernel config, and install `bpftrace` via your package manager. Then,
just run them with `bpftrace [path to script]`.

Soon, kernel tracing will be integrated into the CI process to detect performance regressions using tools that allow for collection and evaluation of BPF programs' output.
