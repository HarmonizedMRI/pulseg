function loop = stream2loop(pulseg_ir, dt)
% STREAM2LOOP Build a 2D loop array from a PulSeg execution stream.
%
% Syntax:
%   loop = pulseg.stream2loop(pulseg_ir, dt)
%
% Input:
%   pulseg_ir
%       PulSeg IR struct with valid fields:
%
%           .execution_stream
%           .virtual_segments
%           .base_blocks
%
%   dt
%       Gradient raster time in seconds, used for gradient energy estimates
%       for arbitrary/sampled gradients. If omitted or empty, this function
%       tries to read:
%
%           pulseg_ir.raster_times.grad_raster_time
%
%       If no raster time is available and sampled gradient energy is
%       requested, an error is thrown.
%
% Output:
%   loop
%       Numeric array [nBlocks x 24], one row per Pulseq block.
%
%       Col  1: segmentID          virtual segment ID
%       Col  2: baseBlockID        base block ID
%       Col  3: rfamp              RF amplitude scale, 0 if no RF
%       Col  4: rfphs              RF phase offset in rad, 0 if no RF
%       Col  5: rffreq             RF frequency offset in Hz, 0 if no RF
%       Col  6: amp.gx             Gx amplitude scale, 0 if no Gx
%       Col  7: energy.gx          Gx gradient energy estimate
%       Col  8: amp.gy             Gy amplitude scale, 0 if no Gy
%       Col  9: energy.gy          Gy gradient energy estimate
%       Col 10: amp.gz             Gz amplitude scale, 0 if no Gz
%       Col 11: energy.gz          Gz gradient energy estimate
%       Col 12: adcphs             ADC receiver phase offset in rad, 0 if no ADC
%       Col 13: adcfreq            ADC receiver frequency offset in Hz, 0 if no ADC
%       Col 14: blockDuration      block duration in seconds
%       Col 15: physioTrigger      binary trigger flag, first block of instance only
%       Col 16-24: R(:)'           flattened 3x3 rotation matrix, row-major
%
% Notes:
%   - Reserved implicit delay base block IDs 0 and 1 have no RF, gradient,
%     or ADC events.
%   - Gradient amplitude is expected to be N x 3 in PulSeg 2.0-alpha, where
%     each row is [gx_scale, gy_scale, gz_scale] for one gradient event.
%   - Gradient energy is estimated from the normalized base block and scaled
%     by the square of the instance gradient amplitude.
%   - Rotation defaults to identity when no rotation_matrix is present.
%   - The loop format is a convenience/debug/legacy view of the execution
%     stream; the PulSeg IR remains the authoritative representation.

if nargin < 2
    dt = [];
end

if isempty(dt)
    dt = infer_grad_raster_time(pulseg_ir);
end

nCols = 24;

% Optional but useful during development.
if exist('pulseg.validate_ir', 'file') == 2
    pulseg.validate_ir(pulseg_ir);
end

%% Pre-count total number of blocks across all instances

nBlocks = 0;
nInstances = numel(pulseg_ir.execution_stream);

for k = 1:nInstances
    instance = pulseg_ir.execution_stream(k);
    seg = get_virtual_segment_by_id(pulseg_ir, instance.virtual_segment_id);
    nBlocks = nBlocks + numel(seg.base_block_ids);
end

loop = zeros(nBlocks, nCols);

R_identity_flat = flatten_rotation_row_major(eye(3));

%% Build loop rows

row = 1;

