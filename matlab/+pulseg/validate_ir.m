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
%   This validator assumes the PulSeg 2.0-alpha spec explicitly requires both:
%
%       rf_frequency_offset
%       adc_frequency_offset
%
%   where rf_frequency_offset contains one entry per RF event and
%   adc_frequency_offset contains one entry per ADC event.
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
        'base_blocks must be non-empty for PulSeg 2.0.');

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
