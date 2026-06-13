function validate_ir(pulseg_ir)
% VALIDATE_IR Validate a PulSeg 2.0-alpha intermediate representation struct.
%
% Syntax:
%   pulseg.validate_ir(pulseg_ir)
%
% Description:
%   VALIDATE_IR performs structural and consistency checks on a PulSeg IR
%   struct according to the PulSeg 2.0-alpha specification. It verifies required
%   top-level fields, base block IDs, virtual segment references, execution
%   stream references, and per-instance array lengths.
%
%   This function performs structural validation only. It does not replace
%   Pulseq timing checks, scanner hardware-limit checks, SAR/RF safety checks,
%   or vendor-specific execution validation.
%
% Inputs:
%   pulseg_ir
%       PulSeg IR struct to validate.

    %% Top-level checks

    assert(isstruct(pulseg_ir), ...
        'PulSeg IR must be a struct.');

    require_field(pulseg_ir, 'pulseg_version', 'pulseg_ir');
    require_field(pulseg_ir, 'base_blocks', 'pulseg_ir');
    require_field(pulseg_ir, 'virtual_segments', 'pulseg_ir');
    require_field(pulseg_ir, 'execution_stream', 'pulseg_ir');

    assert(ischar(pulseg_ir.pulseg_version) || isstring(pulseg_ir.pulseg_version), ...
        'pulseg_version must be a string.');

    assert(strcmp(char(pulseg_ir.pulseg_version), '2.0-alpha'), ...
        'pulseg_version must be ''2.0-alpha''. Found ''%s''.', char(pulseg_ir.pulseg_version));

    assert(~isempty(pulseg_ir.base_blocks), ...
        'base_blocks must be non-empty for PulSeg 2.0-alpha.');

    assert(~isempty(pulseg_ir.virtual_segments), ...
        'virtual_segments must be non-empty.');

    assert(~isempty(pulseg_ir.execution_stream), ...
        'execution_stream must be non-empty.');

    %% Optional metadata checks

    if isfield(pulseg_ir, 'creation_date') && ~isempty(pulseg_ir.creation_date)
        assert(ischar(pulseg_ir.creation_date) || isstring(pulseg_ir.creation_date), ...
            'creation_date must be a string if present.');
    end

    if isfield(pulseg_ir, 'source_file') && ~isempty(pulseg_ir.source_file)
        assert(ischar(pulseg_ir.source_file) || isstring(pulseg_ir.source_file), ...
            'source_file must be a string if present.');
    end

    %% BaseBlock checks

    base_ids = zeros(1, numel(pulseg_ir.base_blocks));

    for p = 1:numel(pulseg_ir.base_blocks)
        bb_name = sprintf('base_blocks(%d)', p);

        require_field(pulseg_ir.base_blocks(p), 'id', bb_name);
        require_field(pulseg_ir.base_blocks(p), 'block', bb_name);

        id = pulseg_ir.base_blocks(p).id;

        assert(isnumeric(id) && isscalar(id) && isfinite(id) && id == floor(id), ...
            '%s.id must be an integer.', bb_name);

        assert(id >= 2, ...
            '%s.id must be >= 2. IDs 0 and 1 are reserved implicit delay blocks.', bb_name);

        base_ids(p) = id;

        check_pulseq_block(pulseg_ir.base_blocks(p).block, sprintf('%s.block', bb_name));
        check_base_block_normalization(pulseg_ir.base_blocks(p).block, bb_name);
    end

    assert(numel(unique(base_ids)) == numel(base_ids), ...
        'Base block IDs must be unique.');

    valid_base_ids = [0 1 base_ids];

    %% VirtualSegment checks

    vs_ids = zeros(1, numel(pulseg_ir.virtual_segments));

    for s = 1:numel(pulseg_ir.virtual_segments)
        vs_name = sprintf('virtual_segments(%d)', s);

        require_field(pulseg_ir.virtual_segments(s), 'id', vs_name);
        require_field(pulseg_ir.virtual_segments(s), 'base_block_ids', vs_name);

        id = pulseg_ir.virtual_segments(s).id;
        ids = pulseg_ir.virtual_segments(s).base_block_ids;

        assert(isnumeric(id) && isscalar(id) && isfinite(id) && id == floor(id), ...
            '%s.id must be an integer.', vs_name);

        assert(id > 0, ...
            '%s.id must be positive.', vs_name);

        assert(isnumeric(ids) && isvector(ids) && ~isempty(ids), ...
            '%s.base_block_ids must be a non-empty numeric vector.', vs_name);

        assert(all(isfinite(ids)) && all(ids == floor(ids)), ...
            '%s.base_block_ids must contain integer IDs.', vs_name);

        assert(all(ismember(ids, valid_base_ids)), ...
            '%s.base_block_ids references invalid base block IDs.', vs_name);

        vs_ids(s) = id;
    end

    assert(numel(unique(vs_ids)) == numel(vs_ids), ...
        'Virtual segment IDs must be unique.');

    %% Execution stream checks

    for k = 1:numel(pulseg_ir.execution_stream)
        inst_name = sprintf('execution_stream(%d)', k);
        inst = pulseg_ir.execution_stream(k);

        required_inst_fields = { ...
            'virtual_segment_id', ...
            'rf_amplitude', ...
            'rf_phase_offset', ...
            'rf_frequency_offset', ...
            'gradient_amplitude', ...
            'adc_phase_offset', ...
            'adc_frequency_offset', ...
            'block_duration'};

        for f = 1:numel(required_inst_fields)
            require_field(inst, required_inst_fields{f}, inst_name);
        end

        virtual_segment_id = inst.virtual_segment_id;

        assert(isnumeric(virtual_segment_id) && isscalar(virtual_segment_id) && ...
               isfinite(virtual_segment_id) && virtual_segment_id == floor(virtual_segment_id), ...
            '%s.virtual_segment_id must be an integer.', inst_name);

        assert(ismember(virtual_segment_id, vs_ids), ...
            '%s.virtual_segment_id references invalid virtual segment ID %d.', ...
            inst_name, virtual_segment_id);

        s = find(vs_ids == virtual_segment_id, 1);
        vs = pulseg_ir.virtual_segments(s);

        counts = count_events_in_virtual_segment(vs, pulseg_ir.base_blocks);

        %% block_duration

        assert(isnumeric(inst.block_duration) && isvector(inst.block_duration), ...
            '%s.block_duration must be a numeric vector.', inst_name);

        assert(numel(inst.block_duration) == counts.n_blocks, ...
            '%s.block_duration must have one entry per block in the virtual segment. Expected %d, found %d.', ...
            inst_name, counts.n_blocks, numel(inst.block_duration));

        assert(all(isfinite(inst.block_duration)) && all(inst.block_duration >= 0), ...
            '%s.block_duration entries must be finite and non-negative.', inst_name);

        %% RF arrays

        check_numeric_vector(inst.rf_amplitude, ...
            sprintf('%s.rf_amplitude', inst_name), counts.n_rf);

        check_numeric_vector(inst.rf_phase_offset, ...
            sprintf('%s.rf_phase_offset', inst_name), counts.n_rf);

        check_numeric_vector(inst.rf_frequency_offset, ...
            sprintf('%s.rf_frequency_offset', inst_name), counts.n_rf);

        %% Gradient amplitudes

        check_gradient_amplitude(inst.gradient_amplitude, ...
            sprintf('%s.gradient_amplitude', inst_name), counts.n_grad);

        %% ADC arrays

        check_numeric_vector(inst.adc_phase_offset, ...
            sprintf('%s.adc_phase_offset', inst_name), counts.n_adc);

        check_numeric_vector(inst.adc_frequency_offset, ...
            sprintf('%s.adc_frequency_offset', inst_name), counts.n_adc);

        %% Optional rotation_matrix

        if isfield(inst, 'rotation_matrix') && ~isempty(inst.rotation_matrix)
            R = inst.rotation_matrix;

            assert(isnumeric(R) && ndims(R) <= 3 && size(R,1) == 3 && size(R,2) == 3, ...
                '%s.rotation_matrix must be a 3 x 3 x N numeric array, or a 3 x 3 matrix for a single gradient event.', ...
                inst_name);

            n_rotation_matrices = size(R, 3);

            assert(n_rotation_matrices == counts.n_grad, ...
                '%s.rotation_matrix must contain one 3x3 matrix per gradient event. Expected %d, found %d.', ...
                inst_name, counts.n_grad, n_rotation_matrices);

            assert(all(isfinite(R(:))), ...
                '%s.rotation_matrix contains non-finite values.', inst_name);
        end

        %% Optional physio_trigger

        if isfield(inst, 'physio_trigger') && ~isempty(inst.physio_trigger)
            assert(isnumeric(inst.physio_trigger) && isscalar(inst.physio_trigger), ...
                '%s.physio_trigger must be a scalar numeric value.', inst_name);

            assert(ismember(inst.physio_trigger, [0 1]), ...
                '%s.physio_trigger must be 0 or 1.', inst_name);
        end

        %% Optional label

        if isfield(inst, 'label') && ~isempty(inst.label)
            assert(ischar(inst.label) || isstring(inst.label), ...
                '%s.label must be a string if present.', inst_name);
        end
    end
