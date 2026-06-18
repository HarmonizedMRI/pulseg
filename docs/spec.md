![pulseg logo](../assets/logo.svg)

# PulSeg Intermediate Representation Specification

**Version:** 2.1-alpha  
**Date:** 2026-06-18  
**Status:** Initial Release  
**Authors:** Jon-Fredrik Nielsen  
**Repository:** https://github.com/HarmonizedMRI/pulseg

---

## 1. Overview

PulSeg is a vendor-neutral intermediate representation (IR) for MRI pulse sequences. 
It is designed to sit between a high-level sequence description format (such as Pulseq) 
and a vendor-specific hardware execution layer. By making explicit the repeating structural 
units present in most MRI sequences, PulSeg enables efficient and unambiguous mapping onto 
the internal execution models of real scanner hardware.

This document defines the PulSeg data structures, terminology, and conversion requirements. 
It is intended for developers of sequence conversion tools, scanner interpreters, and 
simulation frameworks.

This specification is stable at version 2.1-alpha. Any change affecting data structure definitions, 
field semantics, or required fields must increment the version number and include 
migration notes in the changelog (see Section 7).

---

## 2. Definitions

- **Pulseq block:**  
  An atomic time unit in the [Pulseq](https://pulseq.github.io/) sequence format,
  containing at most one waveform per gradient axis, one RF waveform, and one ADC window. 
  Waveform amplitudes in a Pulseq block
  reflect the actual physical amplitudes used during that block.

- **Base block:**  
  A Pulseq block in which all waveform amplitudes have been normalized to a canonical value 
  (see Section 3.1). A base block defines the *shape* of the waveforms but not their 
  physical amplitudes. Base blocks are the atomic elements of a PulSeg representation.

- **Virtual segment:**  
  An ordered, finite sequence of base blocks representing a generic, reusable unit of the 
  MRI sequence — for example, a readout module, a spoiler module, or a contrast preparation
  module (it need not be periodic). A virtual segment 
  defines the *structure* of a sequence unit but not the specific amplitudes, phases, or 
  frequency offsets used in any particular execution.

- **Segment instance:**  
  A concrete realization of a virtual segment within the execution stream. A segment instance 
  associates a virtual segment with specific waveform amplitudes, RF phase offsets, and 
  frequency offsets for a single occurrence in the scan.

- **Execution stream:**  
  The ordered sequence of segment instances that defines the complete execution of the 
  MRI sequence on the scanner.

---

## 3. Data Structures

All field names use snake_case. Fields marked **(required)** must be present in any 
compliant PulSeg representation. Fields marked **(optional)** may be omitted.

### 3.1 BaseBlock

A base block wraps a single Pulseq block with normalized waveform amplitudes. A base block is
identified by the normalized *shapes* of its RF and ADC events and by the *timing* of its
gradient events. Because gradient identity is timing-based, a single gradient event may carry
more than one co-timed waveform *shape* — a *shot* dimension — much as a multi-channel (pTx) RF
event carries more than one transmit channel (see the normalization rules).

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | int | required | Unique identifier for this base block. Must be a non-negative integer. IDs 0 and 1 are globally reserved (see Reserved Identifiers below). User-defined blocks must use IDs ≥ 2. |
| `block` | PulseqBlock | required | A Pulseq block with all waveform amplitudes normalized to 1.0 (or 0.0 for unused channels). See normalization rules below. |
| `name` | string | optional | Human-readable descriptive label (e.g., `"rf_prep"`, `"gx_spoil"`). |

**Reserved Identifiers:**  
To support real-time timing optimizations on scanner hardware, the following base block IDs are globally reserved and implicitly defined across all PulSeg implementations:

- id == 0 (Implicit Constant Delay Block): Represents a pure delay block whose duration remains fixed and invariant across all instances in the execution stream. This allows hardware interpreters to pre-compute structural timing gaps.

- id == 1 (Implicit Variable Delay Block): Represents a pure delay block whose duration can vary dynamically between different instances in the execution stream (e.g., for extending TE or TR). The runtime duration is dictated explicitly by the corresponding entry in the instance's block_duration array.

**Normalization rules:**
- Single-channel RF waveforms: Normalize by peak magnitude, such that `max(|rf.signal|) == 1.0`.
- Multi-channel RF waveforms (Parallel Transmit / pTx): Normalize all transmit channels by a single global scaling factor 
derived from the maximum peak magnitude across all channels combined, such that 
$\max_{c}(\max(\lvert\text{rf.signal}_c\rvert)) == 1.0$. 
This ensures that the relative amplitude between distinct physical transmit coils are strictly preserved.
- Gradient waveforms: normalize each channel independently by peak absolute amplitude, such that `max(|grad.waveform|) == 1.0` for each channel. A gradient event MAY carry multiple co-timed *shot variants* — gradient shapes sharing one timing structure but differing in sample values, e.g. independently optimized spiral interleaves — and each shot variant is normalized independently (peak `1.0` per variant). Two gradient waveforms share a *timing structure* when they have identical `(delay, rise, flat, fall)` for trapezoids, `(delay, time_shape_id)` for extended trapezoids, or `(delay, num_samples)` on the gradient raster for uniform-raster arbitrary gradients. Shot variants are reserved for shapes NOT related by scaling or rotation; families related by scaling or rotation (phase-encode blips, radial spokes, rotated interleaves) MUST use a single shot variant scaled via `gradient_amplitude` / `rotation_matrix`. The single-shot case is the common one.
- ADC windows: not normalized; copied directly from the Pulseq block
- A channel with no waveform in the original block must have no waveform in the base block

### 3.2 VirtualSegment

A virtual segment defines an ordered sequence of base blocks constituting a reusable 
sequence unit.

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | int | required | Unique identifier for this virtual segment. Must be a positive integer. |
| `base_block_ids` | int[] | required | Ordered list of base block IDs comprising this segment. Must be non-empty. All referenced IDs must exist in the base block list. |
| `name` | string | optional | Human-readable descriptive label (e.g., `"tr_delay"`, `"inversion_prep"`). |

**Constraints:**
- `base_block_ids` must contain at least one entry
- All IDs in `base_block_ids` must reference valid base blocks

### 3.3 SegmentInstance

A segment instance associates a virtual segment with the concrete parameters for a 
single execution in the execution stream.

| Field | Type | Required | Description |
|---|---|---|---|
| `virtual_segment_id` | int | required | ID of the virtual segment being instantiated. Must reference a valid virtual segment. |
| `rf_amplitude` | float[] | required | Scaling factors for RF waveform amplitudes, one per RF event in the virtual segment. Multiply by the normalized base block RF amplitude to recover the physical amplitude. |
| `rf_phase_offset` | float[] | required | RF phase offsets in radians, one per RF event in the virtual segment. |
| `rf_frequency_offset` | float[] | required | RF transmit frequency offset in Hz, one per RF event in the virtual segment. |
| `gradient_amplitude` | float[3][] | required | Signed scaling factors for gradient amplitudes (Gx, Gy, Gz), one triplet per gradient event in the virtual segment. Negative values indicate polarity inversion relative to the normalized base block. |
| `gradient_shot_index` | int[] | optional | Selected shot variant for each gradient event (see BaseBlock, Section 3.1), one per gradient event. Defaults to 0 — the first/only shot — if omitted. |
| `adc_phase_offset` | float[] | required | ADC receiver phase offsets in radians, one per ADC event in the virtual segment. |
| `adc_frequency_offset` | float[] | required | ADC receiver frequency offset in Hz, one per ADC event in the virtual segment. |
| `block_duration` | float[] | required | Pulseq block duration in seconds, one per block in the virtual segment. |
| `rotation_matrix` | float[3][3][] | optional | 3D spatial rotation matrices applied to the gradient axes, one per gradient event in the virtual segment. Defaults to identity if omitted.|
| `physio_trigger` | int | optional | Binary hardware flag (1 or 0) indicating whether execution must pause to await a physical gating event (e.g., ECG R-wave or respiratory trigger) before playing out this instance. Defaults to 0 if omitted. |
| `label` | string | optional | Optional execution stream label for this instance (e.g., for slice or contrast indexing). |

**Notes:**
- If a virtual segment contains no RF/gradient/adc events, the associated columns (e.g., `rf_amplitude`, `rf_phase_offset`, etc)
  may be empty arrays but must still be present as fields
- Physical amplitude = base block normalized amplitude × scaling factor
- For multishot base gradients, the per-instance physical gradient uses the shot variant
  selected by `gradient_shot_index`: physical gradient = rotation × signed-scale ×
  (selected-variant normalized waveform)

### 3.4 PulSeg Representation (Top-Level Structure)

A complete PulSeg representation consists of the following top-level fields:

| Field | Type | Required | Description |
|---|---|---|---|
| `pulseg_version` | string | required | Version of this specification. Must be `"2.1-alpha"` for representations compliant with this document. |
| `base_blocks` | BaseBlock[] | required | List of all base blocks. Must be non-empty. IDs must be unique. |
| `virtual_segments` | VirtualSegment[] | required | List of all virtual segments. Must be non-empty. IDs must be unique. |
| `execution_stream` | SegmentInstance[] | required | Ordered list of segment instances defining the complete scan execution. Must be non-empty. |
| `source_file` | string | optional | Path or filename of the source Pulseq `.seq` file from which this representation was generated. |
| `creation_date` | string | optional | ISO 8601 date string (e.g., `"2025-02-20"`) indicating when this representation was created. |

---

## 4. Conversion from Pulseq

### 4.1 Overview

Conversion from a Pulseq `.seq` file to PulSeg proceeds in three steps:

1. **Parse and normalize** — Read all Pulseq blocks; normalize waveform amplitudes to 
   produce base blocks (see Section 3.1 normalization rules).
2. **Identify segments** — Group consecutive base blocks into virtual segments. Segment 
   boundaries must be explicitly annotated in the Pulseq file using the PulSeg labeling 
   convention (see Section 4.2).
3. **Build the execution stream** — For each instance of each virtual segment in the Pulseq 
   block stream, record the physical amplitude, phase, and frequency parameters as a 
   segment instance.


### 4.2 Segment Instance Boundary Annotation

Segment instance boundaries are defined by the sequence designer at the time of Pulseq sequence
creation, using Pulseq block labels. The labeling convention is as follows:

- The first block of each segment instance MUST carry a `TRID` label.
- The value of the `TRID` label identifies the virtual segment instantiated by that segment instance.
- Blocks following a `TRID`-labeled block are considered part of the same segment instance until the next block carrying a `TRID` label or the end of the sequence.
- Blocks inside a segment instance MUST NOT also carry `TRID` labels.
- Repeated occurrences of the same `TRID` value are treated as instances of the same virtual segment and MUST have the same number of Pulseq blocks and the same normalized base-block structure. For gradient events, *the same structure* is defined by timing structure (Section 3.1): repeated instances MAY select different shot variants via `gradient_shot_index`, provided the gradient timing structure is identical across instances.
- The first Pulseq block in the source sequence MUST carry a `TRID` label.

*[Note: provide a concrete example here, ideally with a code snippet from a Pulseq sequence 
file and the resulting PulSeg representation.]*

### 4.3 Conversion Requirements

The following requirements apply to any compliant Pulseq-to-PulSeg conversion:

- All base block waveforms MUST be normalized according to the rules in Section 3.1
- Every virtual segment MUST have a unique ID
- Every base block MUST have a unique ID
- The execution stream MUST account for every block in the source Pulseq file (conversion is lossless)
- The `pulseg_version` field MUST be set to the version of this specification
- Amplitude scaling factors MUST be such that: physical amplitude = normalized amplitude × scale factor
- Gradient shapes that differ across instances of one virtual segment MUST be encoded per the shot-variant rules in Section 3.1 (shot variants only for shapes not related by scaling or rotation; scale/rotation families use a single shot variant).

---

## 5. Diagram

![Intermediate Representation](./spec-diagram.png)

*Figure 1. Schematic of the PulSeg intermediate representation, showing the relationship 
between base blocks, virtual segments, and segment instances in the execution stream.*

---

## 6. Versioning and Changelog

**Current version:** 2.1-alpha

Any change to this specification that affects data structure definitions, field names, 
field types, required/optional status, or normalization rules must:
1. Increment the version number (patch increment for clarifications, minor increment for 
   additive changes, major increment for breaking changes)
2. Add an entry to the changelog below
3. Update the `pulseg_version` field description in Section 3.4

### Changelog

| Version | Date | Description |
|---|---|---|
| 1.0 | 2025-02-20 | Initial release |
| 2.0-alpha | 2026-06-11 | Class definition structural upgrade; minor naming standard alignment to PyPulseq variable guide |
| 2.1-alpha | 2026-06-18 | Clarified that a virtual segment is a reusable structural unit (replaced the "TR period" example; it need not be periodic). Folded multishot gradients into the base-block model: a gradient event may carry co-timed shot variants identified by timing structure, selected per instance via the optional `gradient_shot_index` field. Additive and backward-compatible; single-shot representations are unaffected. |

---

## 7. References

- Layton KJ et al. Pulseq: A rapid and hardware-independent pulse sequence prototyping 
  framework. *Magn Reson Med.* 2017;77(4):1544–1552.
- [Pulseq specification](https://pulseq.github.io/)
- [PulSeg GitHub repository](https://github.com/HarmonizedMRI/pulseg)

---

## 8. Contact and Contributions

For questions, bug reports, or change requests, please open a GitHub issue:  
https://github.com/HarmonizedMRI/pulseg/issues

For correspondence regarding this specification:  
*jfnielsen@gmail.com*

