function pulseg_ir = import(seqarg, varargin)
% IMPORT Convert a Pulseq (.seq) file or sequence object to a PulSeg IR struct.
%
% Syntax:
%   pulseg_ir = pulseg.import(seq)
%
% Input
%   seq      A Pulseq sequence object, or name of a .seq file
%
% Input options with defaults
%   verbose               true/FALSE    Print some info to the terminal
% Output
%   pulseg_ir        PulSeq IR struct, see github/HarmonizedMRI/pulseg/docs/spec.md

% Definitions:
% row           row index in .seq file
% i             segment array index, starting from 1
% j             block number within a segment, starting from 1
% s             virtual segment index, starting from 1

import pulseg.*

pulseg_ir.pulseg_version = '2.0-alpha';

pulseg_ir.creation_date = char(datetime('today', 'Format', 'yyyy-MM-dd'));

% default inputs and user-specified overrides
arg.verbose = false;
arg = vararg_pair(arg, varargin);

%% Get seq object
if ischar(seqarg) || isstring(seqarg)
    pulseg_ir.source_file = char(seqarg);
    seqfile = char(seqarg);
    if arg.verbose, fprintf('Reading %s ... ', seqfile); end
    seq = mr.Sequence();
    seq.read(seqfile);
    if arg.verbose, fprintf(' done\n'); end
else
    assert(isa(seqarg, 'mr.Sequence'), 'First argument is not an mr.Sequence object');
    seq = seqarg;
end

nEvents = 7;   % Pulseq 1.4.0 
blockEvents = cell2mat(seq.blockEvents);
blockEvents = reshape(blockEvents, [nEvents, length(seq.blockEvents)]).'; 

% number of blocks (rows in .seq file) to step through
pulseg_ir.n_blocks = size(blockEvents, 1);


%% Get TRID labels and corresponding row indices for all segment instances
n_trid_labels = 0;
textprogressbar('import(): Reading TRID labels and counting ADC events: ');
pulseg_ir.n_adc = 0;
trids = nan(1, pulseg_ir.n_blocks);
tridLabels.val = [];
tridLabels.index = [];
for row = 1:pulseg_ir.n_blocks
    textprogressbar(row/pulseg_ir.n_blocks*100);

    b = seq.getBlock(row);

    if ~isempty(b.adc)
        pulseg_ir.n_adc = pulseg_ir.n_adc + 1;
    end

    % get TRID label if present
    if isfield(b, 'label') 
        for ii = 1:length(b.label)
            if strcmp(b.label(ii).label, 'TRID')
                n_trid_labels = n_trid_labels + 1;
                tridLabels.val(n_trid_labels) = b.label(ii).value;
                trids(row) = b.label(ii).value;
                tridLabels.index(n_trid_labels) = row;
                break;
            end
        end
    end
end
textprogressbar(''); 

assert(n_trid_labels > 0, ...
    'No TRID labels found. PulSeg import requires segment boundary labels.');

assert(tridLabels.index(1) == 1, ...
    'First block must contain a TRID label. Unlabeled preamble blocks are not currently supported.');

%% Initialize virtual segments
% Each TRID label is interpreted as the start of a new segment instance.
% Blocks between consecutive TRID labels belong to the preceding instance.
[uniqueTridLabels, I] = unique(tridLabels.val);
n_blocks_per_trid_label = diff([tridLabels.index pulseg_ir.n_blocks+1]);

n_segments = length(uniqueTridLabels);

for i = 1:n_segments
    nBlocks = n_blocks_per_trid_label(I(i));

    pulseg_ir.virtual_segments(i).id = i;
    pulseg_ir.virtual_segments(i).base_block_ids = zeros(1, nBlocks);
    pulseg_ir.virtual_segments(i).name = sprintf('TRID_%d', tridLabels.val(I(i)));

    % Optional metadata
    pulseg_ir.virtual_segments(i).n_blocks_in_segment = nBlocks;
    pulseg_ir.virtual_segments(i).TRID = tridLabels.val(I(i));
    pulseg_ir.virtual_segments(i).rows = tridLabels.index(I(i)) + (0:nBlocks-1);
end

% Check that each segment instance for a given TRID has the same number of blocks
for k = 1:length(tridLabels.val)
    trid = tridLabels.val(k);
    i = find(uniqueTridLabels == trid, 1);

    expected_n = pulseg_ir.virtual_segments(i).n_blocks_in_segment;
    actual_n = n_blocks_per_trid_label(k);

    assert(actual_n == expected_n, ...
        'TRID %d has inconsistent segment length at occurrence %d: expected %d blocks, found %d.', ...
        trid, k, expected_n, actual_n);