end


function require_field(s, fieldname, object_name)
% REQUIRE_FIELD Assert that a struct contains a required field.

    assert(isstruct(s), ...
        '%s must be a struct.', object_name);

    assert(isfield(s, fieldname), ...
        '%s is missing required field "%s".', object_name, fieldname);
end


function check_numeric_vector(x, name, expected_n)
% CHECK_NUMERIC_VECTOR Validate a numeric vector with expected number of elements.
%
% Empty [] is allowed when expected_n == 0.

    if expected_n == 0
        assert(isempty(x), ...
            '%s must be empty because the referenced virtual segment contains no matching events.', ...
            name);
        return;
    end

    assert(isnumeric(x), ...
        '%s must be numeric.', name);

    assert(isvector(x), ...
        '%s must be a vector.', name);

    assert(numel(x) == expected_n, ...
        '%s has incorrect length. Expected %d, found %d.', ...
        name, expected_n, numel(x));

    assert(all(isfinite(x(:))), ...
        '%s contains non-finite values.', name);
end


function check_gradient_amplitude(g, name, expected_n)
% CHECK_GRADIENT_AMPLITUDE Validate gradient amplitude array.
%
% Expected representation is N x 3, where each row is:
%
%   [gx_scale, gy_scale, gz_scale]
%
% For a segment with no gradient events, [] is allowed.

    if expected_n == 0
        assert(isempty(g), ...
            '%s must be empty because the virtual segment contains no gradient events.', name);
        return;
    end

    assert(isnumeric(g), ...
        '%s must be numeric.', name);

    assert(ismatrix(g), ...
        '%s must be a 2D numeric array.', name);

    assert(size(g,1) == expected_n && size(g,2) == 3, ...
        '%s must be N x 3, with one [Gx Gy Gz] row per gradient event. Expected %d x 3, found %d x %d.', ...
        name, expected_n, size(g,1), size(g,2));

    assert(all(isfinite(g(:))), ...
        '%s contains non-finite values.', name);
