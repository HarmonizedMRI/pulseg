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
%   usesRotationEvents    TRUE/false    If false, this script tries to estimate 
%                                       in plane (2D, x-y) rotations from the gradient shapes.
% Output
%   pulseg_ir        PulSeq sequence struct, see github/HarmonizedMRI/pulseg/docs/spec.md

% Definitions:
% n, row        row index in .seq file
% i             segment array index, starting from 1
% j             block number within a segment, starting from 1
% s             virtual segment index, starting from 1

import pulseg.*

pulseg_ir.pulseg_version = '2.0';

if ischar(seqarg) || isstring(seqarg)
    pulseg_ir.source_file = char(seqarg);
end

pulseg_ir.creation_date = char(datetime('today', 'Format', 'yyyy-MM-dd'));

% default inputs and user-specified overrides
arg.verbose = false;
arg.usesRotationEvents = true;
arg = vararg_pair(arg, varargin);


%% Get seq object
if isa(seqarg, 'char')
    fprintf(sprintf('Reading %s ... ', seqarg));
    seq = mr.Sequence();
    seq.read(seqarg);
    fprintf(' done\n');
else
    assert(isa(seqarg, 'mr.Sequence'), 'First argument is not an mr.Sequence object');
    seq = seqarg;
end

nEvents = 7;   % Pulseq 1.4.0 
blockEvents = cell2mat(seq.blockEvents);
blockEvents = reshape(blockEvents, [nEvents, length(seq.blockEvents)]).'; 

% number of blocks (rows in .seq file) to step through
pulseg_ir.nMax = size(blockEvents, 1);


%% Get TRID labels and corresponding row indices for all segment instances
n_trid_labels = 0;
textprogressbar('import(): Reading TRID labels and counting ADC events: ');
pulseg_ir.n_adc = 0;
for n = 1:pulseg_ir.nMax
    textprogressbar(n/pulseg_ir.nMax*100);

    b = seq.getBlock(n);

    if ~isempty(b.adc)
        pulseg_ir.n_adc = pulseg_ir.n_adc + 1;
    end

    % get TRID label if present
    if isfield(b, 'label') 
        for ii = 1:length(b.label)
            if strcmp(b.label(ii).label, 'TRID')
                n_trid_labels = n_trid_labels + 1;
                tridLabels.val(n_trid_labels) = b.label(ii).value;
                trids(n) = b.label(ii).value;
                tridLabels.index(n_trid_labels) = n;
                break;
            end
        end
    end
end
textprogressbar(''); 

%% Initialize virtual segments
[uniqueTridLabels, I] = unique(tridLabels.val);
n_blocks_per_trid_label = diff([tridLabels.index pulseg_ir.nMax+1]);

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
n = tridLabels.index(1);  % start of first segment instance

while n < pulseg_ir.nMax + 1
    i = find(uniqueTridLabels == trids(n));  % segment array index

    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment

        b = seq.getBlock(n);
        T = getblocktype(b);

        if blockDuration(i,j) == -1
            blockDuration(i,j) = b.blockDuration;  % first instance of block (i,j)
        else
            if b.blockDuration ~= blockDuration(i,j)  % duration is different from a previous instance
                if T(4)
                    isVariableDelay(i,j) = true;
                    n = n + 1;
                    continue;  % go to next j iteration
                else
                    error(sprintf('(row %d: segment %d, block %d) Non-delay blocks must have the same duration in all segment instances', n, i, j));
                end
            end
        end
        n = n + 1;
    end
end


%% Get base blocks, by parsing first instance of each segment

for i = 1:n_segments

    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment

        n = pulseg_ir.virtual_segments(i).rows(j);  % row index in .seq file

        b = seq.getBlock(n);
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
        issame = false;
        for p = 1:pulseg_ir.n_base_blocks
            np = pulseg_ir.base_blocks(p).row; 
            if compareblocks(seq, blockEvents(n,:), blockEvents(np,:), n, np)
                issame = true;
                pulseg_ir.virtual_segments(i).base_block_ids(j) = pulseg_ir.base_blocks(p).id;
                break;
            end
        end

        % If not similar, add as a new base block
        if ~issame
            if arg.verbose
                fprintf('\nFound new base block on line %d\n', n);
            end
            pulseg_ir.n_base_blocks = pulseg_ir.n_base_blocks + 1;
            pnew = pulseg_ir.n_base_blocks;
            assigned_id = pnew + 1;  % gives 2, 3, 4, ...
            pulseg_ir.base_blocks(pulseg_ir.n_base_blocks).row = n;
            pulseg_ir.base_blocks(pulseg_ir.n_base_blocks).block = normalize_block(b);
            pulseg_ir.base_blocks(pulseg_ir.n_base_blocks).id = assigned_id;
            pulseg_ir.virtual_segments(i).base_block_ids(j) = assigned_id;
        end
    end