for k = 1:nInstances

    instance = pulseg_ir.execution_stream(k);
    segment_id = instance.virtual_segment_id;
    seg = get_virtual_segment_by_id(pulseg_ir, segment_id);

    nBlocksInSeg = numel(seg.base_block_ids);

    % Per-event counters within this instance.
    rf_idx   = 0;
    grad_idx = 0;
    adc_idx  = 0;
    rot_idx  = 0;

    for j = 1:nBlocksInSeg

        base_block_id = seg.base_block_ids(j);

        % Col 1: virtual segment ID.
        loop(row, 1) = segment_id;

        % Col 2: base block ID.
        loop(row, 2) = base_block_id;

        % Col 14: block duration.
        loop(row, 14) = instance.block_duration(j);

        % Col 15: physio trigger on first block of instance only.
        if j == 1 && isfield(instance, 'physio_trigger') && ~isempty(instance.physio_trigger)
            loop(row, 15) = instance.physio_trigger;
        end

        % Cols 16-24: rotation matrix, default identity.
        loop(row, 16:24) = R_identity_flat;

        % Pure delay blocks have no RF, gradient, or ADC events.
        if base_block_id == 0 || base_block_id == 1
            row = row + 1;
            continue;
        end

        % Look up explicit normalized base block.
        b = get_base_block_by_id(pulseg_ir, base_block_id);

        %% RF event

        if has_event(b, 'rf')
            rf_idx = rf_idx + 1;

            loop(row, 3) = instance.rf_amplitude(rf_idx);
            loop(row, 4) = instance.rf_phase_offset(rf_idx);
            loop(row, 5) = instance.rf_frequency_offset(rf_idx);
        end

        %% Gradient event

        has_grad = has_event(b, 'gx') || has_event(b, 'gy') || has_event(b, 'gz');

        if has_grad
            grad_idx = grad_idx + 1;

            grad_triplet = get_gradient_triplet(instance.gradient_amplitude, grad_idx);

            gx_scale = grad_triplet(1);
            gy_scale = grad_triplet(2);
            gz_scale = grad_triplet(3);

            if has_event(b, 'gx')
                loop(row, 6) = gx_scale;
                loop(row, 7) = get_grad_energy(b.gx, gx_scale, dt);
            end

            if has_event(b, 'gy')
                loop(row, 8) = gy_scale;
                loop(row, 9) = get_grad_energy(b.gy, gy_scale, dt);
            end

            if has_event(b, 'gz')
                loop(row, 10) = gz_scale;
                loop(row, 11) = get_grad_energy(b.gz, gz_scale, dt);
            end

            % Rotation matrix: one per gradient event.
            rot_idx = rot_idx + 1;

            if isfield(instance, 'rotation_matrix') && ~isempty(instance.rotation_matrix)
                R = get_rotation_matrix(instance.rotation_matrix, rot_idx);
                loop(row, 16:24) = flatten_rotation_row_major(R);
            end
        end

        %% ADC event

        if has_event(b, 'adc')
            adc_idx = adc_idx + 1;

            loop(row, 12) = instance.adc_phase_offset(adc_idx);
            loop(row, 13) = instance.adc_frequency_offset(adc_idx);
        end

        row = row + 1;
    end
end

assert(row == nBlocks + 1, ...
    'Internal error: expected to populate %d loop rows, populated %d.', ...
    nBlocks, row - 1);

return


function dt = infer_grad_raster_time(pulseg_ir)
% INFER_GRAD_RASTER_TIME Try to infer gradient raster time from PulSeg IR.

dt = [];

if isfield(pulseg_ir, 'raster_times') && ...
        isfield(pulseg_ir.raster_times, 'grad_raster_time') && ...
        ~isempty(pulseg_ir.raster_times.grad_raster_time)
    dt = pulseg_ir.raster_times.grad_raster_time;
    return;
end

if isfield(pulseg_ir, 'grad_raster_time') && ~isempty(pulseg_ir.grad_raster_time)
    dt = pulseg_ir.grad_raster_time;
    return;
end


function seg = get_virtual_segment_by_id(pulseg_ir, id)
% GET_VIRTUAL_SEGMENT_BY_ID Return virtual segment with matching ID.

ids = [pulseg_ir.virtual_segments.id];
idx = find(ids == id, 1);

assert(~isempty(idx), ...
    'Could not find virtual segment with id %d.', id);

seg = pulseg_ir.virtual_segments(idx);

return


function b = get_base_block_by_id(pulseg_ir, id)
% GET_BASE_BLOCK_BY_ID Return normalized base block with matching ID.

ids = [pulseg_ir.base_blocks.id];
idx = find(ids == id, 1);

assert(~isempty(idx), ...
    'Could not find explicit base block with id %d.', id);

b = pulseg_ir.base_blocks(idx).block;

return


function tf = has_event(b, fieldname)
% HAS_EVENT True if block contains a nonempty event field.