end


function counts = count_events_in_virtual_segment(vs, base_blocks)
% COUNT_EVENTS_IN_VIRTUAL_SEGMENT Count RF, gradient, and ADC events in a virtual segment.

    ids = vs.base_block_ids;

    counts.n_blocks = numel(ids);
    counts.n_rf = 0;
    counts.n_grad = 0;
    counts.n_adc = 0;

    for j = 1:numel(ids)
        id = ids(j);

        % Reserved implicit delay blocks have no RF, gradient, or ADC event.
        if id == 0 || id == 1
            continue;
        end

        p = find([base_blocks.id] == id, 1);

        assert(~isempty(p), ...
            'Virtual segment references explicit base block ID %d, but no such base block exists.', id);

        b = base_blocks(p).block;

        if has_event(b, 'rf')
            counts.n_rf = counts.n_rf + 1;
        end

        if has_event(b, 'gx') || has_event(b, 'gy') || has_event(b, 'gz')
            counts.n_grad = counts.n_grad + 1;
        end

        if has_event(b, 'adc')
            counts.n_adc = counts.n_adc + 1;
        end
    end
end


function tf = has_event(b, fieldname)
% HAS_EVENT True if a Pulseq block contains a nonempty event field.

    tf = isstruct(b) && isfield(b, fieldname) && ~isempty(b.(fieldname));
end