end


%% Detect variable delay blocks
pulseg_ir.n_base_blocks = 0;
max_n_blocks_in_segment = 0;
for i = 1:n_segments
    if pulseg_ir.virtual_segments(i).n_blocks_in_segment > max_n_blocks_in_segment
        max_n_blocks_in_segment = pulseg_ir.virtual_segments(i).n_blocks_in_segment;
    end
end
isVariableDelay = false(n_segments, max_n_blocks_in_segment);
blockDuration = -ones(n_segments, max_n_blocks_in_segment); % block instance durations
row = tridLabels.index(1);  % start of first segment instance

while row < pulseg_ir.n_blocks + 1
    i = find(uniqueTridLabels == trids(row));  % segment array index

    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment

        b = seq.getBlock(row);
        T = getblocktype(b);

        if blockDuration(i,j) == -1
            blockDuration(i,j) = b.blockDuration;  % first instance of block (i,j)
        else
            duration_tol = 1e-12;
            if abs(b.blockDuration - blockDuration(i,j)) > duration_tol  % duration is different from a previous instance
                if T(4)
                    isVariableDelay(i,j) = true;
                    row = row + 1;
                    continue;  % go to next j iteration
                else
                    error('(row %d: segment %d, block %d) Non-delay blocks must have the same duration in all segment instances', row, i, j);
                end
            end
        end
        row = row + 1;
    end
end


%% Get base blocks, by parsing first instance of each segment

for i = 1:n_segments

    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment

        row = pulseg_ir.virtual_segments(i).rows(j);  % row index in .seq file

        b = seq.getBlock(row);
        T = getblocktype(b);

        % Pure delay block identification
        if T(4) == 1
            if isVariableDelay(i,j)
                pulseg_ir.virtual_segments(i).base_block_ids(j) = 1; % Implicit Variable Delay
            else
                pulseg_ir.virtual_segments(i).base_block_ids(j) = 0; % Implicit Constant Delay
            end
            continue;
        end

        % Not a pure delay block.
        % Now check if block is similar to an existing base block

        [b0_candidate, ~] = pulseg.normalize_block(b);

        issame = false;
        for p = 1:pulseg_ir.n_base_blocks
            b0_existing = pulseg_ir.base_blocks(p).block;

            if pulseg.compare_normalized_blocks(b0_candidate, b0_existing)
                issame = true;
                pulseg_ir.virtual_segments(i).base_block_ids(j) = pulseg_ir.base_blocks(p).id;
                break;
            end
        end

        % If not similar, add as a new base block
        if ~issame
            if arg.verbose
                fprintf('\nFound new base block on line %d\n', row);
            end
            pulseg_ir.n_base_blocks = pulseg_ir.n_base_blocks + 1;
            pnew = pulseg_ir.n_base_blocks;
            assigned_id = pnew + 1;  % gives 2, 3, 4, ...
            pulseg_ir.base_blocks(pnew).row = row;              % optional metadata
            pulseg_ir.base_blocks(pnew).block = b0_candidate;
            pulseg_ir.base_blocks(pnew).id = assigned_id;
            pulseg_ir.base_blocks(pnew).name = sprintf('base_block_%d', assigned_id);

            pulseg_ir.virtual_segments(i).base_block_ids(j) = assigned_id;
        end
    end
end

assert(isfield(pulseg_ir, 'base_blocks') && ~isempty(pulseg_ir.base_blocks), ...
    'PulSeg 2.0 requires at least one explicit base block.');


%% Create execution_stream per PulSeg 2.0 specification

% Pre-allocate the structured array of segment instances
nInstances = length(tridLabels.val);
pulseg_ir.execution_stream = struct(...
    'virtual_segment_id', cell(1, nInstances), ...
    'rf_amplitude', cell(1, nInstances), ...
    'rf_phase_offset', cell(1, nInstances), ...
    'rf_frequency_offset', cell(1, nInstances), ...
    'gradient_amplitude', cell(1, nInstances), ...
    'adc_phase_offset', cell(1, nInstances), ...
    'adc_frequency_offset', cell(1, nInstances), ...
    'block_duration', cell(1, nInstances), ...
    'rotation_matrix', cell(1, nInstances), ...
    'physio_trigger', cell(1, nInstances) ...
);