tf = isstruct(b) && isfield(b, fieldname) && ~isempty(b.(fieldname));

return


function grad_triplet = get_gradient_triplet(gradient_amplitude, grad_idx)
% GET_GRADIENT_TRIPLET Return [gx gy gz] for gradient event grad_idx.
%
% PulSeg 2.0-alpha representation is N x 3. For limited backward
% compatibility, this helper also accepts 3 x N.

assert(~isempty(gradient_amplitude), ...
    'gradient_amplitude is empty but a gradient event was encountered.');

if size(gradient_amplitude, 2) == 3
    assert(grad_idx <= size(gradient_amplitude, 1), ...
        'gradient_amplitude has too few rows for gradient event %d.', grad_idx);

    grad_triplet = gradient_amplitude(grad_idx, :);

elseif size(gradient_amplitude, 1) == 3
    assert(grad_idx <= size(gradient_amplitude, 2), ...
        'gradient_amplitude has too few columns for gradient event %d.', grad_idx);

    grad_triplet = gradient_amplitude(:, grad_idx).';

else
    error('gradient_amplitude must be N x 3, or legacy 3 x N.');
end

return


function R = get_rotation_matrix(rotation_matrix, rot_idx)
% GET_ROTATION_MATRIX Return the rot_idx-th 3x3 rotation matrix.
%
% Accepts:
%   3 x 3      for a single gradient event
%   3 x 3 x N  for N gradient events

assert(isnumeric(rotation_matrix), ...
    'rotation_matrix must be numeric.');

assert(size(rotation_matrix, 1) == 3 && size(rotation_matrix, 2) == 3, ...
    'rotation_matrix must have size 3 x 3 x N.');

if ndims(rotation_matrix) == 2
    assert(rot_idx == 1, ...
        'rotation_matrix contains one 3x3 matrix, but requested matrix %d.', rot_idx);

    R = rotation_matrix;
else
    assert(rot_idx <= size(rotation_matrix, 3), ...
        'rotation_matrix has too few matrices for gradient event %d.', rot_idx);

    R = rotation_matrix(:, :, rot_idx);
end

return


function r = flatten_rotation_row_major(R)
% FLATTEN_ROTATION_ROW_MAJOR Flatten 3x3 matrix in row-major order.
%
% MATLAB's R(:)' is column-major. Row-major flattening is reshape(R.',1,[]).

assert(all(size(R) == [3 3]), ...
    'Rotation matrix must be 3 x 3.');

r = reshape(R.', 1, []);

return


function E = get_grad_energy(g, scale, dt)
% GET_GRAD_ENERGY Estimate physical gradient energy for one axis.
%
% For sampled gradients:
%
%   E = sum((scale * normalized_waveform).^2) * dt
%
% For trapezoid/scalar gradients with timing fields:
%
%   E = A^2 * (flatTime + riseTime/3 + fallTime/3)
%
% where A = scale * normalized_amplitude.
%
% Units are approximately (gradient unit)^2 * seconds. If scale is in T/m,
% energy is (T/m)^2*s.

E = 0;

if isempty(g) || scale == 0
    return;
end

%% Sampled/arbitrary gradient

if isfield(g, 'waveform') && ~isempty(g.waveform)
    assert(~isempty(dt), ...
        ['Gradient raster time dt is required to compute energy for sampled ', ...
         'gradient waveforms. Call stream2loop(pulseg_ir, dt), or provide ', ...
         'pulseg_ir.raster_times.grad_raster_time.']);

    waveform_physical = scale * g.waveform(:);
    E = sum(waveform_physical.^2) * dt;
    return;
end

%% Trapezoid/scalar gradient

if isfield(g, 'amplitude') && ~isempty(g.amplitude)
    A = scale * g.amplitude;

    if isfield(g, 'riseTime') && isfield(g, 'flatTime') && isfield(g, 'fallTime')
        E = A.^2 * (g.flatTime + g.riseTime/3 + g.fallTime/3);
        return;
    end

    if isfield(g, 'duration') && ~isempty(g.duration)
        E = A.^2 * g.duration;
        return;
    end
end

% If no usable timing/waveform representation exists, leave energy at 0.
return