function check_base_block_normalization(b, bb_name)
% CHECK_BASE_BLOCK_NORMALIZATION Light sanity checks for normalized BaseBlock waveforms.

    tol = 1e-9;

    %% RF

    if has_event(b, 'rf') && isfield(b.rf, 'signal') && ~isempty(b.rf.signal)
        rf_peak = max(abs(b.rf.signal(:)));

        assert(rf_peak <= 1 + tol, ...
            '%s.block.rf.signal appears not to be normalized. max(abs(signal)) = %.6g.', ...
            bb_name, rf_peak);

        if rf_peak > tol
            assert(abs(rf_peak - 1) <= tol, ...
                '%s.block.rf.signal is nonzero but peak is not 1. max(abs(signal)) = %.6g.', ...
                bb_name, rf_peak);
        end
    end

    %% Gradients

    grad_fields = {'gx', 'gy', 'gz'};

    for a = 1:numel(grad_fields)
        gname = grad_fields{a};

        if ~has_event(b, gname)
            continue;
        end

        g = b.(gname);

        if isfield(g, 'waveform') && ~isempty(g.waveform)
            g_peak = max(abs(g.waveform(:)));

            assert(g_peak <= 1 + tol, ...
                '%s.block.%s.waveform appears not to be normalized. max(abs(waveform)) = %.6g.', ...
                bb_name, gname, g_peak);

            if g_peak > tol
                assert(abs(g_peak - 1) <= tol, ...
                    '%s.block.%s.waveform is nonzero but peak is not 1. max(abs(waveform)) = %.6g.', ...
                    bb_name, gname, g_peak);
            end
        end

        if isfield(g, 'amplitude') && ~isempty(g.amplitude)
            amp = g.amplitude;

            assert(isscalar(amp), ...
                '%s.block.%s.amplitude must be scalar if present.', bb_name, gname);

            assert(abs(amp) <= 1 + tol, ...
                '%s.block.%s.amplitude appears not to be normalized. amplitude = %.6g.', ...
                bb_name, gname, amp);

            if abs(amp) > tol
                assert(abs(abs(amp) - 1) <= tol, ...
                    '%s.block.%s.amplitude is nonzero but magnitude is not 1. amplitude = %.6g.', ...
                    bb_name, gname, amp);
            end
        end
    end
end


function check_pulseq_block(b, block_name)
% CHECK_PULSEQ_BLOCK Validate that a BaseBlock.block has Pulseq-like structure.
%
% This is a structural validation, not a full Pulseq timing/safety check.
% It verifies that present events contain the minimum fields expected by
% pulseg.import(), stream2loop(), and downstream interpreters.

    assert(isstruct(b), ...
        '%s must be a struct containing Pulseq block fields.', block_name);

    % A Pulseq block should carry its duration.
    require_numeric_scalar_field(b, 'blockDuration', block_name);
    assert(b.blockDuration >= 0, ...
        '%s.blockDuration must be non-negative.', block_name);

    % RF event, if present.
    if has_event(b, 'rf')
        check_rf_event(b.rf, sprintf('%s.rf', block_name));
    end

    % Gradient events, if present.
    grad_fields = {'gx', 'gy', 'gz'};

    for a = 1:numel(grad_fields)
        gname = grad_fields{a};

        if has_event(b, gname)
            check_gradient_event(b.(gname), sprintf('%s.%s', block_name, gname));
        end
    end

    % ADC event, if present.
    if has_event(b, 'adc')
        check_adc_event(b.adc, sprintf('%s.adc', block_name));
    end

    % Optional trigger event.
    if has_event(b, 'trig')
        check_trigger_event(b.trig, sprintf('%s.trig', block_name));
    end

    % Optional rotation event.
    if has_event(b, 'rotation')
        check_rotation_event(b.rotation, sprintf('%s.rotation', block_name));
    end
end