% Step through the sequence timeline row by row
instance_idx = 1;
row = tridLabels.index(1);

textprogressbar('import(): Getting dynamic scan information: ');

while row < pulseg_ir.n_blocks + 1

    textprogressbar(row/pulseg_ir.n_blocks*100);

    i = find(uniqueTridLabels == trids(row)); % Segment definition lookup

    % Initialize instance collector arrays
    rf_amp = [];
    rf_phase = [];
    rf_freq = [];

    adc_phase = [];
    adc_freq = [];

    grad_amp = zeros(0, 3);
    durations = [];

    R = zeros(3, 3, 0);

    physio_trig_flag = 0;

    % Step through the blocks contained inside this specific segment instance
    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment

        b = seq.getBlock(row);

        % normalize and verify that the current physical block matches the virtual segment’s base block after normalization
        [b0_instance, scales] = pulseg.normalize_block(b);

        base_id = pulseg_ir.virtual_segments(i).base_block_ids(j);

        if base_id >= 2
            p = find([pulseg_ir.base_blocks.id] == base_id, 1);
            assert(~isempty(p), 'Could not find base block ID %d.', base_id);

            assert(pulseg.compare_normalized_blocks(b0_instance, pulseg_ir.base_blocks(p).block), ...
                'Block %d does not match normalized base block ID %d.', row, base_id);
        end

        % Accumulate per-event parameters as specified in spec.md Section 3.3
        durations(end+1) = b.blockDuration;

        % Cardiac trigger
        if isfield(b, 'trig') && ~isempty(b.trig) && ~physio_trig_flag
            if isfield(b.trig, 'channel') && strcmp(b.trig.channel, 'physio1')
                physio_trig_flag = 1;
            end
        end

        % Extract RF scales if present
        if ~isempty(b.rf)
            rf_amp(end+1) = scales.rf;
            rf_phase(end+1) = getfield_default(b.rf, 'phaseOffset', 0);
            rf_freq(end+1) = getfield_default(b.rf, 'freqOffset', 0);
        end

        % Extract Gradient scaling triplets (Gx, Gy, Gz) and rotation
        has_grad = ~isempty(b.gx) || ~isempty(b.gy) || ~isempty(b.gz);

        if has_grad
            grad_amp(end+1, :) = scales.grad;

            if isfield(b, 'rotation') && ~isempty(b.rotation)
                if isfield(b.rotation, 'type') && strcmp(b.rotation.type, 'rot3D')
                    R(:,:,end+1) = mr.aux.quat.toRotMat(b.rotation.rotQuaternion);
                else
                    R(:,:,end+1) = eye(3);
                end
            else
                R(:,:,end+1) = eye(3);
            end
        end

        % Extract ADC phase offsets
        if ~isempty(b.adc)
            adc_phase(end+1) = getfield_default(b.adc, 'phaseOffset', 0);
            adc_freq(end+1) = getfield_default(b.adc, 'freqOffset', 0);
        end

        row = row + 1;
    end

    % Populate the finalized instance structure
    pulseg_ir.execution_stream(instance_idx).virtual_segment_id = pulseg_ir.virtual_segments(i).id;
    pulseg_ir.execution_stream(instance_idx).rf_amplitude = rf_amp;
    pulseg_ir.execution_stream(instance_idx).rf_phase_offset = rf_phase;
    pulseg_ir.execution_stream(instance_idx).rf_frequency_offset = rf_freq;
    pulseg_ir.execution_stream(instance_idx).gradient_amplitude = grad_amp;
    pulseg_ir.execution_stream(instance_idx).adc_phase_offset = adc_phase;
    pulseg_ir.execution_stream(instance_idx).adc_frequency_offset = adc_freq;
    pulseg_ir.execution_stream(instance_idx).block_duration = durations;
    pulseg_ir.execution_stream(instance_idx).physio_trigger = physio_trig_flag;
    pulseg_ir.execution_stream(instance_idx).rotation_matrix = R; % Packed 3x3

    instance_idx = instance_idx + 1;
end
textprogressbar(100);
textprogressbar('');

%% Set sequence duration
pulseg_ir.duration = seq.duration;

%% Validate the structure against the PulSeg 2.0-alpha specification
pulseg.validate_ir(pulseg_ir);

return

function val = getfield_default(s, fieldname, default)
% GETFIELD_DEFAULT Return a struct field value or a default if absent/empty.
    if isfield(s, fieldname) && ~isempty(s.(fieldname))
        val = s.(fieldname);
    else
        val = default;
    end
return
