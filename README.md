
<p align="left">
  <img src="assets/logo.svg" alt="pulseg logo" width="320"/>
</p>

**A segment-based intermediate representation for validating, transforming, and exporting Pulseq MRI sequences**

🛠️ Under Development

---

## Overview

`PulSeg` provides a standardized MATLAB pipeline for converting [Pulseq](https://pulseq.github.io/) MRI pulse sequence files into a segment-based **intermediate representation**.

The PulSeg IR separates normalized reusable waveform blocks from concrete scan-time amplitudes, phases, frequency offsets, and durations. This makes repeated sequence structure explicit and supports validation, transformation, Pulseq round-tripping, and translation to scanner-specific execution layers such as GE via [`pge2`](https://github.com/HarmonizedMRI/pge2).

**Project status:** Version `2.0-alpha` of the IR specification is formalized in [`docs/spec.md`](docs/spec.md). The MATLAB toolbox currently supports Pulseq import, PulSeg IR validation, Pulseq base-block checking/hydration, and flattened Pulseq `.seq` export.

---

## Key Concepts

- **Base Block**  
  A normalized Pulseq block. Base blocks define waveform/timing shape, not scan-time amplitudes or phases.

- **Virtual Segment**  
  An ordered sequence of base block IDs defining reusable sequence structure.

- **Segment Instance**  
  A concrete realization of a virtual segment, including RF amplitudes/phases, frequency offsets, gradient scale factors, ADC offsets, and block durations.

- **Execution Stream**  
  The ordered list of segment instances that defines the full scan.

![Intermediate Representation Diagram](docs/spec-diagram.png)

---

## Installation

```bash
git clone https://github.com/HarmonizedMRI/pulseg.git
```

In MATLAB:

```matlab
addpath pulseg/matlab
addpath(genpath('pulseg/matlab/third_party'))
```

---

## Usage

### Import Pulseq into PulSeg

Source Pulseq files must contain `TRID` labels marking the first block of each segment instance.

```matlab
pulseg_ir = pulseg.import('path/to/sequence.seq');
```

### Validate the IR

```matlab
pulseg.validate_ir(pulseg_ir);
```

### Check or hydrate Pulseq base blocks

```matlab
[pulseg_ir, report] = pulseg.check_base_blocks( ...
    pulseg_ir, ...
    'hydrate', true, ...
    'require_normalized', true, ...
    'strip_metadata_extensions', true);
```

### Export back to Pulseq

```matlab
seq = pulseg.write_seq(pulseg_ir, 'out.seq');
```

With a Pulseq system object:

```matlab
sys = mr.opts();
seq = pulseg.write_seq(pulseg_ir, 'out.seq', 'system', sys);
```

### GE translation

For execution on GE systems, use the [`pge2`](https://github.com/HarmonizedMRI/pge2) toolbox.

---

## MATLAB Toolbox Functions

| Function | Purpose |
|---|---|
| `pulseg.import` | Convert a Pulseq `.seq` file or `mr.Sequence` object to a PulSeg IR struct. |
| `pulseg.validate_ir` | Validate PulSeg 2.0-alpha structure and consistency. |
| `pulseg.check_pulseq_block` | Check and optionally hydrate one Pulseq-like base block. |
| `pulseg.check_base_blocks` | Check and optionally hydrate all explicit base blocks. |
| `pulseg.write_seq` | Flatten a PulSeg IR and write a Pulseq `.seq` file. |

---

## Segment Boundary Annotation

PulSeg currently requires explicit segment boundary labels in the source Pulseq file:

- The first block of each segment instance must carry a `TRID` label.
- The first block of the sequence must contain a `TRID` label.
- Repeated instances of the same `TRID` must have the same normalized base-block structure.

See [`docs/spec.md`](docs/spec.md) for details.

---

## Current Limitations

- Automatic segment discovery is not implemented.
- `TRID` labels are currently required.
- Pulseq export produces a flattened `.seq` stream and may not preserve all segmentation metadata.
- Non-identity gradient rotation export is limited or not yet implemented.
- Physiological trigger export is backend-specific and not yet generally supported.
- Safety, SAR, and hardware-limit validation are outside the scope of `pulseg.validate_ir`.

---

## Documentation

- [Intermediate Representation Specification v2.0-alpha](docs/spec.md)
- [Install instructions](docs/install.md)
- [Changelog](docs/changelog.md)

---

## Contributing

Contributions are welcome!

- Open issues for bugs or feature requests.
- Submit pull requests against the `main` branch.

---

## License

This repository is licensed under [MIT](LICENSE).

---

## Citation

If you use `PulSeg` for your research, please cite:

```text
pulseg: A Harmonized Intermediate Representation for MRI Sequence Files,
HarmonizedMRI Consortium, 2026.
```

---

## Contact

Questions or feedback? Open a [GitHub Issue](https://github.com/HarmonizedMRI/pulseg/issues).

---