function check_rf_event(rf, event_name)
% CHECK_RF_EVENT Validate required fields for a Pulseq RF event.

    assert(isstruct(rf), ...
        '%s must be a struct.', event_name);

    require_field(rf, 'signal', event_name);
    require_field(rf, 't', event_name);

    assert(isnumeric(rf.signal) && ~isempty(rf.signal), ...
        '%s.signal must be a non-empty numeric array.', event_name);

    assert(isnumeric(rf.t) && isvector(rf.t) && ~isempty(rf.t), ...
        '%s.t must be a non-empty numeric vector.', event_name);

    assert(all(isfinite(rf.signal(:))), ...
        '%s.signal contains non-finite values.', event_name);

    assert(all(isfinite(rf.t(:))) && all(rf.t(:) >= 0), ...
        '%s.t must contain finite, non-negative values.', event_name);

    % For single-channel RF, numel(t) usually equals numel(signal).
    % For pTx/multichannel RF, one dimension of signal should match numel(t).
    n_t = numel(rf.t);
    sig_size = size(rf.signal);

    assert(numel(rf.signal) == n_t || any(sig_size == n_t), ...
        ['%s.t length is not compatible with %s.signal size. ', ...
         'Expected numel(t) to match numel(signal) or one signal dimension.'], ...
        event_name, event_name);

    % Optional but common Pulseq RF scalar fields.
    check_optional_numeric_scalar_field(rf, 'delay', event_name, true);
    check_optional_numeric_scalar_field(rf, 'phaseOffset', event_name, false);
    check_optional_numeric_scalar_field(rf, 'freqOffset', event_name, false);
    check_optional_numeric_scalar_field(rf, 'deadTime', event_name, true);
    check_optional_numeric_scalar_field(rf, 'ringdownTime', event_name, true);

    % If use is present, it should be textual.
    if isfield(rf, 'use') && ~isempty(rf.use)
        assert(ischar(rf.use) || isstring(rf.use), ...
            '%s.use must be a string if present.', event_name);
    end
end


function check_gradient_event(g, event_name)
% CHECK_GRADIENT_EVENT Validate required fields for a Pulseq gradient event.
%
% Supports trapezoid/scalar-style gradients and arbitrary/sampled gradients.

    assert(isstruct(g), ...
        '%s must be a struct.', event_name);

    % Pulseq gradient events usually have a type field.
    if isfield(g, 'type') && ~isempty(g.type)
        assert(ischar(g.type) || isstring(g.type), ...
            '%s.type must be a string if present.', event_name);
    end

    has_waveform = isfield(g, 'waveform') && ~isempty(g.waveform);
    has_amplitude = isfield(g, 'amplitude') && ~isempty(g.amplitude);

    assert(has_waveform || has_amplitude, ...
        '%s must contain either waveform or amplitude.', event_name);

     % Arbitrary/sampled gradient.
    if has_waveform
        assert(isnumeric(g.waveform) && isvector(g.waveform), ...
            '%s.waveform must be a numeric vector.', event_name);

        assert(all(isfinite(g.waveform(:))), ...
            '%s.waveform contains non-finite values.', event_name);

        % Recent Pulseq versions require first/last values at raster edges.
        require_numeric_scalar_field(g, 'first', event_name);
        require_numeric_scalar_field(g, 'last', event_name);

        % Arbitrary gradients must include sample times.
        require_field(g, 'tt', event_name);

        assert(isnumeric(g.tt) && isvector(g.tt) && ~isempty(g.tt), ...
            '%s.tt must be a non-empty numeric vector for arbitrary gradients.', event_name);

        assert(all(isfinite(g.tt(:))) && all(g.tt(:) >= 0), ...
            '%s.tt must contain finite, non-negative values.', event_name);

        assert(numel(g.tt) == numel(g.waveform), ...
            '%s.tt must have the same number of samples as %s.waveform. Found %d and %d.', ...
            event_name, event_name, numel(g.tt), numel(g.waveform));

        tt = g.tt(:);
        assert(all(diff(tt) >= 0), ...
            '%s.tt must be monotonically nondecreasing.', event_name);

        % Optional alias/time-vector field, if present.
        if isfield(g, 't') && ~isempty(g.t)
            assert(isnumeric(g.t) && isvector(g.t), ...
                '%s.t must be a numeric vector if present.', event_name);

            assert(all(isfinite(g.t(:))) && all(g.t(:) >= 0), ...
                '%s.t must contain finite, non-negative values.', event_name);

            assert(numel(g.t) == numel(g.waveform), ...
                '%s.t must have the same number of samples as %s.waveform if present. Found %d and %d.', ...
                event_name, event_name, numel(g.t), numel(g.waveform));
        end
    end

    % Trapezoid/scalar gradient.
    if has_amplitude
        assert(isnumeric(g.amplitude) && isscalar(g.amplitude) && isfinite(g.amplitude), ...
            '%s.amplitude must be a finite numeric scalar.', event_name);

        % If this is a trap event, these timing fields should be present.
        if isfield(g, 'type') && strcmp(char(g.type), 'trap')
            require_numeric_scalar_field(g, 'riseTime', event_name);
            require_numeric_scalar_field(g, 'flatTime', event_name);
            require_numeric_scalar_field(g, 'fallTime', event_name);

            assert(g.riseTime >= 0 && g.flatTime >= 0 && g.fallTime >= 0, ...
                '%s riseTime/flatTime/fallTime must be non-negative.', event_name);
        end
    end

    % Common optional scalar fields.
    check_optional_numeric_scalar_field(g, 'delay', event_name, true);
    check_optional_numeric_scalar_field(g, 'area', event_name, false);
    check_optional_numeric_scalar_field(g, 'flatArea', event_name, false);
    check_optional_numeric_scalar_field(g, 'duration', event_name, true);