end


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
    'block_duration', cell(1, nInstances), ...
    'rotation_matrix', cell(1, nInstances), ...
    'physio_trigger', cell(1, nInstances) ...
);

% While stepping through the sequence timeline row by row:
instance_idx = 1;
n = tridLabels.index(1);

textprogressbar('import(): Getting dynamic scan information: ');

while n < pulseg_ir.nMax + 1
    textprogressbar(n/pulseg_ir.nMax*100);
    i = find(uniqueTridLabels == trids(n)); % Segment definition lookup

    % Initialize instance collector arrays
    rf_amp = []; rf_phase = []; rf_freq = [];
    grad_amp = []; adc_phase = []; durations = [];
    R = [];
    physio_trig_flag = 0;

    % Step through the blocks contained inside this specific segment instance
    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment
        b = seq.getBlock(n);

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
            rf_amp(end+1) = max(abs(b.rf.signal)); % Scale factor calculation
            rf_phase(end+1) = b.rf.phaseOffset;
            rf_freq(end+1) = b.rf.freqOffset;
        end

        % Extract Gradient scaling triplets (Gx, Gy, Gz)
        if ~isempty(b.gx) || ~isempty(b.gy) || ~isempty(b.gz)
            grad_amp(:, end+1) = [get_grad_scale(b.gx); get_grad_scale(b.gy); get_grad_scale(b.gz)];
        end

        % Extract ADC phase offsets
        if ~isempty(b.adc)
            adc_phase(end+1) = b.adc.phaseOffset;
        end

        % Extract rotation matrix
        if isfield(b, 'rotation')
            if strcmp(b.rotation.type, 'rot3D')
                R(:,:,end+1) = mr.aux.quat.toRotMat(b.rotation.rotQuaternion);
            end
        else
            R(:,:,end+1) = eye(3); 
        end

        n = n + 1;
    end

    % Populate the finalized instance structure
    pulseg_ir.execution_stream(instance_idx).virtual_segment_id = i;
    pulseg_ir.execution_stream(instance_idx).rf_amplitude = rf_amp;
    pulseg_ir.execution_stream(instance_idx).rf_phase_offset = rf_phase;
    pulseg_ir.execution_stream(instance_idx).rf_frequency_offset = rf_freq;
    pulseg_ir.execution_stream(instance_idx).gradient_amplitude = grad_amp;
    pulseg_ir.execution_stream(instance_idx).adc_phase_offset = adc_phase;
    pulseg_ir.execution_stream(instance_idx).block_duration = durations;
    pulseg_ir.execution_stream(instance_idx).physio_trigger = physio_trig_flag;
    pulseg_ir.execution_stream(instance_idx).rotation_matrix = R; % Packed 3x3

    instance_idx = instance_idx + 1;
end
textprogressbar(100);
textprogressbar('');


%% Set sequence duration
pulseg_ir.duration = seq.duration;

return

%% Gradient heating related calculations

% Get block/row index corresponding to the beginning of the segment instance
% instance with the largest combined (all axes) gradient energy.

% initialize max energy field
for i = 1:n_segments
    pulseg_ir.virtual_segments(i).Emax.val = 0;
    pulseg_ir.virtual_segments(i).Emax.n = 1;
end
   
% find segment instance with max energy
n = 1;
while n < pulseg_ir.nMax
    % Calculate total energy in segment instance
    i = pulseg_ir.loop(n, 1);  % segment index
    Etmp.gx = 0; Etmp.gy = 0; Etmp.gz = 0;
    nFirst = n;
    for j = 1:pulseg_ir.virtual_segments(i).n_blocks_in_segment  
        Etmp.gx = Etmp.gx + pulseg_ir.loop(n, 11);
        Etmp.gy = Etmp.gy + pulseg_ir.loop(n, 12);
        Etmp.gz = Etmp.gz + pulseg_ir.loop(n, 13);
        n = n + 1;
    end
    Etmp.all = Etmp.gx + Etmp.gy + Etmp.gz;

    % update Emax field
    if Etmp.all > pulseg_ir.virtual_segments(i).Emax.val
        pulseg_ir.virtual_segments(i).Emax.n = nFirst;
        pulseg_ir.virtual_segments(i).Emax.val = Etmp.all;
    end
end

