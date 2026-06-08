function loop = stream2loop(pulseg_ir)
% STREAM2LOOP Build a 2D loop array from a PulSeg execution stream.
%
% Syntax:
%   loop = pulseg.stream2loop(pulseg_ir)
%
% Input
%   pulseg_ir    PulSeg IR struct with valid fields:
%                  .execution_stream   (per spec v2.0, Section 3.3)
%                  .virtual_segments   (per spec v2.0, Section 3.2)
%                  .base_blocks        (per spec v2.0, Section 3.1)
%                  .opts               mr.opts() struct, must contain
%                                      .gradRasterTime in seconds
%
% Output
%   loop         2D numeric array [nBlocks x 23], one row per Pulseq block.
%
%                Col  1: segmentID          virtual segment ID
%                Col  2: parentBlockID      base block ID
%                Col  3: rfamp              RF amplitude scale (0 if no RF)
%                Col  4: rfphs              RF phase offset in rad (0 if no RF)
%                Col  5: rffreq             RF frequency offset in Hz (0 if no RF)
%                Col  6: amp.gx             Gx amplitude scale (0 if no Gx)
%                Col  7: energy.gx          Gx gradient energy in (T/m)^2*s (0 if no Gx)
%                Col  8: amp.gy             Gy amplitude scale (0 if no Gy)
%                Col  9: energy.gy          Gy gradient energy in (T/m)^2*s (0 if no Gy)
%                Col 10: amp.gz             Gz amplitude scale (0 if no Gz)
%                Col 11: energy.gz          Gz gradient energy in (T/m)^2*s (0 if no Gz)
%                Col 12: recphs             ADC receiver phase offset in rad (0 if no ADC)
%                Col 13: blockDuration      block duration in seconds
%                Col 14: physioTrigger      binary trigger flag (first block of instance only)
%                Col 15-23: R(:)'           flattened 3x3 rotation matrix (row-major)
%
% Notes
%   - Gradient energy is computed as sum(waveform.^2) * dt for the normalized
%     base block waveform, scaled by the gradient amplitude factor squared.
%   - physioTrigger is placed on the first block row of each segment instance only.
%   - R defaults to eye(3) (cols 15-23 = [1 0 0 0 1 0 0 0 1]) if no rotation is present.

% Validate that opts is present and contains gradRasterTime
assert(isfield(pulseg_ir, 'opts'), ...
    'stream2loop: pulseg_ir.opts is missing. Set pulseg_ir.opts = mr.opts() before calling this function.');
assert(isfield(pulseg_ir.opts, 'gradRasterTime'), ...
    'stream2loop: pulseg_ir.opts.gradRasterTime is missing. Ensure mr.opts() returns a valid options struct.');

nCols = 23;
dt = pulseg_ir.opts.gradRasterTime;

% Pre-count total number of blocks across all instances
nBlocks = 0;
nInstances = length(pulseg_ir.execution_stream);
for k = 1:nInstances
    i = pulseg_ir.execution_stream(k).virtual_segment_id;
    nBlocks = nBlocks + pulseg_ir.virtual_segments(i).n_blocks_in_segment;
end

loop = zeros(nBlocks, nCols);

% Pre-flatten identity rotation matrix for default assignment
R_identity_flat = eye(3);
R_identity_flat = R_identity_flat(:)';   % [1 0 0 0 1 0 0 0 1]

row = 1;
for k = 1:nInstances

    instance = pulseg_ir.execution_stream(k);
    i = instance.virtual_segment_id;
    seg = pulseg_ir.virtual_segments(i);
    nBlocksInSeg = seg.n_blocks_in_segment;

    % Per-event counters within this instance
    rf_idx   = 0;
    grad_idx = 0;
    adc_idx  = 0;
    rot_idx  = 0;

    for j = 1:nBlocksInSeg

        base_block_id = seg.blockIDs(j);

        % Col 1: virtual segment id
        loop(row, 1) = i;

        % Col 2: base block id
        loop(row, 2) = base_block_id;

        % Col 13: block duration
        loop(row, 13) = instance.block_duration(j);

        % Col 14: physio trigger (first block of instance only)
        if j == 1
            loop(row, 14) = instance.physio_trigger;
        end

        % Cols 15-23: rotation matrix (default to identity)
        loop(row, 15:23) = R_identity_flat;

        % Pure delay blocks (reserved IDs 0 and 1) have no events
        if base_block_id <= 1
            row = row + 1;
            continue;
        end

        % Look up the base block
        p = find([pulseg_ir.base_blocks.ID] == base_block_id);
        b = pulseg_ir.base_blocks(p).block;

        % Cols 3-5: RF parameters
        if ~isempty(b.rf)
            rf_idx = rf_idx + 1;
            loop(row, 3) = instance.rf_amplitude(rf_idx);
            loop(row, 4) = instance.rf_phase_offset(rf_idx);
            loop(row, 5) = instance.rf_frequency_offset(rf_idx);
        end

        % Cols 6-7: Gx amplitude and energy
        if ~isempty(b.gx)
            grad_idx = grad_idx + 1;
            gx_scale = instance.gradient_amplitude(1, grad_idx);
            loop(row, 6) = gx_scale;
            loop(row, 7) = get_grad_energy(b.gx, gx_scale, dt);
        end

        % Cols 8-9: Gy amplitude and energy
        if ~isempty(b.gy)
            gy_scale = instance.gradient_amplitude(2, grad_idx);
            loop(row, 8) = gy_scale;
            loop(row, 9) = get_grad_energy(b.gy, gy_scale, dt);
        end

        % Cols 10-11: Gz amplitude and energy
        if ~isempty(b.gz)
            gz_scale = instance.gradient_amplitude(3, grad_idx);
            loop(row, 10) = gz_scale;
            loop(row, 11) = get_grad_energy(b.gz, gz_scale, dt);
        end

        % Col 12: ADC receiver phase
        if ~isempty(b.adc)
            adc_idx = adc_idx + 1;
            loop(row, 12) = instance.adc_phase_offset(adc_idx);
        end

        % Cols 15-23: rotation matrix
        if ~isempty(instance.rotation_matrix)
            rot_idx = rot_idx + 1;
            if rot_idx <= size(instance.rotation_matrix, 3)
                R = instance.rotation_matrix(:,:,rot_idx);
                loop(row, 15:23) = R(:)';
            end
        end

        row = row + 1;
    end
end
end