end


function check_adc_event(adc, event_name)
% CHECK_ADC_EVENT Validate required fields for a Pulseq ADC event.

    assert(isstruct(adc), ...
        '%s must be a struct.', event_name);

    require_numeric_scalar_field(adc, 'numSamples', event_name);
    require_numeric_scalar_field(adc, 'dwell', event_name);
    require_numeric_scalar_field(adc, 'delay', event_name);

    assert(adc.numSamples == floor(adc.numSamples) && adc.numSamples > 0, ...
        '%s.numSamples must be a positive integer.', event_name);

    assert(adc.dwell > 0, ...
        '%s.dwell must be positive.', event_name);

    assert(adc.delay >= 0, ...
        '%s.delay must be non-negative.', event_name);

    % Dynamic ADC offsets are required by PulSeg SegmentInstance, but in the
    % normalized BaseBlock they may be zeroed. They should be scalar if present.
    check_optional_numeric_scalar_field(adc, 'phaseOffset', event_name, false);
    check_optional_numeric_scalar_field(adc, 'freqOffset', event_name, false);
end


function check_trigger_event(trig, event_name)
% CHECK_TRIGGER_EVENT Validate optional Pulseq trigger event.

    assert(isstruct(trig), ...
        '%s must be a struct.', event_name);

    if isfield(trig, 'channel') && ~isempty(trig.channel)
        assert(ischar(trig.channel) || isstring(trig.channel), ...
            '%s.channel must be a string if present.', event_name);
    end

    check_optional_numeric_scalar_field(trig, 'delay', event_name, true);
    check_optional_numeric_scalar_field(trig, 'duration', event_name, true);
end


function check_rotation_event(rotation, event_name)
% CHECK_ROTATION_EVENT Validate optional Pulseq rotation event.

    assert(isstruct(rotation), ...
        '%s must be a struct.', event_name);

    if isfield(rotation, 'type') && ~isempty(rotation.type)
        assert(ischar(rotation.type) || isstring(rotation.type), ...
            '%s.type must be a string if present.', event_name);
    end

    if isfield(rotation, 'rotQuaternion') && ~isempty(rotation.rotQuaternion)
        q = rotation.rotQuaternion;

        assert(isnumeric(q) && numel(q) == 4 && all(isfinite(q(:))), ...
            '%s.rotQuaternion must be a finite numeric 4-vector if present.', event_name);
    end
end


function require_numeric_scalar_field(s, fieldname, object_name)
% REQUIRE_NUMERIC_SCALAR_FIELD Require a finite numeric scalar field.

    require_field(s, fieldname, object_name);

    assert(isnumeric(s.(fieldname)) && isscalar(s.(fieldname)) && isfinite(s.(fieldname)), ...
        '%s.%s must be a finite numeric scalar.', object_name, fieldname);
end


function check_optional_numeric_scalar_field(s, fieldname, object_name, require_nonnegative)
% CHECK_OPTIONAL_NUMERIC_SCALAR_FIELD Validate optional scalar numeric field.

    if nargin < 4
        require_nonnegative = false;
    end

    if ~isfield(s, fieldname) || isempty(s.(fieldname))
        return;
    end

    val = s.(fieldname);

    assert(isnumeric(val) && isscalar(val) && isfinite(val), ...
        '%s.%s must be a finite numeric scalar if present.', object_name, fieldname);

    if require_nonnegative
        assert(val >= 0, ...
            '%s.%s must be non-negative if present.', object_name, fieldname);
    end
end
