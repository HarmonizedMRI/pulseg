![pulseg logo](../assets/logo.svg)

# PulSeg Intermediate Representation Specification

**Version:** 1.0  
**Date:** 2026-02-20  
**Status:** Initial Release  
**Scope:** Formal definition of the intermediate representation for converting Pulseq MRI sequence files in pulseg. This specification is stable; future changes must increment version.

---

## 1. Definitions

- **Base Block:**  
  A Pulseq block with normalized waveform amplitudes. Acts as an atomic element.
- **Virtual Segment:**  
  An ordered sequence of base blocks representing a generic segment of the MRI sequence, without specific amplitudes or phase/frequency offsets. 
- **Segment Instance:**  
  A realization of a virtual segment within the scan loop, providing concrete waveform amplitudes, and phase and frequency offsets.

---

## 2. Data Structures

### 2.1 BaseBlock

```matlab
struct BaseBlock
    id: int                // Unique base block ID
    block: Pulseq block    // A Pulseq block with normalized waveform amplitudes
    name: string           // Optional, descriptive name 
end
```

### 2.2 VirtualSegment

```matlab
struct VirtualSegment
    id: int                      // Unique segment ID
    baseBlockIdx:  int vector    // Base block IDs
    instances: int vector        // Start indices (row numbers in .seq file) of all segment instances
    name: string                 // Optional, descriptive name
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
- Dynamic scan settings, e.g., as list of SegmentInstances, or a table of dynamically varying virtual segment IDs and  amplitude/phase settings.
- Specification version (`ir_version: 1.0`)

---

## 3. Workflow

### 3.1 Conversion

1. Parse Pulseq file → Identify and normalize blocks (BaseBlocks).
2. Assemble VirtualSegments from ordered base blocks.
3. Create table containing dynamic list of segment instances and associated waveform amplitude/phase/frequency.

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

