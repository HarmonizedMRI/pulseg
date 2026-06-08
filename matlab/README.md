# Pulseg MATLAB Tools

This directory contains the MATLAB implementation for the `pulseg` open-source, vendor-neutral MRI pulse sequence standard.

## Directory Structure

* **`+pulseg/`** - The main package namespace containing the core `pulseg.import` function and associated helper functions.
* **`tests/`** - Unit tests for validating package functions.

## Getting Started

### Prerequisites
Ensure this `matlab/` directory is added to your MATLAB path so the `+pulseg` namespace is discoverable:
```matlab
addpath('/path/to/pulseg/matlab');

```

### Running Unit Tests

To execute the test suite, navigate to this directory and run:

```matlab
results = runtests('tests');
table(results)

```

