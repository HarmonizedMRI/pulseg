![pulseg logo](../assets/logo.svg)

# PulSeg Intermediate Representation Specification

**Version:** 1.0  
**Date:** 2026-02-20  
**Status:** Initial Release  
**Scope:** Formal definition of the intermediate representation for converting Pulseq MRI sequence files in pulseg. This specification is stable; future changes must increment version.

---

## 1. Definitions

- **Base Block:**  
  A Pulseq block with normalized waveform amplitudes and defined block type (e.g., RF, gradient, ADC). Acts as an atomic element.
- **Virtual Segment:**  
  An ordered sequence of base blocks representing a generic segment of the MRI sequence, without specific amplitudes or phase/frequency offsets. Also referred to as a “core”.
- **Segment Instance:**  
  A realization of a virtual segment within the scan loop, providing concrete waveform amplitudes, phase and frequency offsets, and unique parameterization.

---

## 2. Data Structures

### 2.1 BaseBlock

```matlab
struct BaseBlock
    type: string         // Block type, e.g., 'excite', 'acquire', 'spoil'
    waveform: array      // Normalized amplitude array
    axis: string[]       // ['RF', 'Gx', 'Gy', 'Gz', ...]
    metadata: struct     // Optional, includes timing, duration, shape
end
```

### 2.2 VirtualSegment

```matlab
struct VirtualSegment
    id: integer              // Unique segment/core ID
    base_blocks: BaseBlock[] // Ordered sequence of base blocks
    metadata: struct         // Optional, segment-level metadata
end
```

### 2.3 SegmentInstance

```matlab
struct SegmentInstance
    virtual_segment_id: integer          // Reference to VirtualSegment
    instance_id: integer                 // Optional, unique occurrence within scan loop
    parameterization: dict               // Key-values for amplitude, phase, etc.
end
```

### 2.4 Intermediate Representation

The IR should include:
- List of BaseBlocks
- List of VirtualSegments
- List of SegmentInstances (per scan repetition)
- Specification version (`ir_version: 1.0`)

---

## 3. Workflow

### 3.1 Conversion

1. Parse Pulseq file → Identify and normalize blocks (BaseBlocks).
2. Assemble VirtualSegments from ordered base blocks.
3. Generate SegmentInstances for each scan repetition, parameterized with physical values.

### 3.2 Requirements

- All base blocks MUST be normalized.
- Virtual segments MUST be uniquely identified.
- Segment instance parameterization MUST include amplitude and phase/frequency offsets.
- IR version identifier MUST be included.

---

## 4. Figure 1: Intermediate Representation Diagram

![Intermediate Representation](./spec-diagram.png)

---

## 5. Versioning

This document is version 1.0.  
Any changes affecting structure or field meanings must increment the version number and provide migration notes.

---

## 6. References

- [Pulseq Specification](https://pulseq.github.io/)
- [PulSeg GitHub repository](https://github.com/HarmonizedMRI/pulseg/)

---

## 7. Contact

For questions, feedback, or change requests:  
- [GitHub Issues](https://github.com/HarmonizedMRI/pulseg/issues)  
- Email: *your-address@your-domain.edu*

---


---

### Optional: Add a CHANGELOG.md in your docs directory to record any modifications by version.

### Optional: Add a `ir_version` field to your intermediate representation files, enforcing compatibility checks.

---

